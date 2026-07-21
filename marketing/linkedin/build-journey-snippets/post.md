# Build Journey — LinkedIn snippets (Fable-drafted Jul 9 2026)

Source: ParkinsonsProject.md → Build Journey section. Guardrails held: no founder-PD disclosure, spaced hyphens, no competitor names, no invented numbers.

**Status:** A + C = ready. **B = HOLD** — overlaps posted post #3 (stats-not-LLM) and the queued intelligence-architecture article; fold B's "brilliant narrator, dangerous statistician" line into that article instead, or differentiate before publishing.

---

## A — Auditing API floors before lowering them  (READY)

**Hooks:**
1. My app's minimum OS version was set by nobody. It nearly cost me every tester I had.
2. An unexamined Xcode default quietly shrank my app's audience to near zero. The fix was not the obvious one.
3. "Just lower the minimum iOS version" broke the build. That failure taught me more than the fix did.

**Body:**
My app's minimum OS version was set by nobody. It nearly cost me every tester I had.

I'm building Kampa, an iOS + watchOS app that tracks Parkinson's symptoms. When I created the project, Xcode defaulted the deployment target - the minimum OS version a device needs to run the app - to iOS 26.4 and watchOS 26.4. I never examined it. That single default excluded almost every tester I had lined up, and worse, the target audience for a Parkinson's app skews older - people who keep their devices longer.

The naive fix: "just lower everything to iOS 18 / watchOS 11." Wrong. It broke the build. The HealthKit Medications API - the Apple framework that powers the app's flagship medication-timing feature - only exists on iOS 26. Lowering the iPhone floor didn't broaden the audience; it deleted the core feature.

So I audited it properly: which feature depends on which API, and what floor does each API actually require? That surfaced an asymmetry the blanket fix missed. The iPhone has to stay on iOS 26. But the Watch - where the tremor data actually originates - drops cleanly to watchOS 10, pulling in the older Apple Watches this audience actually owns.

Lesson: before you lower an API floor, audit which features depend on it. And never trust a default you didn't choose - it can silently shrink your audience to near zero.

#iOSDevelopment #BuildInPublic #HealthTech #watchOS

---

## B — Why we didn't just hand the data to an LLM  (HOLD — see status note)

**Hooks:**
1. An LLM is a brilliant narrator and a dangerous statistician. In a health app, that distinction is the whole architecture.
2. The obvious move in 2026: dump all your health data into an LLM and ask it to find patterns. For a health app, that's the dangerous move.
3. I'm building an AI health app, and the most important decision was what the AI is not allowed to do.

**Body:**
An LLM is a brilliant narrator and a dangerous statistician. In a health app, that distinction is the whole architecture.

The obvious move in 2026 for Kampa, my Parkinson's tracking app: hand all the health data to an LLM and ask it to find the patterns. I didn't, for concrete reasons.

LLMs hallucinate correlations - they'll confidently assert relationships that aren't statistically real. One patient generating many variables means "patterns" will appear by pure chance unless something enforces real thresholds. And confounding is everywhere: a coffee logged right after a medication dose looks like the coffee eased the tremor, when it was the medication. An LLM eyeballing the data would credit the coffee. Finally, no auditability - you can't show a patient why an insight appeared.

So Kampa's correlation engine is deterministic statistics - plain math that gives the same answer every time. A pattern only counts as real once it clears actual thresholds: enough data, a real effect size, and it survives a significance test.

The LLM's job comes after: explain a validated result in plain language. It never gets to find the correlation itself.

That's the lesson. Let the LLM narrate - it's genuinely great at that. But in a health app, only deterministic math earns the right to claim a correlation is real.

#AI #HealthTech #LLM #ProductEngineering #BuildInPublic

---

## C — What a platform lets you read is not what it lets you write  (READY)

**Hooks:**
1. I built hands-free voice logging - speak a sentence, confirm, done. Then I hit the feature where the platform said no.
2. What a platform lets you read is not what it lets you write. I learned that shipping voice logging on iOS.
3. The demo said "log anything by voice." The API said otherwise.

**Body:**
I built hands-free voice logging - speak a sentence, confirm, done. Then I hit the feature where the platform said no.

For Kampa, my Parkinson's tracking app, low-effort input isn't a nicety - it's the product. So I built voice logging for food and meditation using App Intents, Apple's framework for exposing app actions to voice and the system. Speak a sentence, confirm, logged.

Medication seemed like the obvious next one. It wasn't possible - and the reason is worth internalizing. Apple's HealthKit Medications API is read-only to third-party apps: my app can read every dose a user logs, but only Apple Health itself is allowed to write one. Same data type, asymmetric access. Reading and writing are two different permissions, and the platform decides both.

So the app shipped what the platform actually allows: voice logging for food and meditation, and for medication, a deep link - a tap that jumps straight into Apple Health's own logging screen. Not the demo I'd imagined, but honest, and it works.

The lesson generalizes past iOS. When you scope a feature against a platform API, audit the write surface, not just the read surface - what you can pull out tells you nothing about what you're allowed to put in. Design around what the platform actually permits, not the demo someone else showed.

#iOSDevelopment #ProductEngineering #HealthTech #BuildInPublic
