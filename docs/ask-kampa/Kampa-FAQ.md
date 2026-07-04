# Kampa - Frequently Asked Questions

Draft for kampa.health/faq and the in-app Help screen. Voice: calm, honest, second person, spaced hyphens, no em dashes. Entries marked [SHIP-GATED] should be published only when the feature is live.

> Canonical source of truth. The static page (`website/faq.html`) and the bot knowledge file (`netlify/functions/faq-knowledge.md`) are derived from this - keep this master current and regenerate the derivatives when it changes.

---

## Getting started

### What do I need to run Kampa?

An iPhone 11 or newer running iOS 26 or later, and an Apple Watch Series 4 or newer running watchOS 10 or later. The Watch is essential - it is where tremor and dyskinesia are sensed. Kampa works with older Watches like the Series 5 and first-generation SE.

### I installed Kampa and it says "no data yet." Is something wrong?

No - this is expected. Tremor sensing needs a few days of regular Watch wear before patterns appear. Wear your Watch through your normal days, and Kampa will start showing data as it accumulates. If you see nothing after 3-4 days of wear, check that Kampa has Motion and Health permissions in Settings.

### Do I need to open the app every day?

No, but open it every few days. Your Watch stores about a week of tremor data and hands it to your iPhone when the app opens. If the app stays closed longer than that, the oldest days can be lost. Kampa will remind you if it has not heard from your Watch in a while - that reminder is the one notification we will always send, because your data matters. We are working toward fully automatic background sync.

### Which permissions does Kampa ask for, and why?

Health access (to read sleep, exercise, heart data, medications, and to save what you log), Motion access on the Watch (tremor and dyskinesia sensing), and optionally notifications (used only for the handful of things worth interrupting you for - like the Watch losing sync). Kampa asks for nothing it does not use.

### How do I log my medications?

In the Apple Health app, which is the system of record for medications on iPhone. Log a dose there (or via Siri with Apple's own medication features) and Kampa reads it automatically and places it on your timeline. Kampa deliberately does not keep a separate medication list - one list, no double entry.

---

## Understanding your data

### What does the 0-4 tremor scale mean?

It is a None-to-Strong severity estimate produced automatically from your Apple Watch. The labels echo the severity language clinicians use, but the number is a passive estimate from wrist sensing - not a doctor's exam, and not a clinical score. Use it to compare your own days against each other, not to compare yourself against anyone else.

### Why does my tremor number look different from another app I use?

Different apps measure different things. Kampa's chart shows tremor intensity - how strong the tremor was, hour by hour. Some other apps report duration - how many minutes of tremor occurred. Both are legitimate lenses; a day can have long mild tremor or brief strong tremor. Neither number is wrong; they answer different questions.

### What is dyskinesia, and why does mine show zero?

Dyskinesia refers to involuntary movements that can occur as a side effect of levodopa medication, usually at peak dose. Not everyone experiences it - if you don't, a flat line is the correct reading, not a broken feature. Wrist sensing can also register some ordinary movement as possible dyskinesia, so Kampa is deliberately conservative about what it shows.

### Why do tremor and dyskinesia sometimes look like opposites on the chart?

Because pharmacologically they often are. Tremor tends to peak before a dose (medication worn off) and dyskinesia at peak dose. Seeing them rise and fall in opposite rhythm around your doses is the levodopa cycle made visible - many people find this one chart explains their day better than anything else.

### What is the difference between Observations and Insights?

Observations describe today: "Tremor eased 68% in the hour after your 8 AM dose." They are honest descriptions of what co-occurred, not proof of cause. Insights are patterns that hold up across many days and pass statistical checks before you ever see them. Observations are the daily read; Insights are the accumulated evidence.

### What do the confidence labels on Insights mean?

Emerging, moderate, and strong reflect how much evidence supports a pattern - how many days, how large the effect, and how consistently it repeats. Kampa shows the basis plainly ("based on 23 days"). If a pattern stops holding, its card is downgraded or retired. We would rather show you nothing than something that is not real.

### Why do I have so few Insights? / Why did a card disappear?

Because Kampa applies real statistical standards before claiming anything, and honest standards mean fewer, better cards. Some things genuinely have no effect on your symptoms - learning that is valuable too. Cards appear when evidence clears the bar and retire when it no longer does; the screen reflects the current state of evidence, never a highlight reel.

---

## Insights in depth

### [SHIP-GATED] What is an Experiment?

A structured way to test one specific change - for example, taking your afternoon dose on an emptier stomach - using data you already generate passively. You approve a simple plan, live normally for about two weeks, and Kampa reads the result: it worked, it made no difference, or the data was not clear enough to say. No extra logging, and you can stop an experiment at any time. A "no effect" verdict is a real result - one less thing to wonder about.

### [SHIP-GATED] How does the daily forecast work?

Kampa learns how your medication typically behaves - how long a dose takes to work and how long it lasts, from your own history. The forecast runs that pattern forward from today's actual doses: when you are likely to feel your best, and when effects may be wearing off. It is a projection from your own data, not a prediction of certainty, and it is never a medication instruction.

### Will Kampa ever tell me to change my medication?

No. Never. Kampa may surface an observation worth discussing - for example, that your afternoon doses seem to act more slowly than your morning ones - and help you prepare a summary for your neurologist. What to do about it is a decision for you and your doctor.

---

## Privacy and your data

### Where does my health data live?

On your iPhone and in your own private iCloud. Kampa has no servers. We cannot see your data - not because of a policy, but because of how the app is built. Nothing is sold, shared, or used for research without your explicit consent.

### Does Kampa use my data to train AI?

No. Optional AI-powered features (like plain-language explanations) send only derived summary statistics - never your raw health data, never your identity - and only if you opt in. Everything else runs entirely on your device.

### Can I get my data out?

Yes, always. Kampa exports your data as CSV files you can keep, inspect, or share. It is your data; export is free and always will be.

### What happens to my data if I stop using Kampa?

It stays in your iCloud and your Apple Health store, under your control. Deleting the app removes Kampa's copies; your Health data remains yours in Apple Health.

---

## Logging and voice

### How does voice logging work?

Say something like "Hey Siri, log coffee with Kampa" or "log a 20 minute meditation." Kampa reads back what it understood and asks you to confirm before saving anything. It was designed for days when typing is hard.

### Why can't I log a medication dose by voice through Kampa?

Apple allows apps to read medication doses from Apple Health but not to write them. Saying "log my meds" opens Apple Health's own medication screen instead. This is an Apple platform rule, and it exists for a good reason - one trusted list of record for something as important as medication.

---

## Glucose (CGM)

### Kampa shows a glucose panel. Do I need a glucose monitor?

No. Kampa works fully without one. If you choose to wear an over-the-counter continuous glucose sensor (such as Abbott Lingo or Dexcom Stelo - no prescription needed), Kampa can display your glucose curve time-aligned under your tremor chart, with doses and meals marked across both.

### Why would glucose matter for tremor or medication?

Levodopa is absorbed and reaches the brain through transport systems that food - especially protein and large meals - can compete with. Your glucose curve is an objective record of your body's meal response, which can help make sense of days when a dose seemed slow or weak. Kampa treats this as an area to observe honestly, not a promise.

### How do I connect my sensor?

Enable Apple Health sharing inside your sensor's own app (for example Lingo). Kampa reads glucose from Apple Health automatically - no separate pairing.

---

## Cost

### What does Kampa cost?

Nothing right now - Kampa is free to use. Sensing, charts, daily observations, logging, and data export are all included.

> Monetization (Kampa Plus, pricing, paid-only features) is deliberately left out for now - too soon to state publicly. See project notes before adding any of it back.

---

## About Kampa

### Who makes Kampa?

Kampa is built by Bhav Bhasin, a product builder who has spent 25+ years on large-scale technology and now builds independently, working closely with the Parkinson's community. Kampa began as an attempt to answer questions that existing tools would not: not "what happened," but "what actually affects me?"

### What does "Kampa" mean?

Kampa (कम्प) is Sanskrit for "tremor," from Kampavata - the term ancient Ayurvedic medicine used for what modern medicine calls Parkinson's disease. We chose a name that faces the condition honestly.

### I have essential tremor, not Parkinson's. Will Kampa work for me?

Parts of it. Kampa's lifestyle logging and correlation tools apply broadly, but the Watch's tremor sensing is tuned by Apple for Parkinson's resting tremor, and some features (like dose-response analysis) are specific to Parkinson's medication. We have not yet validated Kampa for essential tremor, and we won't claim it works until we have.

### Is Kampa a medical device?

No. Kampa is a personal wellness and symptom-tracking tool. It is not a medical device and does not provide medical advice, diagnosis, or treatment. Always consult a qualified healthcare professional about any medical condition.

### I found a bug / I have an idea. Where do I send it?

info@kampa.health - it lands with the person who builds the app, usually within a day or two. Ideas from people living with the condition have shaped most of what Kampa is.
