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
| 5   | 2026-06-27 | Design principles (three pillars)       | Framing post: Privacy · Apple closed-loop ecosystem · Ambient (low cognitive load); folds in closed-loop HealthKit + on-device intelligence; voice-logging as forward direction (de-risked). Hero image: real Day-in-Review screenshot (tremor chart + Daily Observations) | `none` (framing post; principles already on site) — _confirm_                       | [post](https://www.linkedin.com/posts/parkinsons-digitalhealth-productdesign-share-7476757937143836672-3nWe/)            |

---

## Next up (targeted, ordered)

> `ready` = can write now · `needs-feature` = waiting on a build to ship first

- [ ] **Glucose on your timeline (CGM + finger-prick)** — DRAFTED `2026-07-01-glucose/post.md`. Brand-agnostic CGM ingestion + finger-prick-via-Health, stacked/synced Tremor+Glucose panels, tap-hold crosshair. Feature shipped `6f488e0`, **live in build 9** (F&F) + **website already updated** (`13b5e40` CGM showcase). ⚠ No claim glucose predicts tremor (engine doesn't use it — step 1 = observe by eye). — `scheduled` (Mon Jul 6 AM; feature + site both live)

- [ ] **A clinical report for your neurologist** — the in-app PDF export: charts + observed-medications block + Geist branding, neurologist-ready. Tangible payoff of the "bring to your appointment" line; strong for the clinical/research audience + Parkinson's Foundation contact. — `ready` (feature shipped Jun 19; **post NOT yet published**)
- [ ] **"What to expect today" — the day-ahead forecast** — Tier-1 forward projection of your ON/OFF cycle from today's own doses (`DayAheadPanel`). OFF band now shaded by measured tremor severity so it agrees with the tremor line; forecast times rounded (no false precision). Commits `29ec720` (v1) + `ee38130` (refinements). ⚠ BLOCKED: not in a TestFlight build yet — users can't see it. ⚠ PREDICTION GUARDRAIL: this IS the prediction UI, so frame as *early, personal, "a pattern from your own data — not medical advice,"* NEVER a dosing claim. The strongest near-term post. — `scheduled` (aim **Tue/Wed Jul 7–8**; draft against Bhav's device screenshots, frame as beta/early — glucose posts Mon Jul 6 first).
- [ ] **Ambient voice insight ("the magic")** — plain-language daily summary, hands-free. — `needs-feature`
- [ ] **Insight intelligence architecture (the design fork)** — LLM proposes hypotheses → deterministic engine judges → LLM narrates; "we let the LLM imagine and explain, never be the statistician." Bhav's sequencing: after TestFlight post. See `docs/intelligence-architecture.md`. — `ready` (but hold per sequencing)

> **Bhav's Jun 26 near-term set (post over the next few days, ~alternate days).** A natural 3-part series: what Kampa *believes* → how it *works* → what it *feels like*. Ordering relative to the TestFlight + clinical-report entries above is Bhav's call (these don't depend on a new build).
- [ ] **High-level approach — foundational data → correlation → insights → predictions** — the layered product narrative (how the whole thing fits together). ⚠ PREDICTION GUARDRAIL: frame predictions as a *future direction we're exploring*, NOT a shipping claim — Phase 3 / aspirational; lead with what ships (see ParkinsonsProject.md → Strategic Posture + Differentiation). — `ready`
- [ ] **Magical moments — tremor chart · observations panel · food chips · insights · (predictions)** — a "wow surfaces" showcase. tremor chart / observations panel / food chips / insights are all SHIPPED (food chips live in build 5) = real screenshots. ⚠ Predictions: the Tier-1 "what to expect today" card is now BUILT (`DayAheadPanel`, `29ec720`) but NOT in a TestFlight build → still not screenshot-able for users; keep it out of the showcase or label "coming," never imply it ships. Overlaps posted #3 (insights) — give it fresh framing. — `ready` (minus predictions)

> Dropped: "Why 'Kampa'?" etymology post — the website already covers why Kampa; the standalone-post moment has passed (Jun 19).

## Idea bank (unscheduled)

- **Passive, zero-burden tracking / closed-loop HealthKit (Bhav, Jun 20 — strong, agreed)** — the design philosophy: lean on Apple's closed-loop HealthKit + Apple Watch sensors as much as possible and MINIMIZE in-app manual logging. Example: do a boxing workout on the Watch → it auto-captures heart rate + ancillary data + workout type (Kampa already reads `HKWorkout` types); no manual "log a boxing session" screen needed. GUARDRAILS: (1) frame as *"prefer passive, minimize manual logging,"* NOT *"no logging"* — Kampa DOES log food + meditation (and meds via the native HealthKit medication flow); don't overclaim (same trap caught in post #3's "no logging" line). (2) Do NOT name StrivePD or frame as "better than X" publicly — make it about the principle, per [[project_strivepd_guardian]] / `project_strivepd_guardian` memory. Pairs with the "On-device intelligence" angle below.
- **The best notification is none (attention as the scarce resource)** — a zero-cognitive-load beat: we removed a watch-sync push (`7e3e787`) once we knew a late sync is delayed-not-lost — the app self-heals and shows a quiet in-app note only when you're already looking, instead of nagging. Fits the ambient pillar. ⚠ Thin on its own + overlaps design-principles post #5; fold into a future attention/ambient post rather than a standalone. Framing only — never disclose founder PD.
- **On-device intelligence** — why processing/insight runs on the device, not a server (privacy + speed). Pairs with the privacy post.
- **Movement Disorder API deep-dive** — technical credibility for the research/clinical audience.
- **Data portability** — CSV export of everything you've tracked ("your data, take it anywhere").
- **Food / nutrition logging** — once correlated with symptoms, a "what you eat vs how you feel" story.
- **On-device food understanding (USDA DB, no API, global cuisines)** — the engineering/architecture companion to the food↔symptom angle above, in the tone of the intelligence-architecture post. Kampa ships a USDA food database *inside* the app (no network, no third-party API, fully private) + a tiny hand-grown vocabulary map for regional/global foods, so it understands what you eat on-device. Honest-engineering beat: the spike that proved a US food DB *alone* covers only ~50% of a chai-and-dal diet, and the clean fix. NEVER discloses founder PD. See `docs/food-classification.md`. — `needs-feature` (classifier not shipped; attribute-correctness redesign pending).

---

*Update this file when posting (move the row to Posted) and when a feature ships (add a Next-up candidate).*
