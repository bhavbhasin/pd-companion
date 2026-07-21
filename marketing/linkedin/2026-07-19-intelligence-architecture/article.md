# LinkedIn ARTICLE - The intelligence architecture (propose / judge / narrate)

- **Status:** DRAFT
- **Source:** new long-form LinkedIn **Article**, cross-shared to Bhav's personal feed. Companion to `docs/intelligence-architecture.md`.
- **Target page:** Kampa Health (publish here), then cross-share to personal - same pattern as the design-principles article (~4k views on personal feed last time, Jul 16/design-principles cross-share).
- **Why article:** unlocks headings/bold + inline images (three real Insights-tab screenshots), which a native post can't carry cleanly.
- **⛔ CRITICAL GUARDRAIL - verified against the codebase, do not soften on edit:** there is **no runtime LLM** in Kampa today. Cards are hand-written Swift; the registry is human-curated. The "LLM proposes" and "LLM narrates" layers are **designed, not built**. This draft is written so the *only* thing claimed as live is the deterministic Judge (real, on-device, visible in the screenshots) - the AI layers are framed as a **decision about sequencing**, never as something currently running. Do not edit this into present-tense "the AI suggests..." copy.
- **Guardrails carried over:** founder voice, no personal-patient disclosure; never overclaim the "Try an experiment" button as a live end-to-end feature (experiment loop is unbuilt) - it's shown, not narrated as functional.
- **⛔ Jul 19 revision - depersonalized per `DesignReview-2026-07-19.md` §6:** the caffeine story is real product data (from `intelligence-architecture.md`) but was first drafted in first person ("I drink coffee near my medication doses," "on my own data") - that's disclosure-adjacent and collides with the non-negotiable never-disclose-PD rule. Rewritten to third person ("a user's data") below. Do not revert to "I/my" on this section specifically, even though the rest of the article is legitimately first-person builder voice.
- **✅ RESOLVED (Jul 19) - insight-2.jpg keeps the "Try an experiment" button.** Bhav's call: keep it visible, add a parenthetical "(more on this later)" in the body copy signaling a dedicated future post on the experiment feature, rather than dropping/cropping the image. This does NOT resolve the underlying product risk from `DesignReview-2026-07-19.md` §5.4 (silent data loss on reload) - that's still Bhav's to fix in the app on its own timeline. It only resolves how the *post* handles it: the copy now sets expectations ("more on this later") instead of implying the button is a finished feature.
- **✅ RESOLVED (Jul 19) - cover image.** `screenshot-tremor.jpeg` was already used as the cover on the design-principles post (Jun 27) - reusing it here would repeat a hero across two posts. Replaced with a purpose-built diagram, `cover-diagram.png` (1280x720), rendered from `cover-diagram.html` via headless Chrome (brand blue `#4A8CD6`, Geist, dark theme matching the website + the in-app screenshots). Visualizes the Propose → Judge → Narrate flow from `intelligence-architecture.md`'s mermaid diagram, self-explanatory without needing the article body.
  **v2 (Jul 19):** dropped the top headline ("the one job we decided AI would never do" - redundant with the article title) and the bottom thesis line (redundant with the Judge card's own description); centered "Insight Architecture" as the image title and enlarged the three layer cards into the freed space for legibility at feed size. Article title therefore KEEPS "The One Job We Decided AI Would Never Do" - the two surfaces no longer repeat. Regenerate via:
  ```
  "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" --headless --disable-gpu --hide-scrollbars \
    --allow-file-access-from-files --window-size=1280,720 \
    --screenshot="cover-diagram.png" "file://.../cover-diagram.html"
  ```
- **Editor note:** LinkedIn article editor does not accept pasted markdown - paste plain text, apply Heading 2 / Bold / Hyperlink via toolbar. Hashtags go in the SHARE commentary, not the article body.
- **Jul 19 revision - added technical texture + a second Propose example (Bhav's request).** Named the two reusable building blocks (primitive + registry entry) with two concrete primitives - windowed-effect and Kaplan-Meier survival - for credibility with a clinical/technical reader. Added Tai Chi + boxing as a second example of the same windowed-effect primitive running on other logged activities - framed as **already-wired registry lines waiting on data**, not as unbuilt AI-proposed hypotheses (the doc's "Scaling" section confirms these ship as registry lines day one; keeps the no-runtime-LLM guardrail intact).

## Title

**RECOMMENDED TITLE:** The One Job We Decided AI Would Never Do
- SEO title (carries "Parkinson's" + "AI" keywords the display title omits): `Kampa's Insight Architecture: The One Job We Decided AI Would Never Do`
- Article URL slug: `kampa-ai-never-the-judge`

Titles considered: "We Let AI Imagine. We Never Let It Judge." (strong but reads present-tense - risks implying the propose/narrate layers are live) · "Built the Judge Before the Talker" · "How Kampa Decides an Insight Is Real" · "Tracking Isn't the Product. The Insight Is."

---

## Article body (labels map to editor toolbar)

**[TITLE]** The One Job We Decided AI Would Never Do  _(recommended title)_

Kampa tracks a lot: tremor and dyskinesia straight from the Apple Watch, sleep, meals, medication timing, mood, walking speed. But tracking, by itself, is worth almost nothing. A chart that shows you *what happened* is a diary. The thing worth building - the actual product - is what happened *and what it means*: which of these signals are real, which are coincidence, and which one you should bring to your neurologist. Monitoring without an insight you can act on is just a longer way of feeling the same thing you already felt.

That's the hard part. And it's exactly the part where it's tempting to reach for AI and get it wrong.

**[H2]** The trap

There were two tempting ways to generate those insights, and both are wrong.

**[bulleted list]**
- **Hand an LLM the data and ask what it sees.** LLMs are not calculators. They pattern-match on text - they don't *compute* a correlation or a survival curve. Ask one to find a pattern in someone's tremor data and it will oblige, including patterns that aren't there. For a health app, that's the worst possible failure mode.
- **Write a fixed statistical engine and stop.** Rigorous, but blind. It can only ever test what one person thought to hand-code in advance.

**[Body - continue]**

The resolution wasn't to pick a side. It was to split the job into three layers, and wall the AI off from the one part it's genuinely dangerous at: deciding what's true.

**[H2]** Propose. Judge. Narrate.

An AI **proposes** what's worth testing - it has breadth, it knows the literature, it can suggest a pairing a developer wouldn't think of. A deterministic engine **judges** whether that pattern actually holds in your own data - effect size, sample size, significance, and a guard against confounding, all running on-device. And only *after* something survives judgment does an AI **narrate** it back to you in plain language.

The judge isn't a bespoke script per question. It's built from two reusable pieces. A **primitive** is a statistical method that doesn't know or care which variable it's fed - *windowed-effect* asks whether a signal moves in the hours after an event, whether that event is a cup of coffee, a workout, or a meal; a *Kaplan-Meier survival curve* asks how long something typically lasts before it ends, which is how a dose's ON-time before wearing off gets estimated. A **registry entry** just wires one variable pair to one primitive - new question, same math, one line, no new statistics.

The rule that makes the whole thing safe: **the AI is the imagination and the voice. It is never the judge.** Only deterministic statistics get to promote a hypothesis to something you actually see on your screen.

**[IMAGE -> website/images/insight-1.jpg]** Kampa's Insights tab - several findings, each tagged Hypothesis / For your neurologist / Result, each carrying an honest confidence level (Emerging, Moderate, Strong)

**[H2]** What "judged" looks like

Open one of these cards and the judgment is visible, not just claimed. Here, walking is associated with a ~20% drop in tremor over the following two hours - but the card calls it a hypothesis, not a fact, because that's what the statistics support: an association worth testing, not proof. (Notice the "Try an experiment" button - more on this later.)

**[IMAGE -> website/images/insight-2.jpg]** An insight expanded - tremor trend after walking, framed explicitly as "an association in your own data, a hypothesis to test, not proof"

Compare that to this one: an afternoon dose that takes 68 minutes to kick in versus 40 in the morning, from 146 scored doses over 45 days. Enough evidence that the card is tagged **for your neurologist**, at **Strong** confidence - worth bringing to an actual appointment, not just interesting.

**[IMAGE -> website/images/insight-3.jpg]** "Your afternoon dose works slower" - Strong confidence, tagged for your neurologist, with the morning/pre-lunch/afternoon dose-response curves

That gap between "Moderate, worth watching" and "Strong, worth your doctor's time" isn't a style choice. It's the judge doing its job - and it's why the same engine can say **"no clear effect yet"** on a hypothesis just as easily as it says "strong." A card that only ever confirms things isn't a judge, it's a cheerleader.

The same windowed-effect primitive already runs on more than caffeine and walking. Does Tai Chi ease tremor? Does boxing - a common Parkinson's exercise? Each is one more registry line over the identical math. That list is curated today, drawn from the activities that come up most in Parkinson's, and extending it is a line of configuration rather than new statistics. What decides whether a card actually appears is enough of your own sessions logged. Until then, the honest state is silence, not a guess.

**[H2]** Proof the judge is disciplined

The clearest evidence the judge is real came from a mistake it caught on a real account's data. Early on, a caffeine card read confidently: *"Caffeine eases your tremor - Strong - 32% lower."* Plausible on its face - caffeine has a real pharmacological path to tremor. Almost certainly wrong: coffee tends to get taken near a medication dose, so the two-hour window after coffee was really riding the *dose's* effect, and a confounder-blind engine handed the credit to the coffee.

The fix was a guard that drops any measurement window shadowed by a nearby dose before judging anything else. Once it ran, the same card, on the same data, flipped: **"Caffeine: no clear tremor effect yet - Emerging."** That flip - from a confident, wrong "Strong" to an honest "not yet" - is the whole architecture working as intended. A system that can only ever get more confident isn't rigorous. One that's willing to take a claim back is.

**[H2]** Built in this order, on purpose

Here's the honest part. Today, the propose and narrate layers - the AI imagination and the AI voice - aren't live yet. The registry of questions is human-curated. The words on these cards are hand-written. What *is* live, on-device, right now, is the judge: the layer that decides whether a claim about your medication or your symptoms is allowed to exist at all.

That's not an accident of what got built first - it's the sequencing that made sense. The part that can't be wrong gets built and hardened before the parts that make it more convenient. The imagination and the voice are next. The judge came first because it's the layer everything else has to answer to.

**[Body - closing]**

None of this leaves your device to happen. The analysis runs locally, on your phone, and nothing about it is sent to us - Kampa has no server collecting your symptoms. If the narration layer lands later, the only things that would ever leave, and only if you opt in, are a menu of variable names and a validated summary. Never raw tremor readings.

Tracking alone gives you a diary. This is what makes it a tool.

Kampa is for people living with Parkinson's, the people who care for them, and the researchers working on it. If that's you, we'd value your take. Follow along here, or see more at kampa.health (hyperlink -> https://kampa.health).

---

## Images

| Slot                          | File                                                   | Note                                                                                                                                                          |
| ----------------------------- | ------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Cover banner                  | `cover-diagram.png` (1280x720, in this article folder) | purpose-built Propose→Judge→Narrate diagram, brand blue + Geist + dark theme; avoids repeating `screenshot-tremor.jpeg` (already the design-principles cover) |
| Insights list                 | `website/images/insight-1.jpg` (611x1326)              | already live on the website (Insights section); confidence-tagged card list                                                                                   |
| Walking hypothesis (expanded) | `website/images/insight-2.jpg` (611x1326)              | "hypothesis, not proof" framing; keeps the "Try an experiment" button - copy adds "(more on this later)" rather than dropping/cropping the image              |
| Afternoon dose (expanded)     | `website/images/insight-3.jpg` (611x1326)              | Strong / for-your-neurologist card, the clinical-value beat                                                                                                   |

---

## Share commentary (hashtags live here, NOT in article body)

**Kampa-page share blurb:**
> Tracking tremor is easy. Knowing which pattern in that data is real - and which one you should actually bring to your neurologist - is the hard part. Here's the architecture decision behind how Kampa tells the difference, and the one job we decided AI would never be allowed to do. #Parkinsons #HealthTech  #AI #ProductArchitecture #AppleWatch

**Personal cross-share (first person):**
> A monitoring app that just shows you a chart isn't a product, it's a diary. The value is in the insight you can act on - and that's the part I was most careful about getting right with Kampa. Wrote up the architecture decision behind it.
>
> #Parkinsons #AI #ProductDesign #BuildingInPublic #Kampa
