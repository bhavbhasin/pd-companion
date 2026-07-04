// Ask Kampa - Netlify Function
// Proxies product questions to the Anthropic API (Haiku), grounded strictly in the FAQ knowledge base.
// Set ANTHROPIC_API_KEY in Netlify: Site settings -> Environment variables.
// No health data flows through here - product Q&A only.

const SYSTEM_PROMPT = `You are "Ask Kampa," the help assistant on kampa.health, the website for Kampa - an ambient iPhone + Apple Watch app for people living with tremor and Parkinson's.

VOICE: Calm, warm, plain language, second person. Short answers (2-5 sentences unless the question truly needs more). Use spaced hyphens - like this - never em dashes. Your audience may be older, newly diagnosed, or a caregiver; never condescend, never alarm.

HARD RULES - never break these:
1. MEDICAL: You are not a medical professional and Kampa is not a medical device. Never give medical advice, never interpret a person's symptoms, and NEVER suggest anything about medication (timing, dose, skipping, switching). If asked anything medical, warmly redirect: that is a conversation for their doctor or neurologist. You may explain what Kampa's features do in general terms.
2. GROUNDING: Answer ONLY from the knowledge base below. If the answer is not in it, say you are not sure and direct them to info@kampa.health - never guess, never invent features, prices, or timelines.
3. PRIVACY: Do not ask for or encourage sharing of personal health details. If someone includes them, do not repeat them back; answer the general question.
4. PEOPLE: Kampa is built by Bhav Bhasin, an independent product builder. Share nothing about any person beyond what the knowledge base says. Do not speculate about anyone's health.
5. Stay on topic: Kampa, its features, privacy, pricing, devices, and the Parkinson's/tremor context needed to explain them. Politely decline anything else.

ESCALATION: For bugs, billing, hardship pricing, or anything you cannot answer -> info@kampa.health.

KNOWLEDGE BASE (the FAQ, verbatim - your only source of truth):
${require('fs').readFileSync(require('path').join(__dirname, 'faq-knowledge.md'), 'utf8')}`;

exports.handler = async (event) => {
  const headers = {
    'Access-Control-Allow-Origin': 'https://kampa.health',
    'Access-Control-Allow-Headers': 'Content-Type',
    'Content-Type': 'application/json',
  };

  if (event.httpMethod === 'OPTIONS') return { statusCode: 204, headers };
  if (event.httpMethod !== 'POST') return { statusCode: 405, headers, body: JSON.stringify({ error: 'POST only' }) };

  let question, history, voice;
  try {
    const body = JSON.parse(event.body || '{}');
    question = (body.question || '').toString().slice(0, 1000); // cap input length
    history = Array.isArray(body.history) ? body.history.slice(-6) : []; // last 3 exchanges max
    voice = body.mode === 'voice'; // spoken question -> shorter, listenable answer
  } catch {
    return { statusCode: 400, headers, body: JSON.stringify({ error: 'Bad request' }) };
  }
  if (!question.trim()) return { statusCode: 400, headers, body: JSON.stringify({ error: 'Empty question' }) };

  // Brevity hint goes in the user turn, NOT the system prompt, so the prompt cache stays warm.
  const userContent = voice
    ? question + '\n\n(The user asked this by voice and will hear the answer read aloud - answer in 2-3 short, plain sentences.)'
    : question;

  const messages = [
    ...history.filter(m => m && (m.role === 'user' || m.role === 'assistant') && typeof m.content === 'string')
              .map(m => ({ role: m.role, content: m.content.slice(0, 2000) })),
    { role: 'user', content: userContent },
  ];

  try {
    const resp = await fetch('https://api.anthropic.com/v1/messages', {
      method: 'POST',
      headers: {
        'x-api-key': process.env.ANTHROPIC_API_KEY,
        'anthropic-version': '2023-06-01',
        'content-type': 'application/json',
      },
      body: JSON.stringify({
        model: 'claude-haiku-4-5',
        max_tokens: 400,
        // Prompt caching: the big system prompt is cached across requests -> most calls cost fractions of a cent.
        system: [{ type: 'text', text: SYSTEM_PROMPT, cache_control: { type: 'ephemeral' } }],
        messages,
      }),
    });

    if (!resp.ok) {
      console.error('Anthropic API error', resp.status, await resp.text());
      return { statusCode: 502, headers, body: JSON.stringify({ error: 'upstream' }) };
    }

    const data = await resp.json();
    const answer = (data.content || []).filter(b => b.type === 'text').map(b => b.text).join('\n').trim();
    return { statusCode: 200, headers, body: JSON.stringify({ answer }) };
  } catch (e) {
    console.error(e);
    return { statusCode: 500, headers, body: JSON.stringify({ error: 'server' }) };
  }
};
