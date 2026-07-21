# Kampa — LinkedIn Content Tracker

Running record of what's posted, what's queued, and what's in the idea bank.
Posted from the **Kampa Health** company page. Target **≥1 post/week**, but post more
when feature traction warrants it — cadence follows the building, not a fixed calendar.

- Each post's copy + cards live in `YYYY-MM-DD-topic/` (`post.md`, `card1.png`, `card2.png`).
- Feature backlog (what we're building) = `../../BACKLOG.md`. This tracker is the bridge:
  shipped feature → post. When a feature lands, log a candidate in **Next up**.
- Brand assets for cards: `../../website/assets/brand/` (see `BRAND.md` — don't re-screenshot).
- **Website sync:** the `Site` column logs each post's website treatment — `none` /
  `changelog` (add to the *What's new* section of `index.html`) / `core` (hero/pitch update).
  The website is the **evergreen source of truth**, updated for major features — not synced 1:1
  with posts (LinkedIn is frequent; the site changes on enhancements & features that last).
- Public voice: builder/founder; **never disclose the founder personally has Parkinson's**;
  privacy copy uses ownership/control framing, not "we can't see it" absolutes.

---

## Posted

| #   | Date       | Topic                                   | Feature(s) showcased                                                                                                                                                   | Site                                                                               | Link                                                                                                                      |
| --- | ---------- | --------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------- |
| 1   | 2026-06-02 | Introducing Kampa                       | Passive tremor/dyskinesia tracking; correlation concept; Movement Disorder API + HealthKit                                                                             | `core` (site launch)                                                               | [post](https://www.linkedin.com/posts/kampa-health_parkinsons-digitalhealth-applewatch-activity-7467694178894794752-xz3t) |
| 2   | 2026-06-17 | Your health, your data (privacy)        | Private CloudKit backup/restore; in-app data inventory; resilient restore                                                                                              | `changelog`                                                                        | [post](https://www.linkedin.com/feed/update/urn:li:activity:7472924192384966658)                                          |
| 3   | 2026-06-20 | The first three insights Kampa surfaced | Correlation engine (afternoon dose-response, wearing-off/OFF windows, gait progression); rigor principle (stats, not LLM-guesswork); Movement Disorder API entitlement | `changelog` (pending — batch)                                                      | [post](https://www.linkedin.com/feed/update/urn:li:activity:7474015943602511873)                                          |
| 4   | 2026-06-24 | Kampa is in testing — request access    | TestFlight launch / beta access (curated, by-request)                                                                                                                  | ⚠ _confirm: did the website CTA/changelog go live, or still held for Jul 1 batch?_ | [post](https://www.linkedin.com/feed/update/urn:li:activity:7475704979543191552)                                          |
| 5   | 2026-06-27 | Design principles (three pillars)       | Framing post: Privacy · Apple closed-loop ecosystem · Ambient (low cognitive load); folds in closed-loop HealthKit + on-device intelligence; voice-logging as forward direction (de-risked). Hero image: real Day-in-Review screenshot (tremor chart + Daily Observations). **ARTICLE variant drafted `2026-06-27-design-principles/article.md`** (long-form: title + cover + 1 inline image/pillar) for cross-share to Bhav's personal feed — `draft`, not yet published. | `none` (framing post; principles already on site) — _confirm_                       | [post](https://www.linkedin.com/posts/parkinsons-digitalhealth-productdesign-share-7476757937143836672-3nWe/)            |
| 6   | 2026-07-06 | Glucose on your timeline (CGM + finger-prick) | Brand-agnostic CGM ingestion + finger-prick-via-Health, stacked/synced Tremor+Glucose panels, tap-hold crosshair | `core` (already updated `13b5e40`) | [post](https://www.linkedin.com/feed/update/urn:li:activity:7479957366814294016) |
| 7   | 2026-07-08 | "What to expect today" — the day-ahead forecast | Tier-1 forward projection of ON/OFF cycle from today's own doses (`DayAheadPanel`); OFF band shaded by measured tremor severity | _confirm_ | [post](https://www.linkedin.com/feed/update/urn:li:activity:7480685161320173568) |

---

## Next up (targeted, ordered)

> `ready` = can write now · `needs-feature` = waiting on a build to ship first

- [ ] **A clinical report for your neurologist** — the in-app PDF export: charts + observed-medications block + Geist branding, neurologist-ready. Tangible payoff of the "bring to your appointment" line; strong for the clinical/research audience + Parkinson's Foundation contact. — `ready` (feature shipped Jun 19; **post NOT yet published**)
- [ ] **GI symptoms on your timeline** — log digestive/GI symptoms via "+" or voice; charts alongside tremor/meds. Shipped `c7c54d1`, in **build 10** (`5531de9`). Minor feature — likely a fold-in for the passive/closed-loop or timeline story rather than a standalone post. — `ready` (low priority)
- [ ] **Ambient voice insight ("the magic")** — plain-language daily summary, hands-free. — `needs-feature`
- [ ] **Insight intelligence architecture (the design fork)** — DRAFTED as a LinkedIn **Article** `2026-07-19-intelligence-architecture/article.md` (cross-share to personal feed, same format as design-principles). Cover = purpose-built diagram `cover-diagram.png` (Propose→Judge→Narrate, brand blue/Geist/dark), not a reused screenshot. Uses real Insights-tab screenshots (`insight-1/2/3.jpg`, already live on site) + the caffeine dose-confound-guard story (depersonalized to third person per `DesignReview-2026-07-19.md` §6 — do not revert to "my data"). ⛔ Framed carefully: only the deterministic Judge is claimed as live — propose/narrate AI layers are described as sequencing ("built the judge before the talker"), never as currently running (verified: no runtime LLM yet). `insight-2.jpg`'s "Try an experiment" button kept per Bhav's call, flagged in-copy as "(more on this later)" — a future experiment-feature post is now implied, add to Idea bank once the button ships. — `ready to publish`

> **Bhav's Jun 26 near-term set (post over the next few days, ~alternate days).** A natural 3-part series: what Kampa *believes* → how it *works* → what it *feels like*. Ordering relative to the TestFlight + clinical-report entries above is Bhav's call (these don't depend on a new build).
- [ ] **High-level approach — foundational data → correlation → insights → predictions** — the layered product narrative (how the whole thing fits together). ⚠ PREDICTION GUARDRAIL: frame predictions as a *future direction we're exploring*, NOT a shipping claim — Phase 3 / aspirational; lead with what ships (see ParkinsonsProject.md → Strategic Posture + Differentiation). — `ready`
- [ ] **Magical moments — tremor chart · observations panel · food chips · insights · (predictions)** — a "wow surfaces" showcase. tremor chart / observations panel / food chips / insights are all SHIPPED (food chips live in build 5) = real screenshots. ⚠ Predictions: the Tier-1 "what to expect today" card (`DayAheadPanel`, `29ec720`) is now in **build 10** (`5531de9`) — screenshot-able once build 10 lands in F&F; until then keep it out of the showcase or label "coming," never imply it ships. Overlaps posted #3 (insights) — give it fresh framing. — `ready` (minus predictions)

> Dropped: "Why 'Kampa'?" etymology post — the website already covers why Kampa; the standalone-post moment has passed (Jun 19).

## Idea bank (unscheduled)

- **Passive, zero-burden tracking / closed-loop HealthKit (Bhav, Jun 20 — strong, agreed)** — the design philosophy: lean on Apple's closed-loop HealthKit + Apple Watch sensors as much as possible and MINIMIZE in-app manual logging. Example: do a boxing workout on the Watch → it auto-captures heart rate + ancillary data + workout type (Kampa already reads `HKWorkout` types); no manual "log a boxing session" screen needed. GUARDRAILS: (1) frame as *"prefer passive, minimize manual logging,"* NOT *"no logging"* — Kampa DOES log food + meditation (and meds via the native HealthKit medication flow); don't overclaim (same trap caught in post #3's "no logging" line). (2) Do NOT name StrivePD or frame as "better than X" publicly — make it about the principle, per [[project_strivepd_guardian]] / `project_strivepd_guardian` memory. Pairs with the "On-device intelligence" angle below.
- **The best notification is none (attention as the scarce resource)** — a zero-cognitive-load beat: we removed a watch-sync push (`7e3e787`) once we knew a late sync is delayed-not-lost — the app self-heals and shows a quiet in-app note only when you're already looking, instead of nagging. Fits the ambient pillar. ⚠ Thin on its own + overlaps design-principles post #5; fold into a future attention/ambient post rather than a standalone. Framing only — never disclose founder PD.
- **On-device intelligence** — why processing/insight runs on the device, not a server (privacy + speed). Pairs with the privacy post.
- **Movement Disorder API deep-dive** — technical credibility for the research/clinical audience.
- **Data portability** — CSV export of everything you've tracked ("your data, take it anywhere").
- **Food / nutrition logging** — once correlated with symptoms, a "what you eat vs how you feel" story.
- **"Try an experiment" — turning a hypothesis into a test you run** — teed up by the "(more on this later)" line in the intelligence-architecture article (`2026-07-19-intelligence-architecture/article.md`). — `needs-feature` (experiment loop persistence not started, see `project_kampa_experiment_loop`; also blocked on `DesignReview-2026-07-19.md` §5.4's `#if DEBUG` gate landing first, since the current button silently loses data on reload).
- **On-device food understanding (USDA DB, no API, global cuisines)** - the engineering/architecture companion to the food↔symptom angle above, in the tone of the intelligence-architecture post. Kampa ships a USDA food database *inside* the app (`Resources/Food/FoodDB.json` + `food-aliases.json`, no network, no third-party API, fully private), so it understands what you eat on-device. **Status corrected Jul 19: the classifier IS shipped** (86/86 parity, off-main backfill; the old "not shipped" note was stale). Still open: food-term correction (`docs/food-attribute-correction.md`, designed `d52f90f`, not built).
  **Spine - the honest-engineering beat, and it rhymes with the intelligence-architecture article:** a US food DB alone covers a global diet badly (measured baseline **32.8% resolve / 49.1% useful**; NorthAfrican 6%). An LLM-proposed alias expansion then *scored* 99.4% - and was junk, overfit and circular; a held-out verify split caught it. Same thesis as the AI article from a different angle: **the model proposes, the measurement judges.** Do NOT quote 99.4% as a result. Numbers: `docs/food-classification.md` + coverage-report.
  **Future direction (Bhav, Jul 19): barcode + packaged-food capture** - camera at a protein bar instead of typing it. Decision = **build the corpus ON-DEVICE** (~40 MB, no per-scan leak, no network code in the app target); engineering rationale, sizing, perf and the OFF/ODbL license gate live in `BACKLOG.md` → *Barcode / packaged-food capture*. ⚠ For the POST: don't claim barcode scanning until it's built, and don't let "fully private, no network" copy paper over the packaged-corpus question - same trap as the "isn't more code" line in the AI article.
  NEVER discloses founder PD. - `ready` for the shipped-classifier story; barcode/image half is `needs-feature` (not started - zero barcode code in repo as of Jul 19).

---

*Update this file when posting (move the row to Posted) and when a feature ships (add a Next-up candidate).*
