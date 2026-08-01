# App Store launch checklist

Two decisions, two bars. **List** = quiet US-first, unmarketed. **Launch** = a public/marketing push. Don't market to strangers before cold-start is solved (back-loaded value → stranger churns on day 3). Build-time gates reuse BACKLOG.md → Distribution-readiness; this doc adds the App-Store-specific + product bars.

⚠ Apple's rules shift — items marked **(verify)** need a current-docs check before submission, don't take from memory.

---

## 🎯 REMAINING TO LIST — work this order (status Aug 1 2026)

⚠️ **Verify each `⬜` against App Store Connect or the repo before working it.** This list goes stale
the same way BACKLOG.md does — the Jul 31 pass found 9 of 19 "remaining" items already done, and the
Aug 1 pass found 3 more.

**Open — 3 items** (status Aug 1, mid-session):
- ⬜ 14 · keywords + description (subtitle DONE) · ⬜ 15 · screenshots ·
  ⬜ 19 · build → App Review Information → submit

**✅ Closed on screen Aug 1:** 16 · age rating → **13+** (172 regions; 12+ Vietnam/Korea, A12 Brazil) ·
20 · regulated medical device → **No, in any country or region** · **9 · App Privacy → Data Not
Collected, PUBLISHED** (+ policy URL added — the ASC field was empty even though the policy was live;
they are two different things) · subtitle → `Passive Parkinson's tracking` · Content Rights → No ·
export compliance (no upload needed, `ITSAppUsesNonExemptEncryption = false` verified in both
plists) · 18 · paid-apps agreement → N/A, free app.

**Distribution settings decided Aug 1:** Public (⚠️ **cannot be changed after approval**) ·
Apple Silicon Mac availability **OFF** — it is ON by default and would ship a permanently empty app,
since a Mac has no paired Watch to feed the Movement Disorder API · Vision Pro OFF (1.0 incompatible
anyway) · Apple School Manager volume-price offer unchecked (inert on a free app, but it declared an
education offer that was never intended) · Tax category `App Store software` · Last-compatible: All.

**🌍 Territories — GLOBAL MINUS THE EU/EEA (decided Aug 1).** Includes UK, Switzerland, India,
Australia, NZ, Africa, rest of Asia. **All 27 EU members + Norway + Iceland deselected**, which is
what keeps the **DSA trader-status declaration** out of scope — that declaration publishes the
developer's name, address, phone and email publicly on the App Store product page, and requires
verification that takes days. ⚠️ Adding any single EU country re-triggers it.
⬜ Website follow-up (batch, not a blocker): `privacy.html` names only CCPA/CPRA. UK/India/AU are now
in scope, so the rights section should generalise beyond California.

📋 **All six ASC forms are pre-answered in [`app-store-listing-copy.md`](app-store-listing-copy.md)** —
subtitle options, keyword string, full description, nutrition-label reasoning, age-rating answers,
screenshot sizes, and the submission notes. Paste from there; don't re-derive.

20. ⬜ ⭐ **Regulated medical device status — NEW HARD GATE, was missing from this list.** Since
    **March 26 2026**, an app with a **Health & Fitness** primary or secondary category must declare
    this in ASC to distribute in the US/EEA/UK. Apple: *required for new apps … starting today*
    (existing apps have until early 2027 — **a new app does not**). **Answer: No** → Save → done; no
    further fields appear. Consistent with `terms.html:101`, `privacy.html:190`, `faq.html:310`,
    `index.html:1390`, `SettingsSheet.swift:86`.
    ⚠️ Answering the age-rating medical question **"Frequent"** would trigger this same requirement
    independently — answer **Infrequent/Mild**, which is what the app actually does.

2. ✅ **App name was NEVER open** — reserved since the TestFlight launch, confirmed on screen
   Jul 31. Record: name `Kampa`, Apple ID `6781438685`, SKU `kampa-ios-001`, bundle ID
   `com.bhavbhasin.pdcompanion` (verified against the project — entitlement binding intact),
   category Health & Fitness, status *1.0 Prepare for Submission*.

### ✅ CLOSED by the Jul 31 + Aug 1 verification passes — evidence, not a tick
1. ✅ **Delete + restore from iCloud.** Done Jul 31 on Bhaani's phone, build 15, **Release/TestFlight**,
   3 cycles (watch dead / live / live + pull-refresh). Full record restored, correct spans, 4,471 →
   4,474 rows ⇒ zero duplication. Closes item 6 (Watch sync self-heals in Release) by the same test.
   ⚠️ Residual, **not a listing blocker**: untested at Bhav's ~113k rows (25×), and a user with iCloud
   off has no restore path at all. Both accepted for a quiet US-first list.
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

11. ✅ **§1.4.1 medical-accuracy — copy read DONE Aug 1.** All 424 sentence-like strings in the
    shipping targets were extracted and read, not grepped. Two would have failed; **both are
    unreachable in v1**:
    - `InsightsView.swift:646` `"Take your 3 PM dose 45 min before lunch, not after."` — a genuine
      dosing instruction, but `startExperiment()` has **zero live callers** (sole call site commented
      out at `:580` when "Try an experiment" was hidden Jul 31). ⚠️ It ships as a dead string — if the
      experiment loop is ever un-hidden, this line is a §1.4.1 violation. Rewrite it then.
    - `InsightRegistry.swift:511-524` `workoutRationales` — unhedged efficacy claims ("Resistance
      training improves PD motor scores"). `.rationale` has **zero consumers outside that file**;
      user-facing exercise copy is the hedged version. Provenance only, as its own comment says.

    Everything that renders hedges ("a lead to test, not a conclusion", "Likely, not proven") and
    routes to the neurologist ("decisions only your neurologist can make"). **Zero `UPDRS` anywhere**
    in app or site. Disclaimer live on all five site pages.

### ⬜ GENUINELY OPEN
**Device test:**
19. ⬜ Stage to yourself on a clean device (TestFlight), then submit

### ⬜ POST-APPROVAL — before telling the other testers to switch
21. ⬜ **TestFlight → App Store transition test, on Bhaani's phone.** The one path never exercised:
    every restore test so far stayed *within* TestFlight. She is on build **15**, the App Store ships
    **16**, so iOS should offer a normal in-place update.
    ⭐ **Try the update BEFORE deleting anything** — that is the only way to learn whether the local
    container survives, which Apple's docs do not state (their help page 404s; searched Aug 1).
    Deleting first destroys the experiment and only re-proves the CloudKit restore already verified.
    1. Baseline: Support → Details row counts; copy her CSV backup folder aside (filenames are
       date-range based, so the next export overwrites the previous one).
    2. App Store → Update/Get **without deleting**. Counts intact instantly, no sync wait ⇒ local
       container survived.
    3. Only if that misbehaves: delete + reinstall ⇒ falls back to the proven CloudKit path, and
       confirms App Store builds read the same **Production** container.
    ⚠️ `syncLog` is `#if DEBUG` ⇒ **no console on an App Store build either**; Support → Details is
    the only readout. ⚠️ `cleanupDuplicates()` runs from `.task` on the main view = cold launch only;
    force-quit from the app switcher to re-run it.
    ⛔ **Do NOT push build 16 to TestFlight** — testers must stay on 15 so the store build is strictly
    newer. Same build number on both sides can make iOS refuse the in-place update.
22. ⬜ Tell the other three testers to switch. One-line instruction, plus the one caveat that matters:
    **check iCloud is on for Kampa before deleting anything** — iCloud off = no restore path.
    ⚠️ The app cannot currently tell them ([[BACKLOG]] → "Support → Details doesn't report iCloud
    status"), so this is a manual Settings check until that ships.
23. ⬜ Website batch deploy: `privacy.html` TestFlight-only wording → released; CCPA-only rights
    section → generalised for UK/India/AU. One deploy, not two (~15 of 300 monthly credits each).
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
   ✅ **Opt-out paragraph is LIVE** — verified Aug 1, `kampa.health/privacy.html` serves the "Turning
   this off" paragraph (committed `3a6448d`, auto-deployed).
   ⬜ **`privacy.html` still describes Kampa as TestFlight-only** — *"first being made available to a
   small, invite-only group of testers… may later be released on the App Store."* One-line change at
   listing time; batch it with the other website edits (~15 of 300 monthly Netlify credits per deploy).
9. ⬜ App Privacy "nutrition label" **(verify current fields)**
14. ⬜ Subtitle (confirmed EMPTY Jul 31), keywords, description — claims-clean · Content Rights
15. ⬜ Screenshots, all required device sizes (⚠ mind the black-void bug from the web deploy)
16. ⬜ Age rating questionnaire
18. ⬜ Confirm no paid-apps agreement / banking needed for a free v1

**Tally Aug 1:** 13 of 19 done, **6 open** — 5 ASC forms + the submit. (Jul 31 read 9 done / 9 open;
Aug 1 closed the restore test, the Release watch-sync test, and the §1.4.1 copy read.)

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
- [x] In-app account deletion — **N/A, confirmed Jul 31.** Zero `AuthenticationServices` /
  `ASAuthorization` / sign-in / account-creation references; Apple's requirement is conditional on
  account creation.

### Claims & regulatory hygiene (the medical-app line)
- [x] No UPDRS-equivalence claim anywhere — **zero occurrences of `UPDRS`** in app or site (Aug 1)
- [x] No dosing instruction or medication-regimen suggestion — the one imperative is dead code, see item 11
- [x] In-app + listing medical disclaimer — `SettingsSheet.swift:86` + all five site pages
- [x] App Review Guidelines §1.4.1 (medical accuracy) self-audit — **full copy read Aug 1, item 11**

### Privacy (three separate things)
- [x] Privacy policy URL live + accurate — `kampa.health/privacy.html`, incl. the Movement Disorder
  opt-out paragraph (verified live Aug 1). ⬜ One residual edit: the TestFlight-only wording.
- [ ] Apple **App Privacy "nutrition label"** in App Store Connect filled out — distinct from the policy **(verify current fields)**
- [x] HealthKit App Review rules §5.1.3 — policy states no advertising/marketing use, no third-party disclosure, no analytics or tracking SDKs

### App Store Connect mechanics
- [x] Category — Health & Fitness (set Jul 31; Medical deliberately avoided — more scrutiny)
- [ ] Name, subtitle, keywords, description — claims-clean (name reserved; subtitle confirmed EMPTY)
- [ ] Screenshots — **TWO required classes**: iPhone 6.9" (1320×2868) **and Apple Watch** (mandatory
  because a Watch app ships; one model size, consistent across localizations). 1–10 each, no alpha.
  Mind the black-void screenshot bug from the web deploy.
- [ ] Age rating questionnaire — new 4+/9+/13+/16+/18+ tiers; medical question → **Infrequent/Mild**
- [ ] ⭐ Regulated medical device status → **No** (new gate for Health & Fitness apps, see item 20)
- [x] Support URL + marketing URL — `kampa.health/support` + `kampa.health`, both live
- [x] Export-compliance / encryption declaration — `ITSAppUsesNonExemptEncryption = false` in **both** plists, so ASC won't prompt
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
