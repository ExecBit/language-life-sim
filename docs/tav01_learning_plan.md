# TAV-01 — Tavern vocabulary and the linked learning-situation plan (Issue #8)

Planning deliverable for TAV-01. What is committed as data by this task:

- `data/vocabulary/de_a1_starter.json` — the corpus, extended in place from 15 to **47 lemmas**.
- `data/scenarios/tav01_sample_shift.json` — **10** representative playable records (`t01`…`t10`) built with the mechanics and props that already exist.

What is only planned here and deliberately **not** implemented: the rest of the shift, the event grouping, the situation ground-truth key, the review scheduler, any new scene, prop, action or sound. TAV-02…TAV-06 own those.

## 1. The corpus (47 lemmas, one verified source)

One source only: the official Goethe-Zertifikat A1 (Start Deutsch 1) Wortliste PDF, section *Alphabetische Wortliste*. Every recorded `source_entry`, `source_example_de` and `source_page` was re-checked against a layout-mode extraction of that PDF by a throwaway script in ignored `.local/` (see §8). The 15 lemmas PREP-01 delivered keep their ids, values and order; the 32 new ones are appended.

| part of speech | count | lemmas (Wortliste page) |
| --- | --- | --- |
| noun | 23 | existing 10 (Tisch 24, Schrank 22, Sofa 23, Bett 11, Bild 11, Kühlschrank 19, Brötchen 12, Kartoffel 18, Tomate 24, Fleisch 15) + **Bier 11, Glas 16, Wein 25, Wasser 25, Kaffee 18, Milch 20, Rechnung 22, Speisekarte 23, Gast 15, Hunger 17, Durst 13, Geld 15, Küche 18** |
| verb | 12 | existing suchen 24, finden 14, bringen 12 + **bestellen 11, bezahlen 11, trinken 24, essen 14, möchten 20, holen 17, nehmen 20, kosten 18, schmecken 22** |
| adjective | 7 | existing groß 16, klein 18 + **teuer 24, billig 11, gut 16, fertig 14, wunderbar 26** |
| preposition | 2 | **mit 20, ohne 21** |
| adverb | 1 | **zusammen 27** |
| expression | 2 | **danke** (13, printed as an indented *Nebeneintrag* under the headword *danken*), **„Wie bitte?“** (26, printed as a *Redewendung* under the headword *wie*) |

24 of the 47 lemmas are not nouns. That is the point: a tavern shift is carried by verbs (*holen, nehmen, bestellen, bezahlen, kosten*), by adjectives that a scene can prove (*fertig, teuer, billig*) and by everyday replies (*danke, Wie bitte?*). A noun-only list would only ever teach things to click.

Honesty rules written into the data:

- `source_kind` says what the source printed: `headword`, `nebeneintrag` or `redewendung`. A sub-entry names its `source_parent`. Nothing pretends to be a headword.
- Every lemma carries a Russian `ru` meaning, and CI now requires it for every lemma, not only for the prop-bearing nouns — a verb or an adverb has no object to point at, so the hint text is the only place its meaning exists.
- `not_in_source` lists the everyday tavern words that are **not** A1 entries and therefore are not used at all, verified absent as printed entries: *Theke, Kellner, Bedienung, Teller, Stuhl, Tür, warm, heiß, frisch, voll, leer, nett, freundlich, Prost, Gesundheit, genau*. Near matches are named instead of smuggled in: *hinten* (17) is an entry where *hinter* was looked for, *der Herd* (15) only appears inside *die Küche*'s example.
- `reserve_pool` holds 13 further A1 entries that were verified on a page but are **not** committed as lemmas (*kaputt, der Preis, die Flasche, das Essen, das Frühstück, mögen, die Karte, bitte, die Entschuldigung, der Moment* + „Einen Moment bitte“, „Guten Tag“, *das Restaurant, hinten*), each with the reason it is held back. TAV-06 can draw on them without redoing the research; until a task commits one as a lemma it is taught by nothing.
- It is still a **candidate list, not a frequency ranking**, and the `ru`/`en` glosses are agent-authored helper translations that need human review.

## 2. The authored shift

One shift = one ordered sequence of nine situations at one table. `E1…E9` are plan labels, not data yet: no event grouping exists in the format, so today a "shift" can only be expressed as records on a day.

| # | event | what happens | lemmas in play | action type intended | introduce / reuse | what it needs to be playable |
| --- | --- | --- | --- | --- | --- | --- |
| E1 | arrival | the guest arrives, the player greets, the guest speaks too fast, the player asks again | gast, Guten Tag, Wie bitte? | new `greet` + `farewell`, situation-judged `respond` | introduce | a `situation` ground-truth key (TAV-04); a guest model (TAV-03) |
| E2 | seating | the guest is shown to the table | tisch, zusammen | find_select | reuse tisch (day 1 already taught it) | nothing new |
| E3 | order taking | the guest wants something, the player asks what and takes the order | bestellen, möchten, Bier, Wein, Kaffee, Wasser, Speisekarte | new `take_order` | introduce | `menu.gltf` exists in the pinned pack but is not committed here (TAV-03); a `situation` key for "what does the guest want" (TAV-04) |
| E4 | stock shortage | an ingredient is gone, the player fetches it from the fridge or the cellar | holen, Milch, Hunger, Durst, kuehlschrank, fertig | bring_deliver | introduce holen | nothing new — `t01`/`t07` already do this; *Milch* needs a prop |
| E5 | kitchen prep | the ingredient is taken to the counter and used | nehmen, essen, holen, kueche | bring_deliver | introduce nehmen | `kitchencounter_*.gltf`, `stove_*.gltf`, `cuttingboard.gltf` exist in the pinned pack, not committed (TAV-03) |
| E6 | serving | the dish and the drink go to the table | trinken, schmecken, gut, wunderbar, bringen | new `pour_or_serve` / bring_deliver | introduce | **no mug, glass, cup or bottle model in the pinned Restaurant Bits commit** (TAV-03 must source one) |
| E7 | cleanup | the used plates go back | Teller*, kaputt, bringen | new `clear_table` | reuse | *der Teller* is not an A1 entry, so the event keeps a lemma the corpus does not have; `plate_dirty.gltf` exists in the pinned pack |
| E8 | bill and payment | the bill comes, the player names a price, the guest pays | Rechnung, bezahlen, Geld, teuer, billig, kosten | new `hand_bill`, `collect_payment` | introduce kosten/teuer/billig (done in `t04`/`t06`) | *Rechnung* and *Geld* have no model anywhere in the pack (no cash, register, bill or wallet model) |
| E9 | farewell | thanks and goodbye | danke, Entschuldigung, Guten Tag | new `farewell` | introduce danke | `situation` key + the farewell action (TAV-04) |

## 3. Lemma map: introduction, reuse, delayed review

Introduced and reviewed in the committed sample (`tav01_sample_shift.json`):

| lemma | introduced | reused in | delayed review |
| --- | --- | --- | --- |
| holen (17) | `t01` fetch from the fridge, kitchen | `t07` same verb, target and staged positions swapped, room | `t07` (revisit_of t01) |
| nehmen (20) | `t02` take one named thing to the table, room | `t04`…`t08` frames use bringen instead | planned: E5 for TAV-06 |
| zusammen (27) | `t03` bun on the table, tomato at the fridge → nein, kitchen | `t10` both staged together → ja, room | `t10` (revisit_of t03) |
| kosten (18) | `t04` two prices, kitchen | `t06` same prices, other item; `t08` inside an order, room | `t08` (revisit_of t04) |
| billig (11) | `t04` | `t06` as the wrong alternative; `t08` as target again | `t08` |
| teuer (24) | `t06` | `t04` as the wrong alternative | planned: E8 |
| fertig (14) | `t05` rule stated + bun staged on the table → ja, room | `t09` same rule, bun at the fridge → nein, kitchen | `t09` (revisit_of t05) |
| tomate, kartoffel, broetchen, kuehlschrank, tisch, fleisch | already taught in LEX-01 | `t01`–`t10` in new roles (source of a fetch, priced item, staged together/apart, ordered item) | `t07`–`t10` |

Introduced only as words to hear in the committed sample (never a target, because a scene cannot prove them): *Hunger* (in `t01`'s line), *danke* (in `t01`/`t07`/`t08` feedback), *das Frühstück* (in `t05`/`t09`, and it is a reserve entry, not a lemma).

Deferred on purpose, with the single thing each one waits for:

| blocked by | lemmas | why it is not a target yet |
| --- | --- | --- |
| no committed prop model | Bier, Glas, Wein, Wasser, Kaffee, Milch, Rechnung, Speisekarte, Küche | the player could read the word but never point at the thing; *Speisekarte* has `menu.gltf` available in the pinned pack, the others have nothing |
| social situation needs a ground-truth key | bestellen, möchten, gast, danke, „Wie bitte?“ | whether a greeting, an offer or an order is right cannot be decided by where objects stand |
| no taste, price or inner state in the scene | schmecken, wunderbar, gut, Durst, Geld | judging them from a staged scene would mean guessing |
| needs the event system first | bezahlen, essen, trinken, ohne, mit | they belong to E3/E5/E6/E8 sentences, not to a single click |

Nothing in this table is a permanent decision: each row names the exact dependency, and TAV-03/TAV-04 remove it.

## 4. Worked example: one shift and one next-day review

**Day 1 — the shift as it actually plays today** (six records; the game shuffles option order and the visible candidate positions, so the letters below are the authored ones only):

1. `t01` *Ich habe Hunger. Hol die Tomate aus dem Kühlschrank!* — the tomato is staged at the fridge, the potato and the bun on the table, so "aus dem Kühlschrank" names exactly one object. Verb **holen** introduced; *Hunger* heard, *danke* answers at the end.
2. `t02` *Nimm das Brötchen und bring es auf den Tisch!* — a second carrying verb in a second frame: **nehmen** takes a named thing to a named place (the table is marked as the delivery target).
3. `t03` *Ist das Brötchen zusammen mit der Tomate auf dem Tisch?* → *Nein, … nicht zusammen …* — **zusammen** introduced as a ja/nein pair; both sentences carry the same lemmas, so the only difference is the negation and the answer is visible in the scene.
4. `t04` *Das Brötchen kostet 1 Euro. Das Fleisch kostet 8 Euro. Ist das Brötchen billig?* — **kosten** and **billig** introduced with the evidence written into the sentence: the player compares two numbers, not a feeling about prices.
5. `t05` *Wenn das Brötchen auf dem Tisch ist, ist das Frühstück fertig. Ist das Frühstück fertig?* → *Ja, das Brötchen ist auf dem Tisch …* — **fertig** introduced without asking anyone to judge whether a meal is "ready": the record states its own rule and then stages the fact the rule needs.
6. `t06` *… Ist das Fleisch teuer?* → *Ja, das Fleisch ist teuer.* — the same two prices, the opposite pole, the other item, so the answer cannot be a remembered option. **teuer** introduced.

End of day 1 in the headless run: 17 records presented, 33 lemmas met, 16 summary lines. The new words are credited as targets rather than as answer alternatives in the run's isolated progress save (`user://lex01_progress.probe.json`): `nehmen` is met 1 and correct 1 from `t02` alone (`option_shown` 0), and `holen`, `zusammen` and `fertig` reach their counts only through their `t01`/`t03`/`t05` introductions plus the day-2 revisits.

**Day 2 — the review session** (four records, each declaring `revisit_of`, each in the *other* camera framing than its day-1 record):

1. `t07` (revisit of `t01`) *Hol die Kartoffel aus dem Kühlschrank!* — same verb, the three staged objects in swapped positions: yesterday the tomato was at the fridge and the potato on the table, today the opposite. `holen` registers revisited 1, correct 2, both unaided.
2. `t08` (revisit of `t04`) *Bring das Brötchen! Es kostet nur 1 Euro.* — `kosten`/`billig` return as information inside an order instead of as the question, with the committed verb `bringen` as a third carrying frame.
3. `t09` (revisit of `t05`) the same rule sentence, the bun now staged at the fridge: the answer flips to *Nein, das Brötchen ist im Kühlschrank.* Same words, opposite facts.
4. `t10` (revisit of `t03`) both food items now staged together on the table: the `zusammen` answer flips to *Ja*. The wrong sentence names the fridge, which is where the tomato stood yesterday — a plausible alternative, not a random one.

End of day 2 in the same run: 10 records presented, 21 revisits across all lemmas, 56 lemmas met, 18 summary lines. In the progress save the seven new target lemmas read `holen` met 2 / correct 2 / revisited 1, `nehmen` 1 / 1, `zusammen` 2 / 2 / revisited 1, `fertig` 2 / 2 / revisited 1, `kosten` 3 / 3 / revisited 1, `billig` 2 / 2 / revisited 1 (`option_shown` 1, from t06's wrong sentence), `teuer` 1 / 1 (`option_shown` 1, from t04's wrong sentence) — all with `option_shown` 0 for the verbs, i.e. credited as things the player had to use, not as labels they merely saw.

## 5. Data contract

Fields a record must already have (these are what `scripts/lex01_content.gd` validates today, and `tav01_sample_shift.json` uses nothing else): `id`, `day`, `action_type` (one of `find_select`, `bring_deliver`, `respond`), `context`, `target_lemma_ids`, `distractor_lemma_ids` (derived: lemmas of the wrong options minus lemmas of the correct one), `utterance_de`, `utterance_gloss_ru`, `options[]` with `id` (`a`/`b`/`c` positional), `label_de`, `lemma_ids` (plus `scene_object` for non-respond, plus `gloss_ru` for respond), `correct_option_id`, `feedback_correct_de`, `feedback_wrong_de`; optional `verb_lemma_id`, `npc`, `delivery_target`, `scene_state` (placements must be declared in `data/room/lex01_room.json`), `revisit_of`, `notes`. Unknown fields are ignored, which is what makes the additions below additive.

Fields the plan asks **TAV-04/TAV-05** to adopt, and which TAV-01 deliberately does **not** add to any data file:

- `event_id` / `event_order` — today every record of a `day` is presented as a flat queue, so a connected shift cannot be expressed as data. Without grouping, "one shift" is only a naming convention on ids.
- `situation` — a ground-truth key stated by the record (for example `situation: "greeting"`, `situation: "order_request"`) so a socially decidable answer stops depending on where an object happens to stand. Everything in §3 blocked on "no ground-truth key" waits for this one field.
- `introduced_by` / `review_after` on the lemma record — so the day-2 review is scheduled from data instead of being hand-written as `revisit_of` on each record.

Not added here because a field the loader ignores only looks like support.

## 6. Reusable actions TAV-04 is asked to build (not built here)

`greet` / `farewell`, `take_order`, `pour_or_serve`, `clear_table`, `hand_bill` / `collect_payment`, and a `respond` variant whose correctness comes from `situation` instead of from `scene_state`. Each one is meant to be one reusable action shared by many records — the point of naming them now is that adding a tavern situation later stays a data change.

## 7. What TAV-03 has to supply

Checked against the KayKit Restaurant Bits pack already pinned in this repo (commit `153c8a7`), whose model list is known exactly:

- **exists in the pinned pack but is not committed in this project**: `menu`, `plate`, `plate_dirty`, `bowl`, `jar_A…D`, `crate_buns`, `crate_potatoes`, `crate_tomatoes`, `cuttingboard`, `kitchencounter_*`, `kitchentable_*`, `stove_single`, `stove_multi`, `oven`, `pot_*`, `pan_*`, `dishrack_plates`, `food_stew`, `food_dinner`, `wall_orderwindow`, `door_A`, `door_B`. These would serve E3, E5, E7 and the tavern interior.
- **does not exist anywhere in that pack**: any glass, mug, cup, bottle, tray, napkin, cash, register, bill or wallet model. So E6 (serving drinks) and E8 (the bill as an object) cannot be staged with the assets already licensed here — a drinkware/payment asset has to be chosen first. This is recorded as a TAV-03 dependency and is the reason *Bier, Glas, Wein, Wasser, Kaffee, Milch, Rechnung* are corpus words in a document rather than clickable things in the game.
- This task commits **no** new model: the 10 prop-bearing lemmas and the 2 characters already in `assets/` are the only objects the sample records use.

## 8. Verification actually run for this plan

- **Sourcing check (PASS).** A layout-mode re-extraction of the official PDF plus a throwaway script (`.local/`, ignored) asserted, for all 47 lemmas: the PDF's own footer `Seite N` sits on the recorded page; `source_entry` is printed at the start of a line there; `source_example_de` occurs there; a `headword` sits at that page's entry column while a `nebeneintrag`/`redewendung` sits indented with its parent printed at the entry column; every lemma has a Cyrillic gloss; only the 15 legacy lemmas carry a prop. It also re-confirmed all 16 "absent from A1" claims and all 13 reserve entries. Output: `SOURCE CHECK OK: all 47 lemmas, the reserve pool and the absence claims match the layout extraction.` Two pre-existing records were **corrected** by this check instead of the check being relaxed: `das Brötchen, –` (en dash, not an ASCII hyphen, and its lone-dash marker means the plural equals the singular) and the en dash in *Kühlschrank*'s example sentence.
- **Content checks (PASS).** The assertions CI runs were executed locally over the enlarged data: 47 lemmas (23 nouns, 12 verbs, 7 adjectives, 2 prepositions, 1 adverb, 2 expressions), 3 scenario files, 27 scenarios, 12 lemmas recurring in two contexts, 9 day-2 revisits, one guided record (`s01`), correct-answer positions a=10 / b=11 / c=6.
- **Godot run (PASS).** `--headless --import`, then `res://scenes/main.tscn -- --probe`: `CONTENT lemmas=47 scenario_files=3 scenarios=27 days=[1, 2]`, day 1 `presented=17` / 33 lemmas, day 2 `presented=10` / `revisited=21`, `english_gloss_leaks=0`, no script errors or staging warnings, `LEX01 PROBE OK checks=302`. The run's isolated progress save was read back to confirm that each of the seven new target lemmas is recorded as met and correct, and that the four day-2 revisits each register `revisited` 1.
- **Not verified (NOT_TESTED).** Whether the German and Russian wording of the 32 new lemmas and the 10 new records reads naturally to a human speaker; whether a real beginner can answer `t04`/`t05`/`t06` without the hint (the probe answers them itself); anything about the deferred events in §2, which exist only as text.
