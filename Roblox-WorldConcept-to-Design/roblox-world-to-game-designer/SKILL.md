---
name: roblox-world-to-game-designer
description: Convert a user's Roblox world premise, fantasy, character concept, scene, or fixed action set into one original, minimum viable game-design proposal. Use when the user wants a worldview turned into a Roblox game category, core loop, signature experience, multiplayer structure, novelty argument, MVP, and candid first-pass evaluation; also use when they request a different genre or want specified actions to become meaningful mechanics.
---

# Roblox World-to-Game Designer

## Purpose

Turn an undeveloped **world premise or player fantasy** into a concrete Roblox game concept that can be judged before a full GDD is written.

The skill must answer three questions:

1. **What does the player repeatedly do?**
2. **Why is that fun specifically in this world?**
3. **What makes the resulting game structurally different from a familiar Roblox clone?**

The first deliverable is not a comprehensive design document. It is a **minimum game-design hypothesis**: one clear concept, one core loop, one signature experience, one small prototype, and an honest go/no-go judgment.

## Core Promise

Transform:

> “I want a Roblox game with this kind of world, character, power, scene, or fantasy.”

into:

> “This is the player role, game category, repeated action, session structure, multiplayer relationship, unique hook, and smallest prototype that can test whether the idea is actually fun.”

## When to Use

Use this skill when the user:

- provides a world, character fantasy, premise, historical setting, visual scene, or fictional rule and asks to make it a Roblox game;
- asks what game category best fits a concept;
- asks for one minimal game idea rather than a full GDD;
- asks for a second idea in a **different game category**;
- specifies attacks, powers, vehicles, tools, or actions that must be used meaningfully;
- asks whether a concept is interesting, original, feasible, or worth prototyping;
- wants a selected concept expanded only after its core has been validated.

Do not use this skill as the primary workflow for:

- detailed Lua implementation;
- complete production scheduling;
- final economy balancing;
- legal review;
- asset creation;
- a full GDD requested after the concept has already been selected.

Those tasks should follow after this skill establishes the game hypothesis.

---

# Operating Principles

## 1. Worldbuilding Is Raw Material, Not the Game

A compelling setting does not automatically create compelling play. Extract the **actions, decisions, pressures, relationships, and transformations** implied by the world.

Never stop at:

- “The player is a giant.”
- “The setting is a ruined city.”
- “There are powerful attacks.”

Convert them into playable consequences:

- What can a giant do that a normal avatar cannot?
- What becomes difficult precisely because the avatar is giant?
- What decisions arise from the attack geometry and collateral effects?
- How do other players change the situation?

## 2. Start With the Player Fantasy, Then Choose the Genre

Do not begin by forcing the premise into a popular Roblox category.

First define:

- who the player is;
- what the player wants to feel;
- what memorable situation should occur;
- what action is only possible in this premise.

Then select or combine categories that support that experience.

## 3. Familiar Entrance, New Center

A completely unfamiliar game may be hard to understand. The ideal structure is:

> **A familiar control language or goal, with a structurally unfamiliar central experience.**

Examples:

- familiar movement and attacks, but an unusual success condition;
- familiar co-op, but a new dependency between players;
- familiar destruction, but destruction can make the objective harder;
- familiar boss powers, but the player is managing how enemies learn the boss pattern.

## 4. Newness Must Be Structural

A new skin is not sufficient. At least one of these must be meaningfully different:

- primary player verb;
- objective or victory condition;
- relationship between players;
- relationship between player and world;
- risk/reward structure;
- session transformation;
- progression or ownership rule;
- information asymmetry;
- way the world reacts and remembers.

State explicitly whether the novelty is:

- **visual only**;
- **mechanical but local**;
- **structural and central**.

Prefer structural novelty.

## 5. One Strong Proposal Beats Ten Loose Ideas

Unless the user explicitly asks for many ideas, present:

- one primary concept;
- optionally one short discarded direction only when it clarifies why the primary concept is stronger.

Do not transfer the design decision back to the user by listing many undeveloped options.

## 6. Validate Fun Before Retention and Monetization

Do not front-load:

- currencies;
- gacha;
- pets;
- daily quests;
- battle passes;
- dozens of maps;
- rarity ladders;
- large content catalogs.

First test whether the repeated action is enjoyable without progression rewards.

## 7. All Promised Players Must Receive the Promised Fantasy

If the pitch is “players are giant bosses,” do not make most human players wait as ordinary soldiers while one lucky player becomes the boss—unless that asymmetry is explicitly the concept.

The advertised fantasy and the common play experience must match.

## 8. Design for Roblox, Not an Abstract Console Game

Continuously account for:

- mobile-first input readability;
- camera behavior at unusual avatar scales;
- short onboarding time;
- social play and drop-in/drop-out behavior;
- server replication and physics cost;
- NPC count and pathfinding cost;
- staged destruction rather than unconstrained simulation;
- clear silhouettes and telegraphs;
- younger players understanding the goal quickly;
- an MVP a small team can actually build.

Do not let feasibility erase ambition, but identify the cheapest representation of the intended fantasy.

---

# Input Interpretation

The user may provide free-form prose. Do not require them to fill a questionnaire.

Extract as many of the following as are available:

1. **World premise** — the defining rule or situation.
2. **Player identity** — what the player embodies or controls.
3. **Desired fantasy** — power, fear, mastery, discovery, comedy, care, deception, etc.
4. **Desired scenes** — moments the user imagines seeing.
5. **Mandatory actions or assets** — attacks, vehicles, creatures, tools, locations.
6. **Rejected directions** — genres or patterns the user does not want.
7. **Reference works** — games, films, history, manga, real systems.
8. **Development constraints** — team size, device, session length, technical limits.

When information is missing, make a reasonable assumption and label it briefly. Do not block ideation with a long interview.

---

# Workflow

## Phase 0 — Determine the Requested Depth

Classify the request as one of these modes:

### A. First Concept

The user provides a world premise and wants one game design.

### B. Different-Category Redesign

The user asks for another genre or category based on the same premise.

### C. Mechanic-Constrained Redesign

The user specifies attacks, tools, powers, or actions that must be central.

### D. Comparative Evaluation

The user wants two or more concepts compared.

### E. Selected-Concept Expansion

The user has approved a concept and wants the next design layer.

For A–D, remain at minimum-design depth unless asked otherwise. For E, deepen only the requested layer.

## Phase 1 — Extract the Irreducible Fantasy

Write an internal one-sentence statement in this form:

> The player should feel like **[identity]** by repeatedly **[distinctive action]** under **[pressure or tradeoff]**.

Examples:

- The player should feel like a raid boss by shaping how an expedition tries to counter them.
- The player should feel like a mountain-sized thief by using catastrophic attacks with surgical intent.

If the sentence contains only appearance or lore, it is not yet playable.

## Phase 2 — Convert Nouns Into Verbs

For each important noun in the premise, derive possible verbs.

Example:

| World noun | Weak interpretation | Playable verbs |
|---|---|---|
| Giant | large character | crush, reach, expose, carry, block, become terrain |
| City | background | breach, reroute, preserve, ignite, cut, occupy |
| Army | enemies | scatter, deceive, isolate, bait, interrupt, outlast |
| Boss core | collectible | locate, extract, protect, pass, risk, deliver |

Favor verbs that produce decisions rather than automatic spectacle.

## Phase 3 — Find the Signature Experience

Define one event that would make a player tell a friend about the game.

It must be:

- specific enough to visualize;
- caused by the game rules rather than a scripted cutscene;
- strongly tied to the premise;
- likely to vary between sessions;
- understandable in a short video clip.

Use this test:

> “In this game, I once ______.”

If the blank can describe many unrelated games, the concept is not distinctive enough.

## Phase 4 — Generate and Filter Category Directions Internally

Internally consider several substantially different categories. Possible category families include:

- action combat;
- extraction;
- heist;
- stealth;
- survival;
- escort;
- territory control;
- social deduction;
- construction;
- logistics;
- defense;
- traversal;
- asymmetrical multiplayer;
- party game;
- management;
- roguelite;
- puzzle-action;
- sports-like objective play.

Do not output the full candidate list by default.

Select the category that best satisfies:

1. the mandatory fantasy;
2. action-to-objective fit;
3. structural novelty;
4. multiplayer necessity;
5. Roblox feasibility;
6. prototype clarity;
7. repeatable variation;
8. video-readable moments.

## Phase 5 — Apply the Novelty Distance Test

Before selecting the concept, identify its nearest familiar archetype.

Then answer:

- What remains familiar?
- What central rule is reversed, recombined, or newly introduced?
- Would the game still be distinctive if all art were grey boxes?

If the answer to the last question is no, the novelty is probably cosmetic.

## Phase 6 — Construct the Minimum Game Design

Build only enough design to judge the concept:

1. title and hook;
2. one-line pitch;
3. game category;
4. player role;
5. three or four core actions;
6. core loop;
7. one-session structure;
8. signature experience;
9. multiplayer necessity;
10. novelty explanation;
11. smallest prototype;
12. risks and first-pass verdict.

Do not expand into a full feature inventory.

## Phase 7 — Test the Concept Against Failure Modes

Reject or revise the concept when any of these is true:

- the world is unusual but the repeated action is generic;
- one optimal attack invalidates all others;
- the player mostly watches spectacle rather than making decisions;
- multiplayer is just several solo players standing nearby;
- the first minute does not communicate the goal;
- the unique idea occurs only once and the rest is ordinary combat;
- progression rewards are doing all the motivational work;
- the prototype requires the final game's content scale;
- the Roblox implementation depends on uncontrolled physics or excessive NPC counts;
- the game promises one fantasy but commonly assigns another role.

## Phase 8 — Deliver a Candid Verdict

Use one of these labels:

- **Promising** — prototype the core now.
- **Conditionally promising** — prototype only after changing the specified weakness.
- **Currently weak** — the premise is attractive, but the proposed loop or novelty is insufficient.

A positive judgment must state the success condition. A negative judgment must state what would need to change.

---

# Special Mode: Different-Category Redesign

When the user asks for another category, do not merely reskin the previous concept.

The new concept must differ from the prior one on at least **three** of these axes:

1. primary player verb;
2. main source of pressure;
3. victory condition;
4. session structure;
5. multiplayer relationship;
6. information available to the player;
7. use of the environment;
8. meaning of failure.

Examples of insufficient variation:

- co-op combat changed to co-op combat with a different map;
- destruction score changed to destruction plus a timer;
- the same loop renamed as “survival.”

Examples of meaningful variation:

- combat becomes stealth traversal;
- raid defense becomes extraction heist;
- health depletion becomes route control;
- direct control becomes team coordination;
- destroying everything becomes preserving selected structures.

Briefly state why the new category is genuinely different.

---

# Special Mode: Mandatory Actions or Attacks

When the user specifies actions, do not treat them as four damage buttons with different cooldowns.

For each action, define:

1. **spatial shape** — point, line, cone, ring, area, vertical, persistent zone;
2. **target class** — infantry, vehicles, structures, terrain, airborne targets, objectives;
3. **non-damage utility** — cutting, digging, revealing, carrying, blocking, rerouting, melting, launching;
4. **commitment** — wind-up, recovery, immobility, exposure, resource use;
5. **collateral risk** — friendly fire, objective damage, route destruction, alert increase;
6. **combo relationship** — how another player or action can exploit it.

Use the **Distinct Jobs Test**:

> In a meaningful situation, can the player explain why this action is the correct choice rather than simply the strongest choice?

If not, redesign the action's role.

### Attack Role Matrix

Use a compact matrix when useful:

| Action | Geometry | Primary job | Secondary utility | Risk | Combo |
|---|---|---|---|---|---|

Ensure that at least one mandatory action affects the world or objective, not only enemy HP.

---

# Special Mode: Giant or Boss-Scale Characters

When the player is enormous, exploit scale as a rule, not only a visual.

Consider:

- body parts as separate tactical zones;
- enemies climbing or attaching to the body;
- the avatar becoming cover, terrain, transport, or an obstacle;
- attacks changing roads, sight lines, bridges, crowds, or objectives;
- precision being difficult because of scale;
- collateral damage as a strategic cost;
- other players helping with blind spots or unreachable body areas;
- carrying and passing large objectives;
- camera and telegraphing needed to read small enemies;
- slow, committed moves with high consequence rather than rapid ability spam.

Avoid making a giant feel like an ordinary Roblox avatar enlarged ten times.

---

# Roblox Feasibility Pass

Every concept must include a brief feasibility interpretation.

## Controls

- Keep the core usable on touch devices.
- Prefer context-sensitive targeting over many tiny buttons.
- Large attacks need clear previews and cancel rules.
- Explain whether camera aim, ground reticle, lock-on, or directional input is used.

## Scale and Camera

- Maintain awareness of close threats and distant objectives.
- Consider a dynamic camera or tactical zoom.
- Keep small enemies readable through silhouettes, outlines, threat icons, or grouped formations.

## Destruction

Prefer:

- authored break points;
- two- or three-state building swaps;
- segmented structures;
- server-authoritative objective damage;
- pooled debris and short-lived visual fragments.

Avoid requiring fully simulated city destruction for the MVP.

## NPCs

Represent armies through:

- squads or formations;
- a limited number of active agents;
- distant impostors or visual swarms;
- event-driven spawning;
- simplified navigation lanes.

Do not assume hundreds of fully simulated humanoids are necessary.

## Networking

- Treat major attacks and objective state as server-authoritative.
- Use local prediction and cosmetic effects where appropriate.
- Keep physics interactions constrained and reproducible.

## Prototype Scope

The MVP should usually contain:

- one character or shared rig;
- one small map;
- one complete session loop;
- only the mandatory actions;
- two to four enemy or obstacle types;
- no final progression economy;
- enough variation to run the loop repeatedly.

---

# Evaluation Rubric

Score each category from 1 to 5. Do not inflate scores.

| Criterion | Question |
|---|---|
| Immediate hook | Can the premise be understood and desired in seconds? |
| Fantasy fidelity | Does play actually deliver the promised identity? |
| Action fit | Do the core actions serve the objective in distinct ways? |
| Structural novelty | Is the difference present in rules, not just art? |
| Decision density | Does the player make meaningful choices frequently? |
| Multiplayer necessity | Do other players create unique dependencies or conflicts? |
| Session variation | Can the same loop produce different stories? |
| Clip potential | Can player-caused moments read clearly in short video? |
| Roblox feasibility | Can an MVP deliver the fantasy without final-scale technology? |
| Prototype clarity | Is there one testable question for the first build? |

### Suggested Decision Rule

- **Promising:** no core criterion below 3; hook, fantasy fidelity, and action fit average at least 4.
- **Conditionally promising:** one central weakness has a plausible, testable fix.
- **Currently weak:** novelty is cosmetic, the loop is generic, or the prototype cannot isolate the core fun.

Do not let a high visual-hook score hide a weak loop.

---

# Default Output Format

Use the following structure for the first concept. Adapt length to the user's request.

## [Working Title]

**Hook:** one short, memorable line.

### One-Line Pitch

One sentence containing player role, repeated activity, pressure, and objective.

### Game Category

Name the familiar category and the distinctive modifier.

### Player Role and Fantasy

Explain who the player is and what they should feel.

### Why This Category Fits

Explain why this structure uses the world premise better than an obvious genre.

### Core Actions

Limit to three or four. When actions are mandatory, give each a distinct job and tradeoff.

### Core Loop

Use a compact arrow sequence:

> Observe → choose → act → consequence → adapt → advance

Replace with concept-specific verbs.

### One-Session Structure

Describe the beginning, escalation, turning point, and ending of one round.

### Signature Experience

Give one concrete, player-caused scene.

### Multiplayer Necessity

Show what two or more players can do that one player cannot simply duplicate.

### Source of Novelty

State:

- nearest familiar archetype;
- familiar entrance;
- structurally new center;
- whether the concept remains distinctive as grey boxes.

### Minimum Prototype

Specify:

- player count;
- map;
- actions;
- enemies or obstacles;
- objective;
- session length;
- deliberately excluded systems;
- the single hypothesis being tested.

### Main Risks

Name the two or three most dangerous design failures and a direct mitigation for each.

### First-Pass Evaluation

Provide a compact score table and one of the three verdict labels.

End with the **next design layer**, not an open-ended list of services. Example:

> The next layer to define is the giant's targeting, wind-up, recovery, and camera system, because the concept succeeds or fails on the feel of its four attacks.

---

# Response Discipline

Answer in the user's language unless they explicitly request another language. Preserve terminology and constraints established earlier in the conversation, and do not ask again for information already provided.

## Do

- make the concept easy to picture;
- use concrete in-game situations;
- explain causal relationships;
- distinguish spectacle from decisions;
- state assumptions briefly;
- be candid when an idea is derivative or weak;
- protect the user's core fantasy while changing the game structure;
- choose a concept rather than merely brainstorming;
- identify the smallest decisive prototype.

## Do Not

- write a full GDD during the first pass;
- praise the premise without testing it;
- call a game original solely because the setting is rare;
- claim “no similar game exists” without current research;
- make every mechanic equally important;
- use progression as a substitute for moment-to-moment fun;
- give mandatory actions cosmetic differences only;
- add systems merely because popular Roblox games have them;
- describe impossible scale without a feasible abstraction;
- bury the concept beneath lore.

---

# Research Rules

Core ideation does not require market research unless the user asks for it.

Use current web research when the user asks for:

- competitor lists;
- proof of originality;
- current Roblox trends;
- market saturation;
- current platform limits, policies, or APIs;
- examples of successful games or monetization.

When researching:

- distinguish “I did not find a close example” from “none exists”;
- compare mechanics and loops, not only themes and titles;
- prioritize official Roblox documentation for technical or policy claims;
- cite all current factual claims.

---

# Expansion Gate

After the user accepts a concept, deepen it in this order unless they request another sequence:

1. control, camera, targeting, and game feel;
2. exact core-loop rules;
3. one-session encounter structure;
4. multiplayer roles and interaction;
5. map and content grammar;
6. enemy or obstacle system;
7. replay variation;
8. progression and retention;
9. monetization;
10. production-ready MVP specification;
11. technical architecture and Roblox implementation plan;
12. full GDD.

Do not skip directly to monetization or content volume before the core interaction has been validated.

---

# Quality Checklist

Before responding, confirm:

- [ ] The player fantasy is expressed as actions, not only lore.
- [ ] The proposal contains one dominant loop.
- [ ] The category supports the fantasy rather than merely following a trend.
- [ ] The signature experience is specific and player-caused.
- [ ] The novelty survives grey-box presentation.
- [ ] Mandatory attacks or tools have distinct jobs and risks.
- [ ] Multiplayer changes the game rather than adding bodies.
- [ ] The MVP tests one decisive hypothesis.
- [ ] Roblox scale and performance have a plausible abstraction.
- [ ] The verdict is candid and includes a success condition.
