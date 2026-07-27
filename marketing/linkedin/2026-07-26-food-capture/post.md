# Post — Food capture: say it, type it, or scan it (all on-device)

**Status:** DRAFT, not published. **Target:** Kampa Health company page (last posted Jul 8).
**Register:** tangible first, engineering underneath, honest limit at the end.
**Merges** the two former Next-up entries (barcode + on-device food understanding) into one story.

**Guardrails applied:** never disclose founder PD · no "we can't see it" absolutes (ownership framing) ·
do NOT quote the 99.4% alias number as a result · no competitor named · this IS logging, so don't
claim "no logging" · OCR is deferred — not mentioned, not teased.

---

## Copy

Food is one of the few Parkinson's variables a person actually controls. Protein competes with levodopa for absorption. Caffeine, sugar and fiber all show up in how a day goes. So Kampa had to be able to capture what you ate — without turning eating into paperwork.

There are three ways in, and all three end in the same place.

**Say it.** Tap the mic, say "chai, almonds and walnuts," done.
**Type it.** If your hands are steady and you'd rather.
**Scan it.** Point the camera at a barcode on a package.

What comes back isn't a calorie count. It's a decomposition: the entry, and under it the things the engine can actually reason about — Protein · Fiber · Fat · Sugar · Caffeine. Five chips. That's deliberately coarse, because coarse and correct beats precise and invented.

Under the hood, the part I didn't expect to be the interesting problem:

Kampa ships the food databases **inside the app**. There's no nutrition API, no lookup call, no request that leaves the phone when you log a meal. That's not a slogan — it's a property you get by not writing the networking code in the first place, and it's much harder to lose by accident later.

For packaged food that meant fitting the USDA Branded Foods dataset into an app download. Raw, it's 2 million rows. But the dataset resubmits each product about 4.3 times, so those 2M rows are really **439,082 unique barcodes**. Dedupe by barcode, keep only the five nutrients the engine uses, quantize them to a byte each, sort the whole thing by barcode and binary-search it, then compress the product names in blocks.

Result: **11.8 MB** for 439k products. A naive database would have been ~160 MB.

One detail I'd defend in a code review: each record carries a flags byte marking which nutrients are actually *known*. "Zero grams of sugar" and "we don't know the sugar" have to stay different values. Collapse them and the engine quietly reads missing data as absence — and then it correlates on a fact that was never in evidence.

And the honest part. A US food database describes a global diet badly. We measured it rather than assumed it: across a wide multi-region test set, full resolution sits around 33%, and by region it's brutally uneven — North African came in at 6%. An LLM-drafted expansion of the mappings scored beautifully against the very set it was drafted from, which proves the mappings resolve, not that they generalize. That number went in the bin.

So: barcode where the barcode lands, a real measured floor everywhere else, and a manual path that never dead-ends. Coverage is the work in front of us — not something we're going to claim we've finished.

Your data stays yours, on your device. Kampa is not medical advice.

#Parkinsons #DigitalHealth #OnDeviceAI #Privacy #ProductDesign

---

## Assets needed

See `SHOTLIST.md` in this folder.
