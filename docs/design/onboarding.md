# Onboarding: the shortest path to the first real number

**Status:** design, Aug 2 2026. Not built. Supersedes nothing — there is no onboarding flow today, the
app simply prompts as it goes. Companion to the *Setup videos for the permission chain* backlog entry
(Aug 1), which specifies the video library this doc places.

**The goal in one line:** the user reaches a screen showing their own data with as few decisions as
possible, and no permission is ever requested before they understand why.

---

## The rule that shapes everything

**An iOS permission prompt fires once.** Deny it and the only route back is the Settings app, which
in practice means never. So the cost of asking early is not friction — it is a permanent capability
loss for that user.

⇒ **Ask for a permission at the moment its value is legible, not at install.** A ten-screen wizard
that front-loads all six prompts converts shrugs into permanent denials.

Second rule, from the same family: **a denied Health READ is invisible to the app.** Apple returns
`.notDetermined` for reads whether or not the user granted them, by design. We cannot ask the system
whether onboarding worked. We can only look for data. That single fact drives the verification step
below, and it is why "grant everything up front" fails silently rather than loudly.

---

## The spine — four steps, one decision each

Only what gates the first real number blocks the user.

| # | Step | Why it blocks |
|---|---|---|
| 1 | Install the Watch app · **pick the more-affected wrist** | Wrong wrist ⇒ every downstream number is wrong. Not guessable, and not recoverable by us. |
| 2 | Health permissions — the "Turn On All" sheet | The data floor. |
| 3 | Motion & Fitness — iPhone **and** Watch | Gates the Movement Disorder API. Without it there is no data at all, not merely less. |
| 4 | **What week 1 looks like** | Not a permission. Sets the expectation that insights need days of data. The cold-start churn moment, and the cheapest screen in the flow. |

Nothing else blocks.

## Just-in-time — asked at the tap

| Permission | Asked when |
|---|---|
| Microphone + Speech | First tap on the mic |
| Camera | First tap on "Scan a package barcode" |

Both arrive with the intent already formed, which is the condition under which people say yes.

## iCloud is not a prompt

It is a Settings toggle, so it cannot sit in a prompt chain. Putting it at step 4 sends the user out
of the app before they have seen anything — the worst possible exit point.

⇒ **Deferred nudge**, surfaced once there is data worth protecting (day 2+), tied to the account-status
check in the *Support → Details doesn't report iCloud status* entry. Same plumbing, user-facing
placement.

⚠️ CloudKit is the only restore path (CSV import retired Jul 31). This nudge is the one that decides
whether a user's record survives a lost phone.

---

## Where video sits — outside the app, always

**⛔ DECIDED Aug 2 2026: no video ships inside the app.** Not bundled, not streamed inline, not as
short loops. The binary stays lean and the spine stays offline-capable. This is settled; do not
re-propose inline clips on the grounds that they are "only a few MB."

⇒ **Every step card is static** — text plus a still image — and carries one **"Show me how"** link
that opens the phone's browser. The stuck user gets the video; everyone else never leaves the flow.

### Where the link points

**Recommendation: `kampa.health/start#<step-anchor>`, not a YouTube URL.**

| | Deep link to `/start` | Direct YouTube link |
|---|---|---|
| Control of the destination | Ours | YouTube's — related videos, ads, sign-in walls, autoplay-next |
| Prose fallback beside the video | Yes | No |
| Change hosting later | Edit the page | Requires an app update |
| Drift risk | One artifact | Two that diverge |

YouTube stays the **embed source** — it carries the bandwidth, which is the whole point of not
self-hosting. The user just never lands there directly.

⇒ The in-app link and the website section are the same artifact, addressed by anchor. Nothing to keep
in sync.

### Capture handoff — how clips reach the page

**Name each file by its anchor.** The name is the mapping; anything else has to be guessed at
embed time.

```
01-watch   02-health   03-motion   04-icloud       05-medications
06-voice   07-workouts 08-data-sources  09-barcode  10-week-one
```

Three things that are expensive to fix after capture:

- **Portrait 9:16.** The slots on `/start` are portrait. A landscape clip letterboxes to a strip.
- **Unlisted, not Private.** Unlisted embeds; Private does not.
- **Channel marked "not made for kids"** (Settings → Channel → Advanced). Kids-directed videos have
  embedding disabled outright.

Per-clip content: the caption under each slot in `website/start.html` says what that clip should
show. The ten-item priority table lives in the *Setup videos for the permission chain* backlog entry.

⚠️ `marketing/linkedin/2026-07-26-food-capture/SHOTLIST.md` is a **different job** — the food-capture
LinkedIn post. Useful as a style reference (silent, captioned, real data not staged); not the spec for
these ten.

### The offline consequence, now clean

First run frequently happens on cellular or a poor connection. Because video is always a link out and
never a dependency:

- **The spine never waits on a network call.** Text + stills, bundled, instant.
- A user with no connection completes onboarding fully. They only lose the optional help.

This was the constraint that made inline video awkward. Removing inline video removes the constraint.

---

## The verification step — the screen that makes it trustworthy

After step 3, a brief "checking" state that waits for the **first real sample to land** and then says:

> We're seeing your Watch.

This exists because the permission state is unreadable (above). Data arriving is the only honest
proof, and this screen converts an invisible failure into a visible one at the exact moment the user
is still willing to fix it.

⬜ Falls out of the same problem: when a stream is empty anywhere in the app, say *"no sleep data —
check Health permissions"* rather than render an empty chart. Logged separately; same root cause.

---

## The website page — for the user who wants to read ahead

Some people will not touch a health app until they understand it. Today there is nowhere to send
them: `docs/getting-started-guide.md` covers this in prose but ships as a PDF/HTML attachment, not a
URL.

**`kampa.health/start`** — the full library on one page, in first-run order, free of the app's
constraints:

- All ten videos, embedded from unlisted YouTube/Vimeo. **Embeds, not hosted files** — keeps Netlify
  bandwidth and deploy credits out of it.
- Each with a one-paragraph prose version beside it, so the page is useful muted, translated, or on a
  slow connection.
- The medication hand-off explained properly — third-party apps cannot write doses, so Kampa hands off
  to Health. It is the most confusing step in the product and the one that most needs room.
- What week 1 looks like, expanded.

**Three jobs, one page:**

1. **Pre-install study** for the eager user.
2. **The "Show me how" destination** — deep-linked per section, so the in-app escape hatch and the
   website are one artifact, not two that drift.
3. **The support answer** — link it from `/support`, the FAQ, and Settings → Getting started.

⇒ This page is what lets the in-app spine stay at four screens. Everything the thorough user wants
exists; it just is not in their way.

⚠️ Batch the deploy with other site work — ~15 credits per production deploy, 300/month.

---

## ⚠️ Build order — `/start` ships FIRST

The four step cards link out to `kampa.health/start#<anchor>`. Ship the app screens first and those
links 404 during setup.

**The asymmetry is the reason it matters:** a website fix deploys in minutes; an app fix goes through
App Store review — days, no rollback. A dead link baked into a shipped build is expensive. A page
sitting live and unused for a few weeks costs nothing.

⇒ **`/start` live → then the spine.** The page is also independently useful the day it lands (support
answer, pre-install study), so there is no waiting cost.

---

## Deliberately omitted

- **Any screen explaining what Kampa is.** They installed it.
- **The medication hand-off**, despite being the highest-value video. It is not onboarding — it is the
  first time they log a dose. Teach it there, and on `/start`.
- **Account creation.** There is none, and that is a feature.

---

## Open decisions

| | |
|---|---|
| ⬜ | Can the spine be re-entered from Settings after a skip, or is it once-only? |
| ⬜ | Does step 1 hard-block if no Watch is paired, or allow phone-only with a reduced promise? |
| ⬜ | Is there a Kampa YouTube channel yet, or do the clips go up unlisted under a personal account? Affects only the embed source, not the design. |
