# Ask Kampa - deployment notes

An LLM help chat for kampa.health, grounded strictly in the FAQ. Three files:

- `ask-kampa-widget.html` - standalone prototype of the chat UI (dark theme, brand blue #4A8CD6). Open it in a browser to see the design; on the real site, copy the `.ask-kampa` block, styles, and script into your page (or an `/ask.html`).
- `netlify/functions/ask.js` - the serverless proxy. Calls the Anthropic API (Haiku 4.5) with the FAQ as its only knowledge, via prompt caching so repeat calls cost fractions of a cent.
- You must also copy `Kampa-FAQ.md` into `netlify/functions/faq-knowledge.md` (the function reads it at cold start). Strip the [SHIP-GATED] entries until those features launch - the bot must not describe unshipped features.

## Deploy (3 steps)

1. Copy `netlify/functions/ask.js` and `faq-knowledge.md` into your site repo under `netlify/functions/`.
2. In Netlify: Site settings -> Environment variables -> add `ANTHROPIC_API_KEY` (create a dedicated key in the Anthropic console so it can be rotated/limited independently).
3. Add the widget markup to the site, push to main. Netlify builds functions automatically - no config needed beyond the existing `netlify.toml`.

## Cost & abuse control

- Haiku 4.5 at ~400 max output tokens with a cached system prompt: roughly $0.001-0.003 per question. Even 1,000 questions/month is a few dollars.
- Input capped at 1,000 chars, history capped at 3 exchanges - bounds each call.
- Set a monthly spend limit on the API key in the Anthropic console (belt and suspenders).
- CORS is locked to https://kampa.health in ask.js. If you test on a Netlify preview URL, temporarily add that origin.
- If the widget gets hammered by bots, enable Netlify's rate limiting on the function path, or add a simple hidden honeypot field.

## Privacy policy addition (one paragraph)

> Ask Kampa: questions typed into the Ask Kampa help chat are processed by our AI provider (Anthropic) to generate an answer. Please do not include personal health information in your questions. Chat questions are not linked to your Kampa app data - the app's health data never leaves your device and is not accessible to the website or the chat.

## The in-app version (later, via Claude Code in the app repo)

- SwiftUI chat screen (Help tab or "?" toolbar) that POSTs to the same endpoint - keeps the API key off-device, one knowledge base to maintain.
- Same system prompt; add an `x-kampa-app: ios` header if you want to segment metrics.
- When Insights/Experiments ship, extend the knowledge file - the in-app bot is most valuable exactly there ("why did my card disappear?", "what does emerging mean?").
- Keep it strictly separate from the future ask-your-data voice feature: Ask Kampa knows the *product*; it must never see or claim to see the user's health data. Two different trust boundaries, two different features - blur them and both lose credibility.

## Voice support

- The widget is voice-enabled where the browser allows: a mic button (Web Speech API) captures the question, and a "read answers aloud" toggle speaks responses (speechSynthesis). Voice input auto-enables spoken output.
- Feature-detected: the mic hides on browsers without SpeechRecognition (some Safari versions); text always works.
- Privacy note: Chrome processes speech recognition on Google servers - the footer discloses "voice questions use your browser's speech service."
- Voice questions send `mode: "voice"`; the function then asks the model for a 2-3 sentence answer (hint lives in the user turn so the cached system prompt stays warm).
- The in-app version should be voice-FIRST and fully on-device for audio: SFSpeechRecognizer in (same framework as voice logging), AVSpeechSynthesizer out (same component planned for ask-your-data). Only the transcribed text question goes to the endpoint. ~1-2 days in the repo; add NSMicrophoneUsageDescription + NSSpeechRecognitionUsageDescription.

## Guardrails already in the system prompt

- No medical advice; hard refusal on medication questions with warm redirect to the doctor.
- Answers only from the FAQ; unknown -> "not sure" + info@kampa.health.
- Never repeats personal health details a user types in.
- Builder-voice only about the founder; no speculation about anyone's health.
