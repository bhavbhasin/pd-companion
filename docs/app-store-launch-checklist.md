# App Store launch checklist

Two decisions, two bars. **List** = quiet US-first, unmarketed. **Launch** = a public/marketing push. Don't market to strangers before cold-start is solved (back-loaded value → stranger churns on day 3). Build-time gates reuse BACKLOG.md → Distribution-readiness; this doc adds the App-Store-specific + product bars.

⚠ Apple's rules shift — items marked **(verify)** need a current-docs check before submission, don't take from memory.

---

## Gate A — LIST (US-first, quiet). Low bar; do early.

### Technical / build-time (per-release, from Distribution-readiness)
- [ ] CloudKit schema deployed Dev→Production (every changed `@Model` additive-only)
- [ ] Bundle IDs + Watch companion linkage intact — **never rename** `com.bhavbhasin.pdcompanion*` (Movement Disorder entitlement is bound to it)
- [ ] Entitlements on the right targets (iCloud/CloudKit, aps, Background Modes, Movement Disorder, HealthKit)
- [ ] Movement Disorder distribution gate (EP5499 addendum)
- [ ] Watch sync self-heals on a clean device (build 9 fix verified in Release, not just Debug)
- [ ] Day-ahead forecast verified on a **multi-dose day** (currently gut-checked on 1-dose only)
- [ ] Stage to yourself on a clean device first

### Data safety (a health app can't ship a one-way door)
- [ ] **CSV/JSON import / restore path** — export is one-way today; CloudKit is the only restore. Build before public install. (BACKLOG: "build soon")
- [ ] In-app account deletion **(verify** — Apple requires it *if* there's account creation; Kampa is CloudKit/on-device with no account, likely N/A — confirm)

### Claims & regulatory hygiene (the medical-app line)
- [ ] No UPDRS-equivalence claim anywhere (listing, app, FAQ) — "passive 0-4 estimate," not "the UPDRS scale"
- [ ] No dosing instruction or medication-regimen suggestion, anywhere — observation + refer-to-neurologist only
- [ ] In-app + listing medical disclaimer ("wellness tool, not a medical device; not a doctor")
- [ ] App Review Guidelines §1.4.1 (medical accuracy) self-audit **(verify)**

### Privacy (three separate things)
- [ ] Privacy policy URL live + accurate, incl. cohort export-and-share workflow (BACKLOG item)
- [ ] Apple **App Privacy "nutrition label"** in App Store Connect filled out — distinct from the policy **(verify current fields)**
- [ ] HealthKit App Review rules: no HealthKit data for advertising; policy discloses use §5.1.3 **(verify)**

### App Store Connect mechanics
- [ ] Category — Health & Fitness vs Medical (Medical invites more scrutiny; recommend Health & Fitness) **(verify implications)**
- [ ] Name, subtitle, keywords, description — claims-clean (see hygiene above)
- [ ] Screenshots for all required device sizes (reuse website assets; mind the black-void screenshot bug from the web deploy)
- [ ] Age rating questionnaire
- [ ] Support URL + marketing URL (kampa.health)
- [ ] Export-compliance / encryption declaration **(verify — usually "uses standard encryption, exempt")**
- [ ] Free app: confirm no paid-apps agreement / banking needed for v1

---

## Gate B — LAUNCH (marketed). High bar. One thing gates it: **cold-start solved.**

The decision variable: *does a stranger get honest value fast enough to stay, without a relationship propping them up?* Measurable on the current F&F cohort **now** — time-to-first-honest-insight + would-they-stay at day 5.

- [ ] **Cold-start**: population priors so a new user gets a hedged insight ~day 5, not ~day 40. (Gait HealthKit backfill = one Day-1 seed today; not the whole experience.)
- [ ] **Product analytics wired** — privacy-first tool (TelemetryDeck/Aptabase) or first-party anonymous counters; NO third-party SDKs. Event spec: `install → permissions granted → first Watch data arrived → first honest insight shown → retained day 7`. This funnel *is* the cold-start metric at scale. (BACKLOG: Product analytics + cold-start event spec)
- [ ] A validated **retention surface** (the StrivePD daily-engagement threat) — honest, not gamified
- [ ] Cohort metric passes: a low-patience stranger reaches value before churning (measurable once analytics above is live)
- [ ] Monetization decided/built **only if** launching paid — freemium-by-capability, paywall at demonstrated value (Phase 4; a free launch skips this)
- [ ] Positioning finalized (PD vs broadened "tremor"/ET — don't claim validated ET sensing without verifying Apple's API on ET signal)

### Global launch only (not US-first)
- [ ] Global food coverage answered — USDA-only fails African/ME/SE-Asian (audit: 32.8% resolve). US launch sidesteps this; worldwide doesn't.

---

**Recommendation:** clear Gate A and list quietly US-first — it's low-risk, forces claims-hygiene while stakes are one reviewer, and gives a real product URL for the hiring narrative. Hold Gate B (the marketing push) until the cohort metric shows cold-start holds a stranger.
