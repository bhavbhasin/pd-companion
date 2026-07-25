# LinkedIn POST - The five features I deleted (validation rigor)

- **Status:** DRAFT
- **Type:** native short-form post (not an Article) for Bhav's personal feed; builder-rigor angle that doubles as a hiring signal (methodological credibility for AI-lab health teams).
- **Source:** the Jul 22 forecast-composition validation sweep - five candidate forecast levers (time-of-day rhythm, sleep→next-day, exercise, meal timing, day-to-day persistence) all validated NO-GO/WEAK on real tester data before any production code.
- **⛔ GUARDRAILS (do not soften on edit):**
  - **No PD self-disclosure.** Framed entirely as the app's method + users/testers - never first-person patient, never "my tremor / my data." Non-negotiable.
  - **No identifying tester health details.** Kept abstract ("real data," "a single person," "n-of-1"). No named testers, no personal figures.
  - **Must not read as defeat.** The validated core (personal baseline + medication response) IS the product; the five failures are the quality bar working, not the app coming up empty.
- **Voice:** Bhav's - spaced hyphens (not em dashes), no "I'm thrilled to share," no emoji bullets, no rule-of-three. Risk/trust framing ties to his PayPal/Uber background.
- **Hashtags** (put in the post, not a comment for native): #Parkinsons #DigitalHealth #ProductManagement #MachineLearning

---

## Post

This week I deleted five features. It was the most useful week I've had on the app I'm building.

I'm building a tool that helps people with Parkinson's understand their day - when symptoms tend to rise, what moves them, what doesn't. The tempting way to build that is to hunt for correlations and surface them as "insights." Sleep and symptoms. Exercise and symptoms. Time of day. It's easy, and it demos beautifully.

So before writing a line of production code, I tested five of those against real data. Sleep quality vs. the next day. Exercise. Meal timing. A daily rhythm. Whether a rough morning predicts a rough afternoon.

All five failed.

The one that stuck with me was exercise. The raw numbers looked like a clean story - symptoms rose after a workout. Then I controlled for medication timing, and the effect collapsed to nothing. The "exercise signal" was really medication wearing off around the same time people tended to move. A correlation in a costume.

Twenty years in risk and trust taught me that the dangerous number is the one that looks clean. There's a whole category of health apps that would have shipped all five of these as insights. At the level of a single person, most lifestyle-to-symptom correlations are noise - and an honest app should be willing to look, find nothing it would stake a claim on, and stay quiet.

So the app got simpler this week, not fancier. What survived was the core - a personal baseline, and how medication actually moves it. Everything else had to earn its place, and didn't. That feels like the right kind of restraint for something people might make real decisions around.

#Parkinsons #DigitalHealth #ProductManagement #MachineLearning
