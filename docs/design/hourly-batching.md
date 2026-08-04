# CloudKit Hourly Batching — New Data Only, No Migration

**Status:** Designed Aug 3 2026. **Not built. Not a 1.0 change** — schedule it as the first
post-1.0 piece of work, on its own, never folded into a feature.

**The decision that defines this design: existing per-minute rows are never touched.** No rewrite,
no delete, no migration. Batching applies to data arriving after the update; everything already
stored stays exactly as it is and is read in place. Compacting the old rows remains available as a
separate, later project — see [Keeping the door open](#keeping-the-door-open).

## The problem

Measured Aug 1 2026 off a real account (iCloud → See All → Kampa) against the Jul 31 CSVs:

| | |
|---|---|
| Records synced | ~157,800 (113,496 tremor · 44,040 dyskinesia · 288 food) |
| Raw CSV bytes for all of it | **6.8 MB** |
| Reported in iCloud | **527.1 MB** |
| **Per record** | **~3.3 KB** for a timestamp and a few doubles — **~77× the raw data** |

It is CloudKit **per-record** overhead — system fields, change tag, indexes — not our payload. At
1,351 tremor + 1,295 dyskinesia rows/day that is **~8.7 MB/day ≈ 3.2 GB/year**.

**Who it hurts.** Not the current holders of large records — all four existing testers are on paid
iCloud tiers with years of headroom. A new user on the **free 5 GB tier** already has photos and a
device backup there and realistically has under 1 GB spare: months, not years. ⛔ **When iCloud
fills, CloudKit sync stops silently**, and CloudKit is the only restore path (CSV/JSON import
retired Jul 31, `3a59d61`). Their record quietly stops syncing, they never find out, and the
restore is dead exactly when they need it.

**So the entire beneficiary of this change is a user who does not exist yet.** That is the fact
that decides the migration question below.

## Expected saving — and why the encoding now matters

The BACKLOG's original "~60× → ~55 MB/year" assumed the payload was ~free. It is not, once 60
samples live in one record. Overhead is measured; payload sizing below is arithmetic and **must be
verified with a real before/after storage read**, not trusted from this table.

| | records/day | est. size/day | est./year |
|---|---|---|---|
| Today (per-minute) | 2,646 | 8.7 MB *(measured)* | 3.2 GB |
| Hourly, JSON blob | 48 | ~0.53 MB | ~190 MB (~16×) |
| Hourly, packed binary | 48 | ~0.19 MB | ~70 MB (~45×) |

Encoding choice is worth ~3×, which it never was before. It is a design decision, not an
implementation detail.

## Why new-data-only, not a migration

A migration would reclaim the ~527 MB already spent. Set against that:

- The only people holding a large historical record are the developer and three testers, all with
  ample iCloud headroom. **The storage being reclaimed is storage nobody needs back.**
- Apple's Movement Disorder results are **not refetchable past ~7 rolling days**. A tremor record
  cannot be rebuilt from any source. It is the one dataset in this app that is genuinely
  irreplaceable.
- A migration's dangerous failure is not a crash — a crash is loud and resumable. It is a silent
  encode/decode defect that writes plausible-looking wrong values and then deletes the originals.
  That is undetectable at the moment it happens and permanent afterwards.
- This is a health record. A data-loss incident is not a bug, it is a credibility event.

**New users are born batched and never have a migration at all.** Since new users are the whole
point, the migration buys nothing for the people it endangers.

## Design

### Record shape — one bucket type per stream

`TremorHour` and `DyskinesiaHour`, each holding one hour of samples as an encoded blob. **Not a
combined bucket:** a dyskinesia-only batch would rewrite the tremor blob, and it would re-couple
two streams `DyskinesiaReading`'s header deliberately separates (a minute can carry dyskinesia with
no matching tremor bucket — merging silently drops those minutes).

CloudKit constraints, already known from the existing models: every stored property needs a default
value, and `@Attribute(.unique)` is unsupported, so uniqueness is enforced in code (as
`cleanupDuplicates` does today).

Each bucket carries, alongside the blob:
- `hourStart` — indexed, the query key.
- `firstSampleAt` / `lastSampleAt` — denormalized, see [Watermarks](#watermarks-load-bearing).
- `schemaVersion` — inside the payload, so the packed format can evolve later without a second
  record-type change. A byte now, expensive to retrofit.

### Dual read, permanently

Reads merge two sources: per-minute rows below the cutover instant, buckets above it. The cutover
is a stored date, written once when the new build first runs, so the boundary is unambiguous rather
than inferred. Views never see either shape — a projection layer hands them flat sample arrays, so
the ~8 existing read sites keep consuming what they consume today.

This dual-read code is the price of not migrating. It is permanent unless a later compaction
project removes it.

### The open hour

The watch delivers several batches an hour, so the current hour's bucket is rewritten on each
arrival — CloudKit pushes the whole record, not a delta. **Rewrite it live.** The alternative
(stage the open hour locally, seal it at the boundary) avoids the churn but leaves the most recent
under-an-hour unbacked-up — exactly the data lost to a dropped phone. Churn is cheap; silent
data loss is not.

### Collision handling is a merge, not a prune

Today dedup is exact-timestamp matching plus `pruneDuplicates` deleting rows sharing a key date.
For buckets, a collision is two buckets with the same `hourStart` and partially-overlapping
contents. **Union by sample timestamp inside the blob** — "first wins" would silently drop samples.
This also makes the reinstall race (CloudKit restore landing while the watch re-sends its 7-day
window, [[project_kampa_deletion_restore_test]]) converge by merging rather than by pruning a
duplicate storm.

### Watermarks — load-bearing

Four paths depend on a `fetchLimit = 1` sorted query returning a **real sample time**, not a bucket
boundary:

| Path | Today | Breaks how |
|---|---|---|
| `PhoneConnectivityManager.latestStoredSampleTimestamp()` | newest `timestamp` | Drives the watch's `since`. Returning `hourStart` makes the watch re-send up to an hour, every sync, forever |
| `DayInReviewView.refreshLatestReadingDate()` | newest `timestamp` | Header "Updated…" label reads up to an hour stale |
| `recordIsOlderThanTwoDays` | earliest `timestamp` | Gates the iCloud backup banner |
| `hasEverHadData` | `fetchCount` | Still fine — count only |

`firstSampleAt` / `lastSampleAt` on the bucket keep all four as cheap limit-1 queries.

### Read sites affected

Day-scoped `@Query` in `DayReviewContent` becomes an hour-range predicate plus a decode — trivial
at 24 rows. The full-table readers — `InsightsView`, `SettingsSheet`, `SeverityTrendSheet`,
`recomputeForecast`, `CSVBackupExporter` — hydrate ~60× fewer rows but then decode. Likely net
faster; **measure, do not assume.**

Lost: the per-minute `#Index` moves to per-hour (same range-lookup benefit, coarser grain), and a
store-level predicate on `tremorScore` becomes impossible. Checked — nothing does that today; every
predicate is on `timestamp` / `startDate`.

## Risk register

Since nothing is deleted or rewritten, the classic migration risks do not apply. What remains:

| Risk | Guard |
|---|---|
| Silent encode/decode defect corrupts new samples | Round-trip the packed format against a known corpus before trusting it; compare a rendered day chart before/after on device |
| CloudKit rejects the new record type (schema not deployed) | **Deploy Dev→Production before the build ships** — the recurring release gate. Undeployed = sync stops silently while local looks healthy |
| Dual-read boundary bug hides data on one side of the cutover | Cutover is a stored instant, not inferred; verify a day spanning it renders both halves |
| Buckets and per-minute rows double-count across the boundary | Projection layer is the single merge point; test a day that straddles the cutover |
| No remote kill switch (no servers, by design) | TestFlight on the largest real record first, then App Store phased release |

Rehearse on a **copy** of the largest real store — 158k rows is the field's worst case and it is
already on the developer's machine.

## What this does not fix

`CKAccountStatus` **has no quota case**: a user at their storage limit reports `.available` while
sync has silently stopped. Batching lowers the rate; it does not detect the failure. Detection
needs a probe write catching `CKError.quotaExceeded` — a separate item, see
[[project_kampa_icloud_backup_warning]].

## Keeping the door open

Compacting the existing per-minute rows stays possible at any time. Nothing here forecloses it, and
this design makes it *safer* to do later than now:

- The bucket format will have been proven in production on live data before it is ever asked to
  hold irreplaceable history.
- `schemaVersion` in the payload means the format can improve first.
- The merge-on-collision rule already makes bucket writes idempotent — a compaction pass can run
  more than once, or on more than one device, and converge.
- The dual-read layer is what a compaction would remove, so the work is subtractive.

**Conditions to reopen:** a real user (not a tester) approaching their iCloud limit, or a decision
to reclaim historical footprint at scale. **Preconditions for doing it then:** verify-then-delete
per hour (write bucket → re-read → decode → compare every timestamp → only then delete the source
rows), old rows retained in CloudKit for a full release so the change is reversible by shipping a
build, and a rehearsal against a copy of a real store.

See [[project_kampa_data_architecture]], [[project_kampa_deletion_restore_test]],
`docs/design/watch-sync-payload-options.md`.
