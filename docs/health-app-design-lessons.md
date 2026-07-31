# What Top Health Apps Get Right - Lessons for Kampa

*Researched Jul 30, 2026. Sources at bottom. Each section: what they do, why it works, what Kampa should take (or deliberately reject).*

---

## 1. MyFitnessPal - the habit-loop giant

**What works**: Logging is woven into daily rhythm (meal times = natural triggers). Streaks, progress rings, adaptive goals that move with the user. Community feedback loops. Their stated retention philosophy: "if users succeed, we succeed" - retention via genuine outcomes, not dark patterns.

**What fails**: Navigation bloat after 15 years of feature accretion; manual logging fatigue is the #1 churn driver across the whole category (53% of health apps uninstalled within 30 days; 32% within a week).

**For Kampa**:
- Kampa's passive capture (Movement Disorder API, HealthKit) already sidesteps the category's biggest killer. This is the moat - never add a feature that makes passive data depend on manual input.
- Streaks are wrong for PD (a bad tremor day breaking a streak is punishment for being sick). If gamification ever comes, reward *data coverage* ("14 days of dose logging → forecast unlocked"), not consecutive-day compliance. This matches freemium-by-capability.

## 2. Bevel - the closest analog to Kampa's position

Bevel is what Kampa is architecturally: a HealthKit-native layer that makes Apple's own data legible, no proprietary hardware.

**What works**:
- "Way easier to understand, clean look" is the #1 review theme - it wins on *legibility of existing data*, not new data.
- Privacy as a stated feature: HealthKit opt-in, Sign in with Apple, "we don't sell your health data" said plainly.
- Free core tier (late 2025) with a public promise that free features stay free - trust move.
- Solo-dev responsiveness to user requests is itself cited in reviews as a reason to stay.

**For Kampa**:
- Validates the whole thesis: users pay for *interpretation of data they already generate*. Kampa is Bevel-for-PD.
- Say the privacy position in-app in plain words, not just in policy. "Your tremor data never leaves your device" is a Bevel-grade trust line.
- The tester relationship (John, Harpal) is a feature - Bevel reviews prove responsiveness compounds into retention.

## 3. January AI - prediction as the hero feature

**What works**: Flipped the category from *measurement* (CGM required) to *prediction* (no hardware). "See the impact before you take a bite." Also: one-tap medical-records import to kill onboarding data entry, and an AI coach ("Jan") with persistent memory of the user's history.

**What to be careful of**: January's predictions are population-model guesses dressed as personal insight. Kampa's engine-judges architecture (only the engine claims "real") is the honest version of this.

**For Kampa**:
- The forecast (day-ahead panel, dose-influence envelope) is Kampa's "January moment" - prediction without new hardware is the demo-able magic. Lead marketing with it.
- Their EHR one-tap import is the same instinct as Kampa's 120-day HealthKit backfill: arrive with history, never start at zero. Kampa already does this for gait (Day-1 insight); extend the principle everywhere.

## 4. Whoop vs Oura - two opposite score philosophies, both work

**Whoop**: one number (Recovery 0-100, green/yellow/red), data-dense, built around a single question - "are you ready to train today?" Key pattern: **there is no separate coaching tab; the score IS the coaching.** Also: auto-detects workouts after a learning period - zero-friction capture. Daily Outlook (morning briefing) + Day in Review (evening recap) bookend the day.

**Oura**: three gentle scores, calm presentation, readiness framed as *capacity for your day* not training license. Wins with people who find Whoop's intensity stressful. Flags illness before you feel it (temperature trend) - early-warning as the emotional hook.

**Whoop's documented weakness**: written copy. "Multiple days below strain targets will promote recovery" - users can't tell if that's good or bad. Visual design excellent, sentence design neglected.

**For Kampa**:
- Kampa is temperamentally Oura (calm, capacity-framed) with Whoop's single-question discipline. Kampa's question: **"what should I expect from my body today?"** Every surface should answer it or support it.
- Kampa already has the Whoop bookends (Day-ahead forecast = Daily Outlook; Day in Review panel = theirs, same name). The structure is validated; the gap is that Kampa's aren't yet the *ritual* front door.
- Card copy is a first-class engineering surface. The Jul 29 copy bugs and the #335 stale-dose vocab item are Whoop's exact failure mode. Rule: every sentence must survive "does the reader know what to DO?"
- A composite "PD score" is tempting and wrong for now - tremor/dyskinesia/sleep/dose coverage don't collapse honestly into one number, and an unvalidated score is a January-style guess. Revisit only if a validated composite emerges from the engine.

## 5. Bearable - the direct category neighbor (chronic-illness tracking)

900K users, 4.8 stars, the default recommendation in chronic-illness communities.

**What works**: tracks enormous variable counts without visual clutter; deep customization (users define their own factors); fast logging flows continuously reinvested in.

**What fails (category-wide benchmark finding, 2026)**: the **input-output inversion**. Trackers pour effort into data entry and leave the *output* layer at launch quality. Only 34% of users ever share data with their doctor despite 46% saying the app changed their health management. Nobody has built the output "structured around the question a GP asks at a follow-up appointment." Users bring screenshots to appointments.

**For Kampa**: this is the single biggest finding of the research.
- **The clinician handoff is an unclaimed competitive vector in the entire category.** Kampa's planned chart→PDF embed is exactly this - it should be elevated from a backlog item to a headline feature: a one-page "neurologist visit summary" (tremor trend, dose coverage, wearing-off pattern since last visit) answering what the neurologist actually asks in a 10-minute slot.
- Kampa's insight cards are already output-first - the inversion is the trap Kampa was built to avoid. Keep the asymmetry: every hour on input UX must be matched on output UX.
- Bearable's data-integrity bugs (timestamp corruption unfixed since 2023) show that in this category **trust in the record is the product**. The forecast cold-start bug (swallowed empty HealthKit read rendered as fact) is the same class of sin - it stays worth fixing for this reason, not just polish.

## 6. Zoe - making judgment actionable, not judgmental

**What works**: never just scores a meal "bad" - always offers the tweak ("swap X for Y") and alternatives with better grades. Multiple entry methods (photo, barcode, database, AI-from-title). Behavior loop: log → feedback → adjustment.

**Documented failure**: hiding the data behind simple good/bad labels *reduced user trust*. Engaged users demanded the breakdown underneath.

**For Kampa**:
- Zoe's trust failure is direct evidence for Kampa's facts-over-verdict redesign (Jul 21). Users of serious health apps want the evidence under the claim. Kampa is on the right side of this; don't backslide toward verdict-only cards.
- Zoe's "tweak, don't judge" maps to Kampa's lever framing: a card that says "coverage gap 8.3h/day" should always sit next to the lever ("a dose near 3pm would cover the longest gap") - within the med-change safety line (describe the pattern, never instruct dosing).

## 7. Gentler Streak - designing for bodies that have bad days

Apple Design Award winner (Social Impact). A fitness tracker whose core innovation is emotional: you can set yourself *sick, injured, or on a break* and the app adapts instead of shaming. Soft, warm visual language and copy to match. "A compass, not a drill sergeant."

**For Kampa**: the most philosophically aligned app in the set. PD guarantees bad days; progression guarantees worse ones.
- Kampa must never present a worsening trend as failure. Valence language should attach to *actionable* things (dose coverage, sleep) and stay neutral-descriptive on the disease itself.
- "Design for real-life scenarios" = Kampa equivalents: travel days, med changes, sick days, the un-medicated PD user (already first-class per the medication-cards design). An explicit "medication change in progress" state that adjusts engine expectations is a Gentler-Streak-grade feature.
- Tone is award-winning territory in health apps. Kampa's matter-of-fact-but-warm card voice is a differentiator vs StrivePD's clinical journal feel - keep investing in it.

## 8. Category-wide patterns worth stealing

**Onboarding**: every field added at onboarding measurably increases drop-off. Best practice: one question per screen, skippable everything, get to a "first win" immediately. Kampa's version of the first win is uniquely strong - *backfilled history means a real insight on Day 1* (gait already does this). Make "time-to-first-true-insight" the onboarding metric.

**AI chat coaches** (Whoop Coach, January's Jan): the emerging table-stakes pattern is chat + suggested prompts + memory of user history. Kampa's architecture (LLM proposes/narrates, engine judges) is *better* positioned than any of them for this - every competitor's coach can hallucinate; Kampa's narrator is walled off from the claim of truth. When the LLM layer ships, suggested prompts ("why was yesterday afternoon rough?") beat an empty chat box.

**Ritual bookends**: morning "what to expect" + evening "what happened" is now the dominant engagement structure (Whoop, Oura, Bevel all converged on it). Retention comes from the ritual, not from notification volume. Kampa has both halves built; the play is making them the two moments Kampa is *opened*, e.g. a morning forecast widget/complication and an evening Day-in-Review that's worth 30 seconds.

**Home screen widgets / complications**: Gentler Streak and Bevel both push health state to the home screen. For a PD user with tremor, a glanceable widget (today's forecast band, next-dose coverage) is an accessibility feature, not a growth hack - zero taps is the ultimate low-cognitive-burden interface.

## 9. What Kampa should NOT copy

- **Streak mechanics** - punish sick days (see §1).
- **Composite single score** - dishonest without validation (see §4).
- **Verdict-only simplification** - Zoe's measured trust failure (see §6).
- **Community/social feeds** - MyFitnessPal-scale moderation burden, privacy surface, and PD progression comparison between patients is emotionally hazardous. Off the table for a solo-dev app.
- **Engagement-bait notifications** - the retention data says ritual value beats push volume; StrivePD's daily-engagement pressure is the competitor's problem to have.

## Top 3 actions (recommendation)

1. **Neurologist visit summary (PDF)** - the category's proven unclaimed gap; Kampa's chart→PDF item, promoted to headline feature.
2. **Ritual bookends as front door** - morning forecast widget/complication + evening Day-in-Review polish; the validated engagement structure with zero new data science.
3. **Copy audit as a real pass** - Whoop-grade visual + Whoop-grade sentence failure is the category norm; every card sentence tested against "does the reader know what to do?"

---

**Sources**: [MyFitnessPal retention](https://www.trypropel.ai/resources/myfitnesspal-customer-retention-strategy) · [Bevel review](https://www.healthappinsider.com/en/reviews/bevel-review) · [Bevel engineer's take](https://www.autonomous.ai/ourblog/bevel-app-review) · [January AI launch](https://insider.fitt.co/press-release/january-ai-health-app-combines-one-tap-medical-records-cgm-free-predictive-glucose-ai-and-wearable-data/) · [Whoop vs Oura](https://healnourishgrow.com/whoop-vs-oura/) · [Whoop design breakdown](https://www.925studios.co/blog/whoop-design-breakdown) · [Whoop Coach](https://www.whoop.com/us/en/thelocker/introducing-whoop-coach-powered-by-openai/) · [Symptom tracker UX benchmarking 2026](https://interface-design.co.uk/blog/symptom-tracking-apps-in-2026-the-physician-problem-no-one-is-solving/) · [Bearable](https://bearable.app/) · [Zoe engagement lessons](https://healthmattersandme.substack.com/p/lessons-on-design-for-high-engagement) · [Gentler Streak - Behind the Design](https://developer.apple.com/news/?id=3m0ht22s) · [Health app retention/Hook model](https://productgrowth.in/insights/healthtech/health-app-retention-guide/) · [Onboarding friction](https://productgrowth.in/insights/healthtech/patient-onboarding/)
