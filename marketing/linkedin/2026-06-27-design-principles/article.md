# LinkedIn ARTICLE variant - Design principles (three pillars)

- **Status:** DRAFT (ready to publish)
- **Source:** rebuild of native post #5 (`post.md`, published 2026-06-27) as a long-form LinkedIn **Article** (title + cover + inline images), for cross-share to Bhav's personal feed.
- **Target page:** Kampa Health (publish here), then cross-share to personal.
- **Why article:** unlocks real headings/bold (no Unicode-bold trick) + one inline image per pillar (the "carousel fallback" becomes inline). Personal cross-share historically ~1k views.
- **Guardrails carried over from post.md:** founder voice, no personal-patient disclosure; privacy in ownership/control framing ("stays yours", "not on our servers"), not "we can't see it"; ambient = "prefer passive, minimize logging", names food/meds/meditation taps.
- **Editor note:** LinkedIn article editor does NOT accept pasted markdown - paste plain text, apply Heading 2 / Bold / Hyperlink via toolbar. Hashtags go in the SHARE commentary, not the article body.

## Title

**PUBLISHED TITLE:** Kampa's Product Design Principles
- SEO title (carries the "Parkinson's" keyword the display title omits): `Kampa's Product Design Principles for Parkinson's`
- Article URL slug: `kampas-product-design-principles`

Titles considered (for reference): "Three Principles We Decided We Wouldn't Break - Before Building a Single Screen" · "We Built Kampa's Principles Before Its Features. Here's Why." · "Kampa's Three Design Principles for Parkinson's"

---

## Article body (labels map to editor toolbar)

**[TITLE]** Kampa's Product Design Principles  _(published title)_

When you build a health app, features are the natural place to start - the screens, the charts, the things it can do. We started Kampa somewhere else: with three principles we decided we wouldn't break, before we built a single screen.

For Parkinson's, those principles matter more than any one feature. The data is about as personal as data gets. The effort of tracking competes with the very symptoms you're trying to track. And the people using it deserve a tool that works without getting in the way.

Here's what Kampa is built on.

**[H2]** 1. Privacy is the architecture, not a setting.

The data Kampa handles is about as personal as it gets - continuous movement, tremor, sleep, heart rate. For a neurological condition, that data can reveal how your day went, whether your medication is working, even how things are shifting over time. Data this personal should stay under your control.

So privacy isn't a toggle we added at the end - it's the foundation the whole app sits on:

**[bulleted list]**
- Everything is processed **on your device** first.
- Your data lives on your device and backs up to **your own private iCloud** (Apple's CloudKit), under your account - **not on our servers**.
- The app shows you exactly what's stored - every record type, every count, the full date range. No black box.

**[Body - continue]**

And because your history lives in your private iCloud, it's resilient. Delete the app by accident, lose your phone, or switch to a new one, and it isn't gone - reinstall, restore, and it all comes back. There's no account to create, and we will never sell your data. It's the most personal data there is, and it stays yours.

**[IMAGE -> marketing/linkedin/2026-06-17-privacy/card1.png]** in-app Backup / private-iCloud screen (from the privacy post)

**[H2]** 2. Lean on the ecosystem you already wear.

Apple has already done a remarkable job here. Your iPhone and Apple Watch quietly capture a huge amount of what matters - sleep, heart rate, workouts, and, through Apple's Movement Disorder API, tremor and dyskinesia sensed passively from your wrist. HealthKit already holds your medications. Rebuilding any of that ourselves would only create redundancy and give you two places to do the same thing.

So wherever Apple already does it well, we rely on Apple rather than reinventing it. Log a medication once in Apple's native Health flow and Kampa reads it. Do a boxing session on your Watch and it's captured as a workout - we don't ask you to re-enter it. Every thing the ecosystem already captures is one less thing we ask of you - and that matters enormously for a condition where the effort of tracking competes with the very symptoms you're tracking. The intelligence then runs on-device, where your data already lives.

**[IMAGE -> docs/design/watch/watch-s11-mockup.png]** Watch sensing tremor - Series 11 46mm, silver aluminum, Kampa-blue sport band, on a clean product-shot background

**[H2]** 3. Ambient. Minimize the asking.

Parkinson's is exactly the wrong condition to hand someone a long daily form. So Kampa's default is to **observe, not interrogate**. A few things still need a tap - the food you eat, or your medications (logged through Apple's native Health flow) - but those are the light exceptions, not the price of admission.

**[IMAGE -> website/images/screenshot-daily.jpeg]** clean Day in Review, zero tapping

And even those exceptions are as light as we could make them: you can just say them out loud. Tap the microphone, speak in plain language - *"I ate blueberries and vanilla ice cream last night at 9 PM"* - and Kampa does the rest. It recognizes that's food, pulls out what you ate, and even reads the time (*"last night at 9 PM"* becomes 9:00 PM) - no menus, no typing, nothing to spell. And because Kampa transcribes your speech **on your device**, your voice - like everything else - stays yours; it isn't shipped off to a server to be understood. Voice logging isn't a someday feature; it's how you log in Kampa today.

**[IMAGE -> voice-filmstrip.png]** ONE horizontal image = all 4 voice-flow screens left-to-right with chevrons (mic -> speak -> parsed -> stored). Insert this single file so LinkedIn lays them ACROSS, not stacked vertically. Built from the 4 `website/images/voice-*.jpg` frames; regenerate via the PIL step if the source screens change.

**[Body - closing]**

None of these is something you bolt on later. They're decisions you make before the first screen exists - and they're why Kampa feels less like one more thing to manage, and more like something running quietly in the background of your day.

Kampa is for people living with Parkinson's, the people who care for them, and the researchers working on it. If that's you, I'd value your perspective. Follow along here, or see more at kampa.health (hyperlink -> https://kampa.health).

---

## Images (all in repo, no compositing)

| Slot | File | Note |
| --- | --- | --- |
| Cover banner | `website/images/screenshot-tremor.jpeg` (2736x1260) | only true landscape hi-res product shot; LinkedIn crops to 16:9 |
| Privacy inline | `marketing/linkedin/2026-06-17-privacy/card1.png` (1080x1350) | reused from the privacy post - in-app Backup / private-iCloud screen; matches the elaborated privacy copy. Alts: `card2.png` (branded "data -> iCloud" statement card, also from privacy post) or `website/images/screenshot-observations.jpeg` (on-device data). Could run 2 here (card1 + card2) since section is now longer. |
| Ecosystem inline | `docs/design/watch/watch-s11-mockup.png` (1280x1640) | Watch = ecosystem; Series 11 46mm, silver aluminum case, Digital Crown + flush side button, Kampa-blue sport band, product-shot background. Rendered via CSS/headless-Chrome (source `watch-s11-mockup.html`). Prior options if needed: `watch-app-screen-framed.png` (matches current site) / `watch-app-screen-v1.png` (frameless). |
| Ambient inline | `website/images/screenshot-daily.jpeg` | clean dashboard, zero taps in frame |
| Ambient - voice flow | `voice-filmstrip.png` (single horizontal image, in article folder) | shipped voice logging as ONE across-the-page strip: mic -> speak natural language -> auto-classified (Food) + time parsed -> stored on timeline w/ nutrients. Insert this one file (not the 4 separate JPGs, which stack vertically on LinkedIn). Proof for the present-tense voice copy. |

---

## Share commentary (hashtags live here, NOT in article body)

**Kampa-page share blurb:**
> We started Kampa from the principles, not the features. The three we decided we wouldn't break - and why they matter more for Parkinson's than any single feature. #Parkinsons #DigitalHealth #ProductDesign #AppleWatch #HealthKit #Privacy

**Personal cross-share (first person - leans on operator credibility, drives Bhav's personal-feed reach):**
> A lot of what I've learned in 20+ years of building products came down to this: the hardest decisions aren't features, they're the principles you refuse to break. For Kampa, we made three of those before we built a single screen. I wrote up what they are and why Parkinson's raises the stakes on each one. Would genuinely value your read and your take.
>
> #Parkinsons  #ProductDesign #BuildingInPublic #Kampa
