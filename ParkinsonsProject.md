# PD Companion — Project Context & Brief
> This file is the single source of truth for AI assistants (Claude, Claude Code, Cursor) working on this project.
> Update it as decisions are made. Paste it at the start of any new AI session to restore full context instantly.

---

## The Builder

- **Name**: Bhav Bhasin
- **Email**: bhavdeep.bhasin@gmail.com (Apple ID, Apple Developer account, GitHub, privacy policy contact — all unified under this)
- **GitHub**: github.com/bhavbhasin
- **Diagnosis**: Parkinson's disease, diagnosed 2022
- **Background**: iOS/watchOS developer with existing working app using FFT-based tremor analysis via accelerometer + gyroscope
- **Motivation**: Built this for myself first. If it works for me, I want to make it available to other Parkinson's patients — affordably, and with the patient's dignity and cognitive load in mind.

---

## The Problem Being Solved

Existing tools (notably StrivePD by Rune Labs) have real limitations from a patient's perspective:

- **High cognitive and motor burden**: Manual logging of symptoms, mood, medications and events is hard for people with tremor and cognitive PD symptoms
- **Journalling-first design**: Built around active data entry rather than ambient passive sensing
- **Clinician-facing, not patient-intelligence-facing**: Value delivered at clinic appointments, not in daily life
- **Exorbitant pricing**: $14.99/month (StrivePD Guardian) is unjustifiable for a Parkinson's patient population, many on fixed incomes
- **No predictive layer**: Shows what happened, does not anticipate what is about to happen
- **US/Apple only**: Regulatory constraints limit reach
- **Data used for pharma research**: Patients are partly the product, not just the customer

**Bhav tried StrivePD personally and found limited value.** This is not theoretical — it is direct patient feedback.

---

## Core Design Philosophy

> **"Take cognitive load off an already struggling individual."**

This is the founding principle. Every design decision runs through this filter:
*Does this add cognitive load or reduce it?*

### Principles
1. **Ambient first** - the app watches, listens, and infers. Logging is a last resort, not the primary input
2. **Voice-enabled input** - speak naturally instead of navigating menus or tapping with tremoring hands
3. **Camera/photo input** - photograph a meal, a location, an activity rather than typing it
4. **Passive HealthKit inference** - pull sleep, exercise, HRV, mindfulness from HealthKit automatically without asking the user
5. **Zero-burden UX** - if the user has to think about using the app, the app has already failed
6. **Privacy-first** - data stays on-device and in the user's own HealthKit. Never sold. Never shared.
7. **Patient-aligned pricing** - affordable or free for patients, especially at the personal use stage

---

## Product Roadmap

### Phase 1 - Foundation & Telemetry (Current Focus)
**Goal**: Replace FFT accelerometer approach with Apple's Movement Disorder API for true background monitoring

- [ ] Get Movement Disorder API entitlement approved (in progress - see below)
- [ ] Integrate `CMMovementDisorderManager` for passive background tremor + dyskinesia tracking
- [ ] Integrate HealthKit - read sleep, exercise, HRV, heart rate, mindfulness minutes, activity
- [ ] All data stored on-device / in personal HealthKit store only
- [ ] Simple dashboard: tremor and dyskinesia patterns over time
- [ ] Replace current FFT foreground-only tracking with background-capable API

**Success metric**: Passively capturing real continuous tremor/dyskinesia data throughout the day without the app needing to be open

### Phase 2 - Correlation Engine
**Goal**: Surface meaningful patterns between symptoms and lifestyle events

- [ ] Correlation logic: tremor severity vs. sleep quality, exercise type/duration, meditation, HRV, time of day, medication timing
- [ ] On-device ML via Core ML - no data leaves the device
- [ ] Voice input layer for ambient event logging
- [ ] Camera/photo input for meals, activities, context
- [ ] HealthKit auto-inference to minimise manual logging
- [ ] Lightweight journalling as optional feature (not the core)
- [ ] Visualisations that are interpretable, not just charts

**Success metric**: Bhav discovers at least one actionable correlation that changes how he manages his day

### Phase 3 - Predictive / Preemptive
**Goal**: Anticipate tremor/dyskinesia episodes before they happen and suggest interventions

- [ ] Personal longitudinal model trained on Bhav's own data (on-device, Core ML)
- [ ] Early warning system: "conditions look similar to days when you had a high-tremor afternoon"
- [ ] Intervention suggestions based on personal history: "on days like this, a 20-min walk before noon reduced your tremor by X%"
- [ ] Smart, low-noise notifications - only alert when genuinely predictive
- [ ] Wrist haptics on Apple Watch for subtle, non-stigmatising alerts

**Success metric**: Bhav successfully anticipates and moderates an episode using the app's guidance

### Phase 4 - Scaled Patient App (Future)
When Phase 3 is proven on Bhav's own data:

- Resubmit Movement Disorder API entitlement with research/multi-patient framing
- Build opt-in, consent-first data aggregation (ResearchKit consent flow)
- HIPAA-eligible backend (AWS/Google Cloud/Azure HIPAA tier)
- Partner with neurologist or patient advocacy org for IRB coverage
- Pricing: affordable/tiered - not $15/month
- Consider partnership with organisations like Michael J. Fox Foundation
- Potential FDA 510(k) clearance (StrivePD proved this pathway is navigable)
- Update privacy policy to reflect multi-user, data-sharing context before any public launch

---

## Technical Stack

### Platform
- **iOS + watchOS** - native Swift/SwiftUI only (no React Native, Flutter etc.)
- CoreMotion Movement Disorder API requires native code on Apple Watch
- **Xcode** - required for build/signing/deployment

### Key Apple APIs
- `CMMovementDisorderManager` (CoreMotion) - tremor + dyskinesia background tracking
- **HealthKit** - sleep, HRV, exercise, heart rate, mindfulness, activity
- **WatchConnectivity** - Watch to iPhone data sync
- **Core ML** - on-device correlation and prediction models
- **Speech framework** - voice input (Phase 2+)
- **AVFoundation / Vision** - camera/photo input (Phase 2+)

### AI-Assisted Development Tools
- **Cursor** - daily Swift editing with inline AI assistance (primary IDE alongside Xcode)
- **Claude Code** - complex multi-file architectural tasks, HealthKit + CoreMotion wiring (set up and active)
- **Claude Pro (claude.ai)** - product thinking, architecture decisions, documentation
- **Model guidance**: Use Sonnet for day-to-day work; switch to Opus for hard architectural problems, complex debugging, and Phase 2/3 ML design

### Data Architecture Principle
Design the Phase 1 data model with Phase 3 in mind. Schema for tremor readings, HealthKit events, and annotations must support correlation analysis and on-device ML prediction without a painful migration later.

---

## Apple Entitlement Request

### Status
- [x] Apple Developer account created (Individual/Sole Proprietor, under bhavdeep.bhasin@gmail.com)
- [x] Privacy policy written and finalised
- [x] GitHub account created (github.com/bhavbhasin)
- [x] Privacy policy hosted on GitHub Pages (repo: pd-companion)
- [ ] App ID registered in Developer portal (Watch Extension App ID)
- [x] Entitlement request submitted (May 6, 2026)
- [x] Entitlement APPROVED by Apple (May 8, 2026)

### Privacy Policy
- **File**: privacy-policy.html
- **Repo**: github.com/bhavbhasin/pd-companion
- **Live URL (once Pages enabled)**: https://bhavbhasin.github.io/pd-companion/privacy-policy.html
- Personal-use framing, first-person voice, Bhav's story in the intro
- Covers: Movement Disorder API (7-day windows, arm selection), HealthKit, data storage, no sharing, regulatory disclaimer (not a medical device), children's privacy, future-state transparency
- Em dashes removed (replaced with hyphens) to avoid AI-written tells
- Will need to be fully replaced (not updated) when app goes public in Phase 4

### What's Needed for Submission
- Entitlement key: `com.apple.developer.CoreMotion.movement-disorder`
- Must be requested by Account Holder in Apple Developer portal
- Path: Certificates, Identifiers & Profiles → Identifiers → Watch Extension App ID → Capability Requests tab

### Submission Strategy
**Framing**: Personal use by a Parkinson's patient, not a research platform (yet)

**Key points to include in request form**:
1. Bhav is a Parkinson's patient (diagnosed 2022) building this for personal symptom management
2. Existing working app already built using FFT-based tremor analysis - proof of technical seriousness
3. Specific technical gap: current FFT approach only works in foreground; Movement Disorder API enables essential background monitoring
4. Data stays on-device / in HealthKit - no server, no data sharing
5. Intent to eventually make available to other PD patients affordably
6. Privacy policy URL: https://bhavbhasin.github.io/pd-companion/privacy-policy.html

### Draft Entitlement Request Description
> Copy-paste this into the Apple capability request form:

"I am a Parkinson's disease patient (diagnosed 2022) who has developed a working iOS/watchOS application to track tremor and dyskinesia symptoms. The app currently uses FFT analysis of raw accelerometer and gyroscope data, but is fundamentally limited to foreground operation only - making continuous, real-world monitoring impractical for daily use. The CMMovementDisorderManager API would enable passive background monitoring throughout the day, which is essential for capturing real symptom patterns in normal life, not just during deliberate tracking sessions. All data will remain on-device and in my personal HealthKit store - no server, no data sharing, no third-party access. I intend to eventually make this tool available free or at low cost to other Parkinson's patients."

### After Approval
- [ ] Add entitlement key to Watch Extension `.entitlements` file:
  ```xml
  <key>com.apple.developer.CoreMotion.movement-disorder</key>
  <true/>
  ```
- [ ] Enable capability in Xcode under Watch Extension target → Signing & Capabilities
- [ ] File a DTS ticket alongside submission to put a human eye on it faster

---

## Competitive Landscape

### StrivePD (Rune Labs) - Primary Reference Point
- Originally built by Aura Oslapas, a Parkinson's patient, for herself - then acquired by Rune Labs in 2019
- FDA 510(k) cleared - proves the regulatory pathway is navigable
- Uses `CMMovementDisorderManager` - proves Apple approves this entitlement for PD apps
- Free base app + $14.99/month Guardian tier
- Real business model is pharma clinical trial data, not patient subscriptions
- **Key weaknesses from patient perspective**:
  - High cognitive/motor burden - journalling-first design
  - Clinician-facing value, not real-time patient intelligence
  - No predictive/preemptive layer
  - US + Apple only
  - Patient data partially used for pharma research pipeline
  - Bhav tried it personally and found limited value

### Differentiation
| | StrivePD | This App |
|---|---|---|
| Primary input | Manual logging | Ambient / voice / camera |
| Value delivery | At clinic appointments | In daily life, in real time |
| Predictive layer | None | Core Phase 3 feature |
| Data philosophy | Pharma research pipeline | Stays with patient |
| Pricing | $14.99/month premium | Patient-aligned |
| Cognitive burden | High | Minimal by design |
| Built by | Engineers/clinicians | A Parkinson's patient |

---

## Infrastructure & Accounts

| Service | Account | Status |
|---|---|---|
| Apple ID | bhavdeep.bhasin@gmail.com | Active |
| Apple Developer Program | Individual/Sole Proprietor | Active ($99/yr paid) |
| GitHub | github.com/bhavbhasin | Active |
| GitHub repo | pd-companion | Active, SSH auth configured, local at ~/Documents/ParkinsonsProject |
| GitHub Pages | https://bhavbhasin.github.io/pd-companion/ | Active |

---

## Key Decisions Made

| Decision | Choice | Rationale |
|---|---|---|
| Platform | Native Swift/SwiftUI only | CoreMotion API requires native; no cross-platform workaround |
| Primary dev tool | Cursor + Claude Code | Cursor for daily edits; Claude Code for complex architecture |
| Data storage (Phase 1) | On-device + HealthKit only | Privacy, simplicity, entitlement approval framing |
| ML approach | On-device Core ML | Privacy-first; no data leaves device |
| Input paradigm | Ambient + voice + camera | Cognitive load reduction |
| Competitor response | Differentiate, don't compete head-on | Predictive layer + UX philosophy are the moat |
| Phase sequence | Personal → research → commercial | De-risks each phase; personal data proves the concept |
| Developer account type | Individual/Sole Proprietor | Solo developer, personal use app, faster approval |
| Unified identity | bhavdeep.bhasin@gmail.com | Apple ID = Developer account = GitHub = privacy policy contact |
| GitHub username | bhavbhasin | Clean, professional, available |
| App name | "PD Companion" (placeholder) | Rename before public launch - name should carry design philosophy |
| Privacy policy style | Personal, first-person, Bhav's story | Honest framing for entitlement review; no corporate boilerplate |
| Claude model strategy | Sonnet for daily work, Opus for hard problems | Speed vs depth tradeoff |

---

## Open Questions / To Decide Later

- [ ] App name - "PD Companion" is placeholder; final name should carry design philosophy and Bhav's voice
- [ ] Watch-only vs. Watch + iPhone primary interface
- [ ] Specific HealthKit data types to correlate in Phase 2
- [ ] Voice input: native Speech framework vs. Whisper on-device
- [ ] Camera input: what exactly gets captured - meal photos? location context? activity recognition?
- [ ] Notification strategy: how to be useful without being annoying
- [ ] Phase 4 backend: which HIPAA-eligible cloud provider
- [ ] IRB / research partnership strategy for Phase 4
- [ ] Monetisation model for Phase 4 (patient subscription vs. pharma partnership vs. both)
- [ ] Whether to open-source any part of the project

---

## Session Log

### Session 1 - May 2026
**Topics covered**: Tool selection (Cursor + Claude Code), Movement Disorder API entitlement strategy, competitive analysis (StrivePD), product roadmap (3 phases + Phase 4 scale), core design philosophy, privacy policy drafted and refined, Apple Developer account created (Individual), GitHub account created (bhavbhasin), repo created (pd-companion), privacy policy personalised with Bhav's story and updated with regulatory/safety/children's privacy sections.

**Next actions**:
1. Upload privacy-policy.html to GitHub repo pd-companion
2. Enable GitHub Pages on the repo
3. Verify privacy policy is live at https://bhavbhasin.github.io/pd-companion/privacy-policy.html
4. Register Watch Extension App ID in Apple Developer portal
5. Submit Movement Disorder API entitlement request
6. File DTS ticket alongside entitlement request

---

## How to Use This File

**In Claude.ai (new session)**: Paste the full contents at the start of the conversation. Claude will have full project context instantly.

**In Claude Code**: Place this file in the root of the Xcode project repo as `ParkinsonsProject.md`. Claude Code will read it automatically when you start a session in that directory.

**In Cursor**: Reference it with `@ParkinsonsProject.md` in any Cursor chat.

**Updating**: After any significant product or technical decision, update the relevant section and add a note to the Session Log.

### Session 2 - May 7, 2026
**Topics covered**: Claude Code setup and configuration, Google Drive mounted locally (`/Users/bhav/Library/CloudStorage/GoogleDrive-bhavdeep.bhasin@gmail.com/`), git initialized with SSH authentication to GitHub, Xcode project created with iOS + watchOS targets, capabilities configured.

**Capabilities configured**:
- iOS: HealthKit, Motion & Fitness, Background Modes (background fetch, background processing)
- watchOS: HealthKit, Background Modes (workout processing, session type: physical therapy)

**Environment established**:
- Xcode 26.4.1 active
- Git global config set (Bhav Bhasin, bhavdeep.bhasin@gmail.com)
- SSH key (ed25519) added to GitHub for passwordless push/pull
- CLAUDE.md updated with Google Drive path and communication preferences

**Next actions**:
1. ~~Awaiting Movement Disorder API entitlement approval from Apple~~ — APPROVED May 8
2. ~~Begin coding Phase 1 foundation once entitlement is approved~~ — DONE in Session 3
3. Change Mac password (exposed in chat during sudo attempt) — STILL PENDING

### Session 3 - May 8, 2026
**Topics covered**: Movement Disorder API entitlement approved by Apple. Phase 1 foundation fully built, builds clean on iOS and watchOS simulators, committed to GitHub.

**What was built (commit d8e4dd3)**:
- **Watch app**: `MovementDisorderManager` (CMMovementDisorderManager wrapper with simulator-safe handling), `WatchConnectivityManager` (sends data to iPhone), `WatchDashboardView` (latest reading + today's averages)
- **iPhone app**: `HealthKitManager` (sleep, HRV, RHR, exercise, mindfulness, steps), `PhoneConnectivityManager` (receives Watch data, persists to SwiftData), `DashboardView` with `TremorChartView` and `HealthSummaryView`
- **Shared models**: `SymptomData.swift` with `TremorSample` and `HealthSample` Codable structs
- **iPhone SwiftData models**: `TremorReading`, `HealthSnapshot`
- **Build settings**: HealthKit + Motion usage descriptions properly configured via INFOPLIST_KEY_* in project.pbxproj (Xcode 16 GENERATE_INFOPLIST_FILE pattern)

**Critical implementation details to remember**:
- `CMMovementDisorderManager` crashes in simulator due to entitlement check — code uses `#if targetEnvironment(simulator)` to bail out gracefully. Real Apple Watch (Series 4+) required for actual data.
- Apple's API typically requires ~24 hours of wear before producing tremor results.
- Switched from Sonnet 4.6 to Opus 4.7 mid-session due to API hallucinations (wrong CoreMotion method names). Opus should be the default for Swift work.

**Next session starts here — deploy to physical devices**:
1. Connect iPhone to Mac via USB cable, trust the computer
2. Enable Developer Mode on iPhone (Settings → Privacy & Security → Developer Mode → On)
3. Enable Developer Mode on Apple Watch (Settings → Privacy & Security → Developer Mode)
4. Verify iPhone is paired with Apple Watch (in Watch app on iPhone)
5. Verify both devices have a passcode (required for HealthKit)
6. In Xcode: select PD Companion scheme + iPhone as destination, press ⌘R
7. Grant HealthKit + Motion permissions on first launch
8. Watch app should auto-install (or install via Watch app → Available Apps)
9. Begin actual tremor monitoring (data takes ~24h to start appearing)

**Still pending from Session 2**: Change Mac password (was exposed during sudo command in chat).

---

*Last updated: May 8, 2026 - Session 3 complete; Phase 1 built and committed*
