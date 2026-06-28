# LinkedIn Post #5 - Design principles (three pillars)

- **Status:** PUBLISHED
- **Published:** 2026-06-27 (Kampa Health page)
- **Live URL:** https://www.linkedin.com/posts/parkinsons-digitalhealth-productdesign-share-7476757937143836672-3nWe/
- **Target page:** Kampa Health
- **Theme:** umbrella / framing post on Kampa's three design pillars - Privacy · Apple closed-loop ecosystem · Ambient (low cognitive load). Part 1 of Bhav's 3-part series ("what Kampa believes" -> how it works -> what it feels like).
- **Altitude:** overview, NOT a privacy rerun. Privacy is one of three bullets here; the deep version is posted #2.
- **Folds in idea-bank angles:** closed-loop HealthKit + on-device intelligence.
- **Guardrail honored:** ambient pillar framed as "prefer passive, minimize manual logging," NOT "no logging" - explicitly names food, meditation, and meds (native HealthKit flow) as the taps that remain. Avoids the post-#3 overclaim.
- **Safety check:** founder voice; no personal-patient disclosure; privacy in ownership/control framing, not "we can't see it."
- **Format:** native LinkedIn text post. No markdown rendering on LinkedIn - the arrows + line breaks carry the structure. Plain text only; do NOT use the Unicode-bold trick (breaks screen readers, fails accessibility-sensitive audience).
- **Image (final pick):** ONE real app screenshot - the Day in Review / main screen with the passively-captured tremor chart + Daily Observations, no manual-entry UI in frame. See "Screenshot guidance" below.

---

## FINAL - native LinkedIn copy (paste as-is)

Most health apps are a stack of features. We started Kampa from the other end - with three principles we decided we wouldn't break, before we built a single screen.

For Parkinson's, those principles matter more than any one feature. The data is about as personal as data gets. The effort of tracking competes with the very symptoms you're trying to track. And the people using it deserve a tool that works without getting in the way.

Here's what Kampa is built on.

→ Privacy is the architecture, not a setting. Your health data is processed on your device and lives in your own private iCloud, under your account - not on our servers. It's the most personal data there is, and it stays yours.

→ Lean on the ecosystem you already wear. Kampa is built deep into Apple's closed loop - your Apple Watch senses tremor and movement passively through Apple's Movement Disorder API, while HealthKit already carries your sleep, heart rate, and workouts. Do a boxing session on your Watch and it's captured as a workout - we don't ask you to re-enter it. The intelligence then runs on-device, where your data already is.

→ Ambient. Minimize the asking. Parkinson's is exactly the wrong condition to hand someone a long daily form. So Kampa's default is to observe, not interrogate. A few things still need a tap - the food you eat, or your medications (logged through Apple's native Health flow) - but those are the light exceptions, not the price of admission. And we're working to remove even those - voice-driven logging is where we're headed.

None of these is something you bolt on later. They're decisions you make before the first screen exists - and they're why Kampa feels less like one more thing to manage, and more like something running quietly in the background of your day.

Kampa is for people living with Parkinson's, the people who care for them, and the researchers working on it. If that's you, I'd value your perspective.

Follow along here, or see more at kampa.health.

#Parkinsons #DigitalHealth #ProductDesign #AppleWatch #HealthKit #Privacy

---

## Screenshot guidance

**Primary (give me this one):** the Day in Review / main dashboard with the passively-captured **tremor chart + Daily Observations** visible, and **no manual-entry UI** in frame. Rationale: a framing post should *show* the principles, and this single screen demonstrates all three at once - on-device private data, sensed via Apple Watch, captured with zero tapping. It's the "running quietly in the background" line, made literal.

**Fallback (only if you'd rather a carousel):** 3 portrait screenshots, one per pillar -
1. in-app data inventory screen (record types + counts) -> Privacy
2. tremor/movement chart with Watch-sourced data -> Apple closed loop
3. clean Day in Review with food/meds chips lightly present -> Ambient

Carousels ("documents") tend to get the most reach, but they're more work and risk re-running post #2's privacy screen. One strong hero screenshot is the better effort/payoff trade for a framing post.

**Capture clean:** real data, no debug/X-ray overlays, tidy status bar, brand blue `#4A8CD6` (not Apple blue).
