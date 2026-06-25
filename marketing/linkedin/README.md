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

| # | Date | Topic | Feature(s) showcased | Site | Link |
|---|------|-------|----------------------|------|------|
| 1 | 2026-06-02 | Introducing Kampa | Passive tremor/dyskinesia tracking; correlation concept; Movement Disorder API + HealthKit | `core` (site launch) | [post](https://www.linkedin.com/posts/kampa-health_parkinsons-digitalhealth-applewatch-activity-7467694178894794752-xz3t) |
| 2 | 2026-06-17 | Your health, your data (privacy) | Private CloudKit backup/restore; in-app data inventory; resilient restore | `changelog` | [post](https://www.linkedin.com/feed/update/urn:li:activity:7472924192384966658) |
| 3 | 2026-06-20 | The first three insights Kampa surfaced | Correlation engine (afternoon dose-response, wearing-off/OFF windows, gait progression); rigor principle (stats, not LLM-guesswork); Movement Disorder API entitlement | `changelog` (pending — batch) | [post](https://www.linkedin.com/feed/update/urn:li:activity:7474015943602511873) |

---

## Next up (targeted, ordered)

> `ready` = can write now · `needs-feature` = waiting on a build to ship first

- [ ] **Kampa is in testing — request access** — TestFlight launch. The next big beat. Dual moment: website CTA ("request access") + a strong post. Site: `core` (adds an access CTA) + `changelog`. **Batch the website work: Insights What's-new line + access CTA in ONE Netlify deploy.** — `needs-feature` (TestFlight release; build-1 still "Waiting for Review" as of Jun 20; see BACKLOG.md distribution-readiness)
- [ ] **A clinical report for your neurologist** — the in-app PDF export: charts + observed-medications block + Geist branding, neurologist-ready. Tangible payoff of the "bring to your appointment" line; strong for the clinical/research audience + Parkinson's Foundation contact. — `ready` (shipped Jun 19)
- [ ] **Ambient voice insight ("the magic")** — plain-language daily summary, hands-free. — `needs-feature`
- [ ] **Insight intelligence architecture (the design fork)** — LLM proposes hypotheses → deterministic engine judges → LLM narrates; "we let the LLM imagine and explain, never be the statistician." Bhav's sequencing: after TestFlight post. See `docs/intelligence-architecture.md`. — `ready` (but hold per sequencing)

> Dropped: "Why 'Kampa'?" etymology post — the website already covers why Kampa; the standalone-post moment has passed (Jun 19).

## Idea bank (unscheduled)

- **Passive, zero-burden tracking / closed-loop HealthKit (Bhav, Jun 20 — strong, agreed)** — the design philosophy: lean on Apple's closed-loop HealthKit + Apple Watch sensors as much as possible and MINIMIZE in-app manual logging. Example: do a boxing workout on the Watch → it auto-captures heart rate + ancillary data + workout type (Kampa already reads `HKWorkout` types); no manual "log a boxing session" screen needed. GUARDRAILS: (1) frame as *"prefer passive, minimize manual logging,"* NOT *"no logging"* — Kampa DOES log food + meditation (and meds via the native HealthKit medication flow); don't overclaim (same trap caught in post #3's "no logging" line). (2) Do NOT name StrivePD or frame as "better than X" publicly — make it about the principle, per [[project_strivepd_guardian]] / `project_strivepd_guardian` memory. Pairs with the "On-device intelligence" angle below.
- **On-device intelligence** — why processing/insight runs on the device, not a server (privacy + speed). Pairs with the privacy post.
- **Movement Disorder API deep-dive** — technical credibility for the research/clinical audience.
- **Data portability** — CSV export of everything you've tracked ("your data, take it anywhere").
- **Food / nutrition logging** — once correlated with symptoms, a "what you eat vs how you feel" story.
- **On-device food understanding (USDA DB, no API, global cuisines)** — the engineering/architecture companion to the food↔symptom angle above, in the tone of the intelligence-architecture post. Kampa ships a USDA food database *inside* the app (no network, no third-party API, fully private) + a tiny hand-grown vocabulary map for regional/global foods, so it understands what you eat on-device. Honest-engineering beat: the spike that proved a US food DB *alone* covers only ~50% of a chai-and-dal diet, and the clean fix. NEVER discloses founder PD. See `docs/food-classification.md`. — `needs-feature` (classifier not shipped; attribute-correctness redesign pending).

---

*Update this file when posting (move the row to Posted) and when a feature ships (add a Next-up candidate).*
