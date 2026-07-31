# App Store launch checklist

Two decisions, two bars. **List** = quiet US-first, unmarketed. **Launch** = a public/marketing push. Don't market to strangers before cold-start is solved (back-loaded value → stranger churns on day 3). Build-time gates reuse BACKLOG.md → Distribution-readiness; this doc adds the App-Store-specific + product bars.

⚠ Apple's rules shift — items marked **(verify)** need a current-docs check before submission, don't take from memory.

---

## 🎯 REMAINING TO LIST — work this order (status Jul 30 2026)

**Next:**
1. ⬜ **Delete + restore from iCloud on Dad's phone.** Replaces building CSV/JSON import — his call
   Jul 30, and the cleaner proof anyway. If it passes, the import path moves to post-list.
2. ✅ **App name was NEVER open** — reserved since the TestFlight launch, confirmed on screen
   Jul 31. Record: name `Kampa`, Apple ID `6781438685`, SKU `kampa-ios-001`, bundle ID
   `com.bhavbhasin.pdcompanion` (verified against the project — entitlement binding intact),
   category Health & Fitness, status *1.0 Prepare for Submission*.
   ⚠️ It sat here flagged as the one time-critical item. It was done all along. **This list is
   stale in the same way BACKLOG.md is — verify each `⬜` against App Store Connect or the repo
   before working it.**

### ✅ CLOSED by the Jul 31 verification pass — evidence, not a tick
3. ✅ **CloudKit schema Dev → Production.** All three `@Model` files (`TremorReading`, `FoodEvent`,
   `DyskinesiaReading`) last changed **2026-06-29** (`8724973`, `e15c1e3`) — no schema drift since
   the deploy, so nothing additive is pending.
5. ✅ **Entitlements on the right targets.** iOS: `aps-environment`, `healthkit`,
   `icloud-container-identifiers`, `icloud-services`. Watch: `healthkit`,
   `health-movement-disorder`. Movement Disorder is on the **Watch** target, which is correct.
7. ✅ Day-ahead forecast verified on a multi-dose day.
8. ✅ **`[export-timing]` prints.** Both sites (`HealthKitExporter.swift:430`, `:438`) sit inside
   `#if DEBUG`. Nothing to strip.
10. ✅ **HealthKit review rules §5.1.3.** `website/privacy.html` states it explicitly: *"In line with
    Apple's HealthKit requirements, HealthKit data is never used for advertising or marketing and is
    never disclosed to third parties"*, plus *"no third-party analytics, no advertising SDKs, and no
    tracking"*.
12. ✅ **In-app account deletion — N/A, confirmed.** No account system exists: zero references to
    `AuthenticationServices` / `ASAuthorization` / sign-in / account-creation anywhere in the app.
    Apple's requirement is conditional on account creation, so it does not apply.
13. ✅ Category — **Health & Fitness** (not Medical). Secondary deliberately empty.
17. ✅ **Export compliance.** `ITSAppUsesNonExemptEncryption = false` in **both**
    `PD-Companion-Info.plist` and `PD-Watch-App-Info.plist` — answered at build time, ASC won't prompt.

11. 🟡 **§1.4.1 medical-accuracy — no violations found, full read still owed.** Pattern search over
    all shipping Swift found the risk words only inside *disclaimers* (`SettingsSheet.swift:86`
    "wellness tool, not a medical device… never advises on medication"; the n-of-1 / "not a diagnosis
    or treatment recommendation" lines in `InsightsView.swift:386` + `ClinicalReportPDF.swift:65,177`)
    and **zero** dosing-instruction phrasing. A grep is not a copy audit — a human read of card copy
    is still owed, but nothing flagged.

### ⬜ GENUINELY OPEN
**Device tests (need hardware + people, not a keyboard):**
1. ⬜ Delete + restore from iCloud on Dad's phone. (Confirmed there is no CSV/JSON import path in the
   app — `fileImporter`/`importCSV` return nothing — so iCloud restore IS the only restore story.)
6. ⬜ Watch sync self-heals on a clean device, in **Release** not Debug
19. ⬜ Stage to yourself on a clean device (TestFlight), then submit
    ⭐ **At submission: paste the Movement Disorder disclosure into App Review Information → Notes**
    (draft in item 4). Contractually required by EP5499 §4 and there is no repo artifact to remind you.
    ⚠ Budget days, not hours: the Movement Disorder entitlement can draw extra review scrutiny

**App Store Connect forms (can't verify from the repo — check on screen):**
4. 🟡 **Movement Disorder / EP5499 — mostly a non-item; ONE action at submission.** Read the addendum
   Jul 31: it is a **click-through** ("AGREE"), not a document to sign and return, and §2 makes
   acceptance a **precondition of receiving the Entitlement Profile** — which he holds and which works
   on device. ⇒ already accepted. Confirm visually if wanted at developer.apple.com/account →
   Membership, or ASC → Business.
   ⭐ **THE ACTUAL TO-DO — §4 "Submission to Apple":** *"You agree to disclose to Apple in writing any
   use of the Movement Disorder APIs as part of the submission process."* ⇒ **paste a line into
   App Review Information → Notes when submitting** (see item 19). Draft:
   > *Kampa uses Apple's Movement Disorder APIs (CoreMotion) under our approved entitlement
   > `com.apple.developer.health-movement-disorder` to passively measure tremor and dyskinesia on
   > Apple Watch for personal Parkinson's symptom tracking. The app makes no diagnosis and no
   > medication or clinical recommendation.*
   ⛔ Not a repo change — nothing to commit, which is exactly why it gets forgotten.
   ✅ §3.3 (disclose to end-users how their health data is used) — already satisfied by
   `website/privacy.html`. §3.4's consent/third-party duties are a **human-subject-research** clause;
   Kampa has no participants and no data recipients, so it does not bite (Bhav's call Jul 31, and the
   obligations are incoherent without third parties). ⛔ Don't re-raise it as a blocker.
   ⬜ **Opt-out paragraph ADDED to `website/privacy.html` Jul 31 — NOT DEPLOYED.** Batch with the other
   website items before spending a Netlify prod deploy (~15 of 300 monthly credits).
9. ⬜ App Privacy "nutrition label" **(verify current fields)**
14. ⬜ Subtitle (confirmed EMPTY Jul 31), keywords, description — claims-clean · Content Rights
15. ⬜ Screenshots, all required device sizes (⚠ mind the black-void bug from the web deploy)
16. ⬜ Age rating questionnaire
18. ⬜ Confirm no paid-apps agreement / banking needed for a free v1

**Tally Jul 31:** 9 of 19 verified done, 1 substantially done, 9 open — of which 3 are device tests
and 6 are ASC form-filling. The list previously read "19 remaining".

**✅ Done Jul 30:** in-app medical disclaimer + reachable Privacy/Terms (Settings → About) ·
Support URL live at `kampa.health/support` · marketing URL `kampa.health` · `support@kampa.health`
verified forwarding · privacy policy live · FAQ claims audit (no UPDRS-equivalence, no dosing
instruction, AI answer made forward-looking) · CSV export 92s → 12.4s · name/trademark cleared.

---

## Gate A — LIST (US-first, quiet). Low bar; do early.

### Technical / build-time (per-release, from Distribution-readiness)
- [x] CloudKit schema deployed Dev→Production (every changed `@Model` additive-only)
- [x] Bundle IDs + Watch companion linkage intact — **never rename** `com.bhavbhasin.pdcompanion*` (Movement Disorder entitlement is bound to it)
- [x] Entitlements on the right targets (iCloud/CloudKit, aps, Background Modes, Movement Disorder, HealthKit)
- [x] Movement Disorder distribution gate (EP5499 addendum)
- [x] Watch sync self-heals on a clean device (verified Jul 31 on build 15, TestFlight/Release, Bhaani's phone — 3 delete+reinstall cycles, watch dead and live; full record restored with correct spans, zero duplication)
- [x] Day-ahead forecast verified on a **multi-dose day** (currently gut-checked on 1-dose only)
- [ ] Stage to yourself on a clean device first

### Data safety (a health app can't ship a one-way door)
- [x] ~~**CSV/JSON import / restore path**~~ — ⛔ **NOT NEEDED, decided Jul 31 2026.** The premise was that CloudKit-as-only-restore is an untested single point of failure. It's now tested: 3 delete+reinstall cycles on a Release/TestFlight build restored the full record with correct spans and zero duplication (watch dead and watch live). Export stays one-way by design — it's for taking data OUT (clinician, analysis), not for getting it back. Don't reopen without a *failed* restore.
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
- [x] Category — Health & Fitness (set Jul 31; Medical deliberately avoided — more scrutiny)
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
