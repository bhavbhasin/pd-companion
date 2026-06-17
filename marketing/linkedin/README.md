# Kampa — LinkedIn Content Tracker

Running record of what's posted, what's queued, and what's in the idea bank.
Posted from the **Kampa Health** company page. Target **≥1 post/week**, but post more
when feature traction warrants it — cadence follows the building, not a fixed calendar.

- Each post's copy + cards live in `YYYY-MM-DD-topic/` (`post.md`, `card1.png`, `card2.png`).
- Feature backlog (what we're building) = `../../BACKLOG.md`. This tracker is the bridge:
  shipped feature → post. When a feature lands, log a candidate in **Next up**.
- Brand assets for cards: `../../website/assets/brand/` (see `BRAND.md` — don't re-screenshot).
- **Website sync:** the `Site` column logs each post's website treatment — `none` /
  `changelog` (add to the *What's new* section of `index.html`) / `core` (hero/pitch update).
  The website is the **evergreen source of truth**, updated for major features — not synced 1:1
  with posts (LinkedIn is frequent; the site changes on enhancements & features that last).
- Public voice: builder/founder; **never disclose the founder personally has Parkinson's**;
  privacy copy uses ownership/control framing, not "we can't see it" absolutes.

---

## Posted

| # | Date | Topic | Feature(s) showcased | Site | Link |
|---|------|-------|----------------------|------|------|
| 1 | 2026-06-02 | Introducing Kampa | Passive tremor/dyskinesia tracking; correlation concept; Movement Disorder API + HealthKit | `core` (site launch) | [post](https://www.linkedin.com/posts/kampa-health_parkinsons-digitalhealth-applewatch-activity-7467694178894794752-xz3t) |
| 2 | 2026-06-17 | Your health, your data (privacy) | Private CloudKit backup/restore; in-app data inventory; resilient restore | `changelog` | [post](https://www.linkedin.com/feed/update/urn:li:activity:7472924192384966658) |

---

## Next up (targeted, ordered)

> `ready` = can write now · `needs-feature` = waiting on a build to ship first

- [ ] **Kampa is in testing — request access** — TestFlight launch. The next big beat. Dual moment: website CTA ("request access") + a strong post. Site: `core` (adds an access CTA) + `changelog`. — `needs-feature` (TestFlight release; see BACKLOG.md distribution-readiness)
- [ ] **The first patterns Kampa surfaced** — the correlation engine: levodopa wearing-off window, OFF-period timing. The strongest "this actually works" story. — `needs-feature` (correlation engine, see BACKLOG.md / ParkinsonsProject.md)
- [ ] **Why "Kampa"?** — etymology: *Kampavata*, the Ayurvedic name for the tremor disorder. Human, distinctive, zero new features required. Good filler for a build-light week. — `ready`
- [ ] **Ambient voice insight ("the magic")** — plain-language daily summary, hands-free. — `needs-feature`

## Idea bank (unscheduled)

- **Passive, zero-burden tracking** — the "no tap, no log" thesis; why manual tracking is backwards for motor impairment. (Angle, not a feature.)
- **On-device intelligence** — why processing/insight runs on the device, not a server (privacy + speed). Pairs with the privacy post.
- **Movement Disorder API deep-dive** — technical credibility for the research/clinical audience.
- **Data portability** — CSV export of everything you've tracked ("your data, take it anywhere").
- **Food / nutrition logging** — once correlated with symptoms, a "what you eat vs how you feel" story.

---

*Update this file when posting (move the row to Posted) and when a feature ships (add a Next-up candidate).*
