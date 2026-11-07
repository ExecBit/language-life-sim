# Language Life Sim — Game Concept

**Status:** Concept draft 0.1 · **Purpose:** product vision, not an implementation specification

## High concept

A small game about finding your feet in a place where you do not understand the local language. The player starts with **zero German**. By interacting with people and solving ordinary situations, they gradually acquire words and ready-made expressions that let them ask, answer, clarify, and act with increasing independence.

**The language is a tool for accomplishing goals in the world, not a quiz layered over the game.**

The newcomer/immigrant premise provides an understandable starting situation; it is not intended as a realistic immigration bureaucracy simulation. Neither a tavern nor any other specific building or occupation is essential to the concept.

## Player experience

At first, other characters' words are unfamiliar. The player can rely on clear context, gestures/visual cues, and optional help in a language they know. Early interactions should be safe to try and easy to repeat.

Over time, the same useful expressions return in different situations. The player begins to understand without assistance and can achieve things that previously required a translation or explicit guidance. The intended sense of progression is **growing autonomy**: being able to navigate everyday encounters through the new language.

The game should still offer a reason to act beyond completing a vocabulary exercise: a concrete, small, understandable goal in the fictional world. Whether this loop feels engaging enough is a hypothesis to test, not an established fact.

## Audience and starting conditions

- Primary audience: adults and older beginners who know no German, including people who dislike drill-heavy flashcard study.
- Assumed entry level: **below A1 / Pre-A1**; no prerequisite German vocabulary or grammar.
- Starting language: German, with Russian-language support for the initial prototype. Other learning/translation languages are future possibilities, not MVP requirements.
- The game is a supplement to learning, not a promise of fluency or a substitute for real conversation.

## Design pillars

1. **Zero-knowledge entry.** The first meaningful interaction must work for someone who knows no German at all. Introduce a small amount of language with explicit meaning and context before testing it.
2. **Communication before object catalogs.** Prioritize transferable abilities such as greeting, yes/no, thanking, apologizing, indicating non-understanding, asking to repeat, requesting help, and locating something. Objects and verbs appear when needed to enact these abilities.
3. **Language changes what the player can do.** Understanding or choosing an expression should produce a clear outcome in the game world, not only a correct/incorrect popup.
4. **Meaningful repetition.** Reuse an expression for different purposes and with changed context. Correctness must depend on understanding it, not remembering a button, item position, or the previous answer.
5. **Help without punishment.** Make translation, repetition, and contextual guidance available, but distinguish supported success from independent comprehension. Mistakes should not cause dead ends.
6. **Small and reusable interactions.** Favor a few consistent, legible actions over specialized minigames, simulated NPC behavior, complex animation or elaborate environments.

## Core loop

1. **Encounter** an understandable everyday need or interaction.
2. **Interpret** a short German utterance using the scene and, when needed, assistance.
3. **Respond or act** using a minimal set of interactions.
4. **Observe a consequence**: a person responds, an item moves, an option is accepted or declined, a request is resolved.
5. **Reuse** the relevant language later with different circumstances; observe whether the player can succeed with less help.

This is a design loop, **not** a requirement to interrupt play with an exercise screen after every utterance.

## Language progression

Progression is organized around **communicative capabilities**, not locations or raw vocabulary totals:

1. **Make contact:** greet, say goodbye, say yes/no, thank someone.
2. **Repair communication:** apologize/get attention, say “I don't understand,” request repetition or help.
3. **Orient and identify:** ask what/where, recognize simple indications of places and things.
4. **Express basic needs:** make a simple request, accept/refuse an offer.
5. **Follow short requests:** understand and execute simple instructions in everyday routines.

A starting set of roughly **12–15 high-utility words and fixed expressions** is a candidate for exploration, not a finalized curriculum. Multi-word phrases count as communicative units, not single lemmas. The exact selection, order, German naturalness and ability to teach each expression through play must be validated in the MVP design. A player should encounter only a few new units at once.

## Success criteria and learning integrity

The game succeeds at the concept level if a complete beginner can start without external instruction, understand why they are acting, and subsequently recognize or use a small set of German expressions in **new situations without compulsory translation**—while finding the process sufficiently interesting to continue.

Testing must distinguish:
- exposure to an expression;
- a correct response with hints or translation;
- an independent correct response in a changed context;
- delayed recall or recognition after actual elapsed time.

A single correct click is not evidence that a word has been learned. Evidence of listening comprehension requires audio; a text-only prototype measures primarily reading-based comprehension.

## Scope boundaries

**Part of the vision:** recurring everyday encounters; increasing independence; reusable language, situational help, and context-dependent actions.

**Not a foundational requirement:** tavern work, a particular first location, specific props, first-person 3D, an open world, a complex life simulator, simulated economy, free-form conversations, character animation, or audio in the first prototype.

The existing Godot tavern, assets, 47-lemma corpus and 27 scenarios are **reusable experimental material**, not the definition of the new vision. Do not discard or rewrite them solely because this concept has changed. Existing Issues and implementation are not automatically re-scoped by this document.

## Next design decision

A separate `MVP_DESIGN.md` should specify **one testable, very small learning experience**: the first communicative capabilities and expressions, the simplest suitable setting and player routine, exact interactions and hints, how outcomes change the world, and the evidence needed to decide whether to expand. Those choices are intentionally not settled by this concept.
