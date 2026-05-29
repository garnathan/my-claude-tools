# AI-writing tells, and how to fix each

> The reference the `deai` skill reads before rewriting. Synthesised from the Wikipedia "Signs of AI writing" catalogue, GPTZero/Pangram/Originality detector methodology, a 14M-abstract PubMed study of post-ChatGPT word-frequency spikes, and writing-craft sources. Each entry is **tell → fix**.
>
> **The core model: there are two tiers of tell, and you must fix both.**
> - **Human-eye tells** — vocabulary, em-dashes, bolding, formulaic intros. A careful reader spots these. Easy to fix, but fixing *only* these leaves the text detectable.
> - **Machine-statistical tells** — low *burstiness* (uniform sentence length), low *perplexity* (predictable word choice), low diversity. These survive surface paraphrasing and are what actually separate human from machine.
>
> The single highest-leverage move hits both: **deliberate sentence-length variance (Short–Long–Short)**. The strongest content move — **replacing abstraction with the concrete specifics already in the source, and committing to a stance** — defeats both a detector and a careful human, and stays fully professional.

---

## 1. Lexical blocklist (priority-ordered by measured spike)

Replace or delete. Order reflects how strongly each correlates with AI in formal text (PubMed-measured % increases 2022→2024 in parentheses where known).

**Tier-1 — burned words (near-certain tells; almost always cut):**
- delve / delve into (+1,500%) → look at, dig into, examine, get into
- underscore / underscores (+1,000%) → show, stress, point to
- intricate (+700%) → complex, detailed
- tapestry / rich tapestry → mix, range (usually delete — the single most burned word)
- meticulous / meticulously (+137%) → careful, exact, by hand
- commendable (+83%) → good, solid
- realm ("in the realm of") → area, field (often delete)
- testament ("a testament to") → shows, proves
- pivotal → important, central (usually delete)
- garner → get, earn, attract
- boast / boasts → has, includes

**Tier-2 — inflated verbs:**
- leverage / utilize / harness → use
- foster / cultivate → build, encourage
- facilitate → help, ease
- streamline → simplify, speed up
- bolster → support, strengthen
- enhance / elevate → improve, sharpen, raise
- showcase → show, display
- illuminate / shed light on → explain, clarify
- navigate (the landscape) → handle, work through
- embark (on a journey) → start, begin
- unlock / unleash / empower → enable, let, allow
- resonate (with) → connect, land
- align with → match, fit

**Tier-3 — promotional adjectives:**
- robust → strong, solid, reliable
- crucial / vital / key / paramount → important (and usually delete)
- comprehensive → complete, full, thorough
- seamless / seamlessly → smooth, clean
- multifaceted / nuanced → complex, layered
- innovative / cutting-edge / groundbreaking / game-changing / revolutionary / transformative → new, novel (or name the actual change)
- vibrant / rich / profound → (delete; show, don't label)
- invaluable → useful, valuable
- notable / noteworthy → (delete; if it's notable the reader sees it)
- versatile / scalable / dynamic / holistic → (replace with the concrete property)

**Tier-4 — filler abstractions (nouns):**
- landscape ("ever-evolving landscape") → field, market, situation (often delete)
- journey ("on this journey") → process, work
- ecosystem (outside biology) → system, network
- synergy / interplay → (say what actually combines)
- insights ("valuable insights") → findings, points, lessons
- paradigm → model, approach
- underpinnings → basis, foundation

> Don't thesaurus-swap mechanically — that produces flat, still-detectable text. Prefer the plainer word, or delete the sentence's decoration entirely.

---

## 2. Phrase & scaffolding blocklist (delete on sight)

These are pure connective tissue with no content — cut them and the sentence is stronger:
- "It's worth noting that" / "It is important to note that" / "It's important to remember"
- "When it comes to …" → "for / with / in"
- "In today's fast-paced world" / "In an increasingly digital age" / "Now more than ever" / "In an era of"
- "At its core" → "basically" or delete
- "That being said" → "still / but / even so"
- "As we delve into" / "As we navigate" / "In this article we will explore" / "As we have seen"
- "In conclusion" / "Ultimately" / "Overall" / "In summary" / "At the end of the day"
- "needless to say", "it goes without saying"

Transitions used as reflexes (thin them out, don't open every paragraph with one):
- moreover / furthermore / additionally → "also", "and", or just start the sentence
- notably / importantly / significantly → delete; let the fact carry weight
- consequently / therefore / thus / hence → "so"

---

## 3. Punctuation & typography (these are human-eye tells)

Fix for the reader; know they don't move the statistical needle on their own.
- **Em-dash overuse (—)** — the "ChatGPT dash". Keep one or two genuinely earned ones; convert the rest to a period, comma, colon, or parentheses. **Do not zero them out** — real writers use them; an obviously dash-free text is its own tell.
- **Smart vs straight quotes** (" " ' ' vs " ' ) — normalise to whatever the surrounding document/house style uses. Mismatched quotes mid-document is a paste tell.
- **Rule-of-three everywhere** ("X, Y, and Z" in every list, every adjective string) → break the count: use two, or four, or one.
- **Decorative bolding** of every key term, inline `**Header:**` bullets → bold sparingly; let prose carry emphasis.
- **Emoji in headers / as bullets** → remove for professional register.
- **Title Case Headings** / "X: A Comprehensive Guide to Y" colon-titles → sentence case, plain declarative titles (match house style).
- **Too-perfect uniformity** — robotically identical punctuation/structure reads machine. Don't introduce errors; do allow natural variation.

---

## 4. Structural & rhetorical patterns

- **"It's not just X, it's Y" / "not X, but Y"** — the compulsive LLM antithesis. Allow **one** per piece, where the punch is earned; convert the rest to plain statements.
- **"From A to B"** framing ("from boardrooms to break rooms") → name the actual range or drop it.
- **"Not only… but also"** → split into two sentences or cut "not only".
- **Copula avoidance** — "serves as / stands as / represents / functions as / boasts" instead of "is" → just use "is".
- **Formulaic intro** (scene-setting, "Imagine a world where…") → open on a specific fact, number, or claim.
- **Formulaic conclusion** (recap of what was just said) → end on the strongest specific point; don't summarise.
- **Self-narration** ("In this article we will… / As we've seen…") → delete the meta-commentary.
- **Bulleted-list reflex** (everything in bullets, each a bold header + colon) → use prose; reserve lists for genuinely parallel items.
- **Uniform paragraph length** → vary deliberately; a one-line paragraph beside a long one.
- **Relentless hedging** ("can / may / might / often / generally / typically / tends to / arguably / to some extent") → cut; make the specific claim. Keep a hedge only where the uncertainty is real and load-bearing.
- **Relentless balance / no stance** ("While X, it's also important to consider Y" on every point) → pick a side; note the counterpoint once, briefly, if at all.

---

## 5. Statistical signatures (the part that survives paraphrasing — fix these or it stays detectable)

- **Burstiness (sentence-length variance).** Humans mix 3-word and 40-word sentences; AI runs 18–24-word sentences one after another. This uniformity is the biggest surviving tell. **Fix — Short–Long–Short:** never let three same-length sentences sit together. Put a ≤5-word sentence beside a 35-word one. At least one very short sentence per paragraph. This single move is the highest-leverage edit in the whole playbook.
- **Perplexity (word-choice predictability).** AI picks the highest-probability next word, so the text is too smooth. **Fix:** one genuinely unexpected-but-correct word per passage; a concrete proper noun; an exact number. Not thesaurus swaps (those stay flat).
- **Lexical diversity.** AI repeats vocabulary and structure. **Fix:** vary sentence openings (not every one subject-first), vary syntax, don't reuse the same connective.
- **Vary perplexity *and* burstiness together.** Changing words while keeping uniform rhythm still gets flagged. Cadence variance is the one that matters most.

---

## 6. Tone & content tells

- **No stance.** AI is hedged, balanced, agreeable. → Take a position; let a reader who disagrees have something to push against.
- **No concrete specifics.** AI says "a number of"; a human says "seven". AI states facts without sources. → Use the exact figures, names, dates, and examples **already present in the source**. (See the hard constraint below — never invent them.)
- **No personal/lived detail or voice.** → Keep any specific, first-hand, or domain-insider detail the source contains; foreground it.
- **Over-comprehensive, no priority.** AI covers every angle equally. → Privilege what matters; cut exhaustive even-handed coverage.
- **Summarising itself** ("As discussed above…") → delete; trust the reader.
- **Uniform register** — one even tone throughout. → Modulate: a blunt short sentence after a careful one.

---

## 7. What human professional writing does (the target — without going casual)

All of these are compatible with a formal/professional register. None require slang:
- **Specificity over generality** — exact figures, named sources, dated events. The #1 human differentiator, and it never reads casual.
- **A clear point of view** — argues, doesn't survey neutrally.
- **Burstiness in service of emphasis** — short sentence for the punch, long for the nuance.
- **Rhetorical devices used once** — a single antithesis or tricolon lands *because* it's rare. AI's failure is repetition, not the device.
- **Domain texture** — real jargon used correctly, an acknowledged trade-off, a reference an insider would make.
- **Controlled informality, not errors** — a sentence fragment for effect; an "And"/"But" opener; direct address. Within professional bounds.
- **Concrete verbs** — "cut, shipped, broke, powers" over "facilitates, leverages, enhances".

---

## 8. Hard constraints (do not violate)

1. **Never fabricate to sound human.** The strongest human signal is concrete specifics — but you are *transforming existing text*, not authoring new facts. Use only the numbers, names, dates, and examples already in the source. If the source is vague, it stays vague (or you flag the vagueness) — you do **not** invent a statistic, source, or anecdote to add "human" texture. Fabrication is a worse failure than detectability.
2. **Preserve meaning.** The de-AI'd text must say the same thing as the input. Style changes; substance doesn't.
3. **Don't introduce errors.** This is professional writing. Controlled informality (a fragment, an "And" opener) is fine; grammar/spelling mistakes are not.
4. **Professional, not casual.** No slang, no exclamation-point hype, no "honestly/literally/basically" tics, no emoji, no jokey asides, no second-person marketing voice. Human ≠ relaxed. You buy humanity through specificity, stance, and rhythm — not through loosening the register.
5. **Match the document's register and conventions.** Contractions ("don't/it's") read human in most business and editorial writing — use them there; reserve fully-spelled forms for formal/legal/academic. Match smart-vs-straight quotes and heading style to the surrounding document.
6. **Don't cargo-cult.** Removing every em-dash or swapping synonyms doesn't fool a real detector and can read worse. The moves that matter: cadence variance, killed scaffolding, concrete specifics already present, a real stance.
