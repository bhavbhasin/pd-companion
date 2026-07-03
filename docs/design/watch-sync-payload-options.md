# Watch → Phone Sync — Payload Reliability: Options & Failure Modes

**Status:** analysis only. No code. Decision pending. (Jul 2 2026)

## Verified facts (grounded in logs + code)

1. The watch re-sends a **fixed 48h window** on every autonomous push (`pushLatestContext`, `queryAndSync`) — independent of what the phone already has.
2. Build 6 (`7c91fab`) widened `TremorSample` 4 → 11 fields (~3× per sample). 48h × fat samples ≈ **1 MB** (log: `t=2772 d=2772`, `1017KB`).
3. `updateApplicationContext` has a hard size cap (~256 KB, exact TBD) → **`PayloadTooLarge`**. Consequence: the ambient backbone is effectively dead for **any** user past ~12h of history, not only after a gap. The phone's `Application context data is nil` *is* this failure — the context was never set.
4. Fallback is `transferUserInfo` (~1 MB in the log).
5. The phone persists incoming samples by **de-duplicating on `timestamp`** → **re-sending the same sample is harmless.** This is the load-bearing property for any reliable design.
6. Movement Disorder API retains only **~7 rolling days** → a hard ceiling on the largest possible backfill. The transfer can never exceed 7 days of samples, no matter how much total history exists.

## Open question that forks the design (Gap 1 — NOT verified)

Does a large `transferUserInfo` / `transferFile` **actually deliver** (just slowly), or can iOS silently drop/defer it indefinitely?
- **Delivers** → bulk transport is fine; keep each item under cap, let dedup absorb overlap.
- **Can silently drop** → we need delivery-confirmation + retry, not merely smaller payloads.

Each option marks its dependency. **Confirm before committing** — on the attached phone, after a `[sync] … queued` line, look for a later `[sync] processTremorData received=`.

## Design axes & priority

Selection (what to send) × Encoding (how packed) × Transport (which WC channel) × Chunking.
Priority for this foundation: **reliability > simplicity > bandwidth/battery.**

## Adversarial cases every option is tested against

A. Cold start / reinstall — phone empty, watch holds up to 7 days.
B. Long gap (2-day desync) then reconnect.
C. Steady state — healthy, frequent syncs, large accumulated history.
D. Staggered TestFlight update — watch on build N, phone on N±1.
E. Partial delivery — some chunks/pushes lost.
F. Clock skew / out-of-order arrival.

---

## Option 1 — Chunked idempotent window  *(Selection + Chunking)*

Keep sending a bounded window, but split into pieces each < cap; rely on timestamp-dedup. No watermark.

- **Fixes:** size overflow, with zero fragile state.
- **Adversarial:**
  - A/B (cold start, gap): many chunks, one-time, bounded by 7-day retention. OK *if* transport delivers.
  - E (partial): phone keeps valid partial data; next push resends the rest; self-heals. ✔
  - D (staggered): each chunk is a plain sample batch; the existing tolerant decode (`decodeIfPresent`) already absorbs missing keys. ✔
  - C (steady state): re-sends overlap the phone already has → wasted bytes/battery, absorbed by dedup. Bounded.
  - Window < gap: data older than the send window never resends. **Mitigation — tiered, depth decoupled from cadence:**
    - *Every push (cheap):* re-send a short overlap (last few hours) so recent dropped transfers recover at low cost.
    - *Rare full sweep (7 days):* only on app launch or when stale-detection (@8h) fires. 7 days = the watch's retained window (`monitorKinesias(forDuration: 7d)` + the `-7d` query bound), so the sweep leaves nothing recoverable behind. Runs seldom, so its size doesn't hurt. A *frequent* 7-day resend would reintroduce the oversized-payload bug — avoid.
- **Depends on Gap 1:** yes (needs bulk transport to deliver).
- **Verdict:** strongest correctness story; leans only on the verified dedup property.

## Option 2 — Compression  *(Encoding modifier; combines with any option)*

gzip / lzfse the payload before send; ~5–10× smaller (repeated JSON keys compress away).

- **Fixes:** buys headroom; likely brings a normal window under cap.
- **Adversarial:**
  - D (skew): tag payload with a format byte; unknown format → fall back / ignore. Both sides ship together regardless.
  - A (worst-case backfill): may still exceed cap even compressed → **insufficient alone; still needs chunking.**
- **Depends on Gap 1:** no (orthogonal).
- **Verdict:** good multiplier, not a bound. Pair with #1; don't rely on it alone.

## Option 3 — Trim / quantize the record  *(Encoding modifier)*

Drop wire-redundant fields: `id` (unused in dedup), `tremorScore` (recomputable from the distribution), `bucketEnd` (≈ ts + 60s). Optionally quantize the 6 percentages to `UInt8`.

- **Fixes:** ~3–4× smaller before any compression.
- **Adversarial:**
  - Recomputing `tremorScore` on the phone must match `weightedScore` **exactly** → one source of truth for the formula.
  - Quantization → ~0.4% resolution loss on a 0–1 fraction. **Conflicts with the "preserve raw sensor data" guardrail — a fidelity decision, not free.**
  - Dropping `id` → confirm nothing keys on it (dedup is by timestamp; looks safe, verify).
- **Depends on Gap 1:** no.
- **Verdict:** cheap size win but touches the data model / fidelity — higher scrutiny; likely unnecessary if #1 + #2 suffice.

## Option 4 — `transferFile` for bulk  *(Transport)*

Write the batch to a file; send via `transferFile` (Apple's mechanism for larger, reliable, queued payloads); phone reads then deletes.

- **Fixes:** removes the size ceiling for bulk entirely; the intended API for this size class.
- **Adversarial:**
  - Delivery timing still opportunistic (same Gap-1 question — but this is the channel Apple points at for size).
  - E (interrupted): WC re-queues; phone dedups on re-receive. ✔
  - File lifecycle: cleanup both ends.
- **Depends on Gap 1:** partially — it *is* the more-reliable transport; may resolve Gap 1 favorably.
- **Verdict:** serious candidate as the bulk channel instead of `transferUserInfo`.

## Option 5 — Delta / watermark  *(Selection)* — REJECTED, documented

Send only samples newer than a stored watermark.

- **Advantage:** least bytes.
- **Failure modes (why rejected):** watermark advances past data that never landed (lost ack) → **silent permanent loss**; clock skew (F); boundary off-by-one; out-of-order arrival. Trades bandwidth for silent-data-loss risk.
- **Verdict:** no — wrong trade for a foundation that "can't be flaky."

---

## Recommendation

**Option 1 (idempotent window) + Option 2 (compression).** Rationale: leans only on the verified property — timestamp dedup makes re-sending safe — and revives the zero-open ambient path.

**Design:**
- **Selection:** idempotent bounded window, no watermark. Tiered reconcile (short overlap every push; full 7-day sweep on launch / stale-trigger).
- **Encoding:** lzfse compression on every payload. Format-byte tag so an unknown format falls back rather than crashes.
- **Transport:** `applicationContext` = small recent slice, compressed → always under cap → ambient backbone restored. Bulk/backfill = chunked `transferUserInfo`, each chunk under a safe threshold.
- **Not doing:** Option 3 (trim/quantize — touches fidelity, held in reserve), Option 5 (delta — silent-loss risk).
- **Reserve:** Option 4 (`transferFile`) only if observation shows `transferUserInfo` backing up.

**Sequence (smallest-risk first):**
1. Loud saves — replace `try? context.save()` with `do/catch` + `[sync]` error log and a `received=/inserted=` line. Zero behavior change; makes persistence and delivery observable.
2. Compression + small-slice `applicationContext` — fixes the acute overflow, restores the ambient path.
3. Chunked bulk + tiered reconcile — bounds cold-start / long-gap.
4. Stale detection @ 8h — safety net.

**Gap 1** (does a large `transferUserInfo` deliver or silently drop) does not gate this design: the idempotent re-send recovers dropped transfers, and step 1 makes delivery observable so chunk size and reconcile cadence can be tuned against real logs. `transferFile` is the fallback if step 1's logs show drops.

## Step 1 detail — Loud saves

**What:** replace the silent `try? context.save()` in `PhoneConnectivityManager.persistSamples` and `persistDyskinesiaSamples` with `do/catch` that logs on failure, plus a success line reporting `received=/inserted=`.

**Problem it addresses:** `try?` discards any thrown save error. On a failed SwiftData/CloudKit save the function returns `inserted` as if it succeeded, nothing persists, and nothing logs. The receive→dedup→insert→**save** pipeline currently has an invisible last step. When "data isn't on the phone," the three causes — never arrived / decode failed / save threw — are indistinguishable.

**Why it is step 1:** the idempotent-window design assumes the phone reliably persists what it receives. If saves fail silently, re-sending cannot help and we would debug the wrong layer.

**Risk:** none to data integrity. Purely additive observability — no control-flow change on success; on failure it only adds a log line and continues (identical to the prior `try?` behavior). Cannot itself introduce a data bug.

**Traceability:** each of the four sequence steps lands as a separate commit referencing this doc, and each code site carries an inline comment pointing here. A future regression can be bisected to a specific step and read back against the rationale above.
