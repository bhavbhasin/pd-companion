# Working file: food capture article (this line is NOT the title, see "Title field" below)

**Status:** DRAFT, not published. **Format:** LinkedIn *article* (not a feed post).
**Target:** Kampa Health company page (last posted Jul 8).
**Register:** tangible first, engineering underneath, honest limit at the end.
**Merges** the two former Next-up entries (barcode + on-device food understanding) into one story.

**Guardrails applied:** never disclose founder PD · no "we can't see it" absolutes (ownership framing) ·
do NOT quote the 99.4% alias number as a result · no competitor named · this IS logging, so don't
claim "no logging" · OCR is deferred, not mentioned, not teased.

**Paste note:** the LinkedIn article editor does not convert Markdown. Paste as plain text, then apply
headings, bullets, bold and the pull quote with the toolbar. The `##` marks below are instructions to
you, not characters to paste.

---

## Title field

Paste this exact line into LinkedIn's title field, no asterisks, no quotation marks:

Food Logging, Built for Parkinson's 

⚠ This sentence used to open the body as well. It has been cut from the body so it appears once. If
you switch to one of the alternates below, put it back as the body's first line, otherwise the piece
opens cold on "Protein competes with levodopa for absorption."

Alternates if you want the engineering angle to lead instead:
- 439,082 products in 11.8 MB, with no network call
- What "on-device" actually costs to build

Recommendation: the title above. LinkedIn shows the title plus the opening lines in the feed preview,
so the title makes the claim and the first body line supplies the evidence for it. The patient and
clinician half of the audience reads that line as being about them, and the engineering payoff still
lands three screens down for the people who care about it. The alternates are aimed at builders and
would suit X better than the company page.

## Cover

**Use the video as the cover.** LinkedIn articles accept a cover video, uploaded the same way as a
cover image, with closed captions and a custom thumbnail. Set the thumbnail to shot 1 (Entry +
Detected chips), which is where the video ends anyway per the sequence in `SHOTLIST.md`. That way the
still that sells the thesis is what shows in the feed preview and in any email, and the video plays
for anyone who opens the article.

Specs: cover images are 1920x1080, cropped 16:9, JPEG/PNG/WEBP (GIFs are no longer accepted). The
shotlist calls for portrait 9:16 or 4:5 because it was written for a feed post. **A cover video needs
a landscape re-frame**, so shoot it or export it accordingly, or accept letterboxing.

Fallback if the cover video slips: shot 1 as a 1920x1080 still, framed with headroom for the wide crop.

---

## Copy

<!-- No subhead on the opening. First two lines are the feed preview; leave them dense. -->

Food is one of the few Parkinson's variables you actually control. Protein competes with levodopa for absorption. Caffeine, sugar and fiber all show up in how a day goes. So Kampa had to capture what you ate without turning eating into paperwork.

### Three ways in

There are three ways in, and all three end in the same place.

<!-- Toolbar: bulleted list. Do not bold the opening words; the toolbar bullet is enough structure. -->

- Say it. Tap the mic, say "coffee, almonds and walnuts," done.
- Type it. If your hands are steady and you'd rather.
- Scan it. Point the camera at a barcode on a package.

<!-- IMAGE: shot 4 (mic entry point) or shot 2 (barcode scanner live). One, not both. Caption it. -->

What comes back is a decomposition, not a calorie count: the entry, and under it the things the engine can actually reason about. Protein, fiber, fat, sugar, caffeine. Five chips. That's deliberately coarse, because coarse and correct beats precise and invented.

### The databases ship inside the app

Under the hood, the part I didn't expect to be the interesting problem:

Kampa ships the food databases inside the app. There's no nutrition API, no lookup call, no request that leaves the phone when you log a meal. You get that property by never writing the networking code in the first place, which makes it much harder to lose by accident later.

For packaged food that meant fitting the USDA Branded Foods dataset into an app download. Raw, it's 2 million rows. But the dataset resubmits each product about 4.3 times, so those 2M rows are really 439,082 unique barcodes. Dedupe by barcode, keep only the five nutrients the engine uses, quantize them to a byte each, sort the whole thing by barcode and binary-search it, then compress the product names in blocks.

Result: 11.8 MB for 439k products. A naive database would have been around 160 MB.

<!-- IMAGE: the explainer card from SHOTLIST.md (2M rows → 439,082 → 11.8 MB). This is the one place
     a diagram earns its space in an article. Caption: "USDA Branded Foods, reduced to what the engine
     reads." -->

### Zero is not the same as unknown

One detail I'd defend in a code review: each record carries a flags byte marking which nutrients are actually known. "Zero grams of sugar" and "we don't know the sugar" have to stay different values. Collapse them and the engine quietly reads missing data as absence, then correlates on a fact that was never in evidence.

### The honest part

A US food database describes a global diet badly. We measured that rather than assuming it. Across a wide multi-region test set, full resolution sits around 33%, and by region it's brutally uneven. North African came in at 6%. An LLM-drafted expansion of the mappings scored beautifully against the very set it was drafted from, which proves the mappings resolve, not that they generalize. That number went in the bin.

So: barcode where the barcode lands, a real measured floor everywhere else, and a manual path that never dead-ends. Coverage is the work in front of us, and we're not going to claim we've finished it.

<!-- Toolbar: block quote. One pull quote only, placed near the top of this section so it breaks up
     the longest stretch of text. -->

> Coarse and correct beats precise and invented.

Your data stays yours, on your device. 

---

## Share commentary (when you post the article to the feed)

Put the hashtags here rather than in the article body. The article editor has no tag field, and tags in
an article body do not behave like they do in a feed post. Two or three lines plus the tags:

One of my favorite features launched in Kampa to date. Food plays a key role in Parkinson's symptoms management. This post describes how we
  built frictionless food logging with wide coverage, without the need for server calls. #Kampa #Parkinsons #HealthTech #AppleHealth #Privacy

Three ways to log food in Kampa, and the part I didn't expect to be the hard problem: fitting 439,082 products into 11.8 MB so the lookup never leaves your phone.

#Parkinsons #HealthTech  #AppleHealth  #Privacy #ProductDesign

---

## Assets needed

See `SHOTLIST.md` in this folder. It was written for a feed post, so three things change:

- **The video stays the lead asset**, as the article cover. Verified against LinkedIn's help docs: a
  cover video is supported, and native video uploads work in the article body too.
- **Aspect ratio flips.** The shotlist specifies portrait 9:16 or 4:5 for the feed. The cover slot is
  16:9, so the video needs a landscape export. If you want both the article cover and a feed-post
  version, that is two exports from the same capture, not one.
- **The carousel option is dead.** Articles take inline images one at a time, so shot 5 (timeline
  context) and the explainer card compete for the same slot. Explainer card wins.
- Pre-flight checklist in `SHOTLIST.md` still applies, especially confirming the scanned product still
  resolves on the current build.
