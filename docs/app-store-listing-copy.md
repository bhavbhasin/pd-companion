# App Store listing — copy pack

Everything needed to fill the five open ASC forms in one sitting. Fields verified against Apple's
current docs Aug 1 2026 (sources at the bottom). **Paste, don't retype** — the description is
claims-audited and every claim traces to `website/index.html`, `website/faq.html`, or
`website/privacy.html`, all of which passed the §1.4.1 read.

⛔ Per `brand-guide.md`: calibrated, never overstated; no health status of anyone on the team appears
in a public artifact.

---

## 0. Work order — which ASC page holds what

ASC moves fields between pages between releases, so match on **field name**, not on a click path.

| ASC page | Fields | §|
|---|---|---|
| **App Information** | Subtitle · Category (done) · Content Rights · Age Rating · **Regulated Medical Device Status** · Privacy Policy URL (done) | 1, 4, 5 |
| **Pricing and Availability** | Price: **Free** · Availability: **United States only** | 0.1 |
| **App Privacy** | Nutrition label → Data Not Collected | 3 |
| **1.0 Prepare for Submission** | Screenshots · Promotional Text · Description · Keywords · Support/Marketing URL (done) · Build · App Review Information · Version Release | 2, 6, 8 |
| **Business / Agreements** | Nothing to do for a free app | 7 |

### 0.1 Pricing and Availability — set territories to **United States only**

Not previously on the checklist, and it does more than match the "quiet US-first" plan:

- It is the decision that makes **§5's regulated-device answer a single US field** instead of three.
- It sidesteps the **global food-coverage gap** — the USDA corpus resolves 32.8% and fails
  African/Middle-Eastern/SE-Asian foods. A worldwide listing ships that failure to people it fails.
- ⚠️ It should also sidestep the **EU DSA trader-status declaration** required to distribute on EU
  storefronts. Confidence: high that this exists, **not verified against Apple's current docs** —
  check it before ever adding EU territories, not now.

### 0.2 Content Rights

The question is whether the app contains third-party content you need rights to. Kampa ships the
**USDA FoodData Central** corpus, which is **US-government public domain** — no licence, no
attribution obligation. Either answer is defensible; **"No"** is the simpler true one, since nothing
rights-restricted ships. Your call, it is one radio button.

### 0.3 Version Release — choose **Manually release this version**

The default publishes the moment review approves, which could be 3 a.m. on a day you are not
watching. Manual keeps the listing date yours. This matters more than usual here: the Movement
Disorder entitlement can draw extra review scrutiny, so approval timing is unpredictable.

---

## 1. Name / subtitle / keywords

**Name** — `Kampa` (reserved, Apple ID `6781438685`). No change.

**Subtitle** — 30 characters max. Currently empty.

| Option | Chars | Note |
|---|---|---|
| ⭐ `Passive Parkinson's tracking` | 28 | **Recommended.** Apple indexes the subtitle for search, so this buys "Parkinson's" + "tracking" and frees both from the keyword field. Says what it does in three words. |
| `Tremor patterns, automatically` | 30 | Leads with the sensation, not the disease. Weaker search value. |
| `See what affects your tremor` | 28 | Benefit-led, but "affects" edges toward a causal claim. |

**Keywords** — 100 characters max, comma-separated, **no spaces after commas** (a space costs a
character). Do not repeat the name or subtitle; Apple indexes those separately.

```
tremor,dyskinesia,levodopa,carbidopa,medication,symptom,movement,neurology,wearing off,journal,PD
```
97 characters. Deliberately excluded: `sinemet` and other brand drug names (third-party trademarks —
a rejection risk for no gain), `apple watch` (Apple trademark), `health`/`fitness` (the category
already indexes those).

---

## 2. Description

4000 characters max. Draft below is ~2,150 — deliberately short of the cap; nobody reads past the
third paragraph, and every extra sentence is another claim to defend.

```
Notice what your body already knows.

No two people experience Parkinson's the same way. Kampa passively measures tremor
and dyskinesia through Apple Watch, lines them up with every dose, meal, workout,
and night of sleep, and surfaces the patterns that hold true for you.

No manual symptom tracking. No daily check-ins. You wear the watch and live your day.

PASSIVE, ALL DAY
Kampa uses Apple's Movement Disorder API — developed specifically for Parkinson's
symptom monitoring — to measure tremor and dyskinesia in the background on Apple
Watch. Nothing to start. Nothing to remember.

YOUR MEDICATION, ON THE SAME TIMELINE
Doses you log in the Health app appear alongside your measurements. Kampa shows how
your tremor moves after a dose, how long the effect holds, and where the uncovered
stretches fall in your day.

LOG BY VOICE
Meals, medication, mindfulness, symptoms — say it and Kampa files it. Built for the
days when typing is hard.

DAILY OBSERVATIONS, CROSS-DAY INSIGHTS
Observations tell you what happened today. Insights look across weeks for the
patterns that repeat — each one carrying how much of your own data stands behind it,
so you can tell a real signal from an early hint.

WHAT TO EXPECT TODAY
A view of the day ahead built from your own dose-response history, not a generic
model of an average patient.

PRIVACY ISN'T A FEATURE HERE
Everything is processed on your device and stored in your own private iCloud. No
third-party analytics. No advertising SDKs. No tracking. Your health data is never
transmitted to us — we could not read it if we wanted to.

WHAT KAMPA IS NOT
Kampa is a wellness and self-tracking tool. It is not a medical device. It does not
diagnose, treat, cure, or prevent any disease, including Parkinson's disease, and it
never tells you to change your medication. Any pattern it surfaces is a starting
point for a conversation with your neurologist, not a substitute for one.

WHAT YOU NEED
An iPhone 11 or newer running iOS 26, and an Apple Watch Series 4 or newer running
watchOS 10. The Watch is essential — it is where tremor and dyskinesia are sensed.
It does not need to be a recent one.
```

⚠️ Deliberately absent, keep it that way: no UPDRS or any clinical-scale equivalence · no accuracy
or validation percentage · no efficacy claim about any drug, food, or exercise · no dosing or timing
instruction · no essential-tremor claim (`faq.html:307` promises not to claim it until validated).

**Promotional text** — 170 characters, optional, and the only listing field editable **without a
review**. Use it for shipped-feature news. Starter:

```
New: charts now scroll back through your whole record, and detail views show how
long you spend at each severity level.
```

---

## 3. App Privacy nutrition label → **Data Not Collected**

Answer the first question "Do you or your third-party partners collect any data from this app?" with
**No**. That ends the questionnaire.

This is defensible, not convenient. Apple defines *collect* as "transmitting data off the device in a
way that allows you and/or your third-party partners to access it." Verified in the repo Aug 1:

- **Zero networking code.** No `URLSession`, no `dataTask`, no `URLRequest` anywhere in either target.
  The only four `https://` strings are links opened in Safari (`SettingsSheet.swift:59,61,83,85`).
- **Zero third-party dependencies.** No Swift Package references in `project.pbxproj` at all — so no
  analytics or ad SDK can be collecting behind your back.
- **CloudKit is the user's own private database.** You have no access to it, so it is not collected.
- **Support email** falls under Apple's optional-disclosure exception (user-initiated, not used for
  tracking or advertising, not core functionality).

⚠️ The moment any analytics ships — including the privacy-first counters in Gate B — this answer
changes. Revisit it in the same commit.

---

## 4. Age rating questionnaire

Apple replaced this in 2025; tiers are now **4+ / 9+ / 13+ / 16+ / 18+**, and there are four new
questions (in-app controls, capabilities, **medical or wellness topics**, violent themes).

| Question | Answer | Why |
|---|---|---|
| Medical or wellness topics | **Infrequent/Mild**, not Frequent/Intense | Kampa shows the user their *own* logged data. It contains no medical instruction, no treatment guidance, no drug reference material. ⚠️ **"Frequent" would trigger the regulated-medical-device declaration on its own** — see §5. |
| Violence, sexual content, profanity, horror, gambling, contests | **None** | |
| Unrestricted web access | **No** | The four links open in Safari, they are not an in-app browser. |
| User-generated content / social features | **No** | Nothing a user logs leaves their device. |
| Messaging / chat | **No** | |

Expected result: **4+**.

⚠️ Read the medical question's exact wording on screen — Apple's help page does not reproduce the
questionnaire, so this row is reasoned from the app's behavior, not copied from Apple's text. It is
the one answer worth a careful read.

---

## 5. ⭐ Regulated medical device status — **NEW, and a hard gate**

**This is not on the launch checklist and it blocks distribution.** Since March 26 2026, an app whose
primary or secondary category is **Health & Fitness** or Medical — Kampa's is Health & Fitness —
must declare a regulated medical device status in App Store Connect to distribute in the US, EEA, or
UK. Apple's wording: *required for new apps … in order to distribute in these regions, starting
today.* Existing apps have until early 2027; **a new app does not.**

**Answer: No.** Select "No", click Save, done — Apple requires no further information when the answer
is No. All the heavy fields (FDA Owner/Operator Number, Instructions for Use URL, indications-for-use
statement, safety information) only appear behind "Yes".

"No" is consistent with every other artifact: `terms.html:101`, `privacy.html:190`, `faq.html:310`,
`index.html:1390`, and `SettingsSheet.swift:86` all state Kampa is not a medical device and does not
diagnose, treat, cure, or prevent disease.

---

## 6. Screenshots

**Two size classes are required, not one.** The checklist says "all required device sizes" without
naming them.

| Class | Required? | Portrait pixels | Count |
|---|---|---|---|
| iPhone 6.9" | **Yes** — or 6.5" if 6.9" is absent | 1320 × 2868 | 1–10 |
| **Apple Watch** | **Yes — mandatory because Kampa ships a Watch app** | your Watch's native size; keep it identical across localizations | 1–10 |

⭐ **Bhav's iPhone Air is a 6.9" device — it captures 1320 × 2868 natively.** Screenshot on the phone
and upload; no Simulator, no upscaling, and no empty-state problem (the Simulator cannot run the
Movement Disorder API at all — `MovementDisorderManager.swift:34`).

**Watch capture:** side button + Digital Crown together; the image lands in iPhone Photos at the
Watch's native resolution, which is by definition one of Apple's accepted sizes.
⚠️ Requires Watch app → General → **Enable Screenshots** turned on first — it is off by default.

Smaller iPhone classes (6.3", 6.1", 5.5") are optional; Apple scales the 6.9" set down.
No alpha channel, no transparency. `.png` or `.jpg`.

⚠️ Watch as the more likely miss — it is easy to submit iPhone shots, hit Save, and only find the
Watch requirement at submission.
⚠️ Mind the black-void screenshot bug seen during the web deploy.

Suggested six, in narrative order: Day in Review · tremor trend with dose markers · a dose-response
curve · an Insight card showing its confidence tier · voice logging mid-capture · the privacy screen.

---

## 7. Paid Apps agreement — not needed

A free app with no in-app purchases ships under the Free Apps terms already accepted with the
developer account. The Paid Apps agreement and its banking/tax forms are only required to charge.
⚠️ Freemium (Gate B, ~$7.99) flips this — banking and tax forms take days to clear, so start them
before the paywall work, not after.

---

## 8. At submission — App Review Information → Notes

⭐ Contractually required by EP5499 §4 and there is no repo artifact to remind you. Paste:

> Kampa uses Apple's Movement Disorder APIs (CoreMotion) under our approved entitlement
> `com.apple.developer.health-movement-disorder` to passively measure tremor and dyskinesia on
> Apple Watch for personal Parkinson's symptom tracking. The app makes no diagnosis and no
> medication or clinical recommendation.

Also supply a demo account note: **no account is needed** — the app is on-device with no sign-in.
Tell the reviewer the app needs a paired Apple Watch to show tremor data, and that a simulator will
show an empty state (`MovementDisorderManager.swift:34`). A reviewer without a Watch seeing an empty
app is a plausible rejection path — pre-empt it here.

---

## Sources
- [Screenshot specifications](https://developer.apple.com/help/app-store-connect/reference/screenshot-specifications/)
- [App privacy details on the App Store](https://developer.apple.com/app-store/app-privacy-details/)
- [Updated age ratings in App Store Connect](https://developer.apple.com/news/?id=ks775ehf)
- [Declare regulated medical device status](https://developer.apple.com/help/app-store-connect/manage-app-information/declare-regulated-medical-device-status/)
- [Update on regulated medical device apps in the EEA, UK, and US](https://developer.apple.com/news/?id=nyqbfz1y)
