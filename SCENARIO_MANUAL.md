# Scenario Authoring Manual

This manual explains how to create playable scenarios for Liber Meus v2.

## 1. Where Scenarios Live

- Base scenarios: `config/scenarios/*.yml`
- Locale overlays: `config/scenarios/locales/<slug>.<locale>.yml`

Examples:
- `config/scenarios/prison_break.yml`
- `config/scenarios/romeo_juliet.yml`
- `config/scenarios/locales/prison_break.pl.yml`

## 2. Engine Model (Important)

A scenario is act-based.

- A scenario has one or more `acts`.
- Each act has its own scenes, actors, objects, conditions, and events.
- Game flow uses:
  - global turn number (`turn_number`) across the whole game
  - act turn number (`act_turn`) that resets to `0` when a new act starts

### End condition behavior

Conditions are checked in this order:
1. Turn limit reached (`turn_limit`)
2. Health depleted
3. Act conditions (top to bottom)

Supported condition `type` values:
- `goal`: complete the game
- `danger`: fail the game
- `act_goal`: move to the next act if `next_act` exists

If `act_goal` is met and the next act exists:
- current act is marked completed
- next act is created/activated
- actor/object **statuses carry over** from the previous act (e.g. a dead NPC stays dead); only actors/objects new to the act receive their `default_status`
- actor/object **scenes** are set to the new act's definitions (placement resets, status does not)
- actors/objects not defined in the new act are kept in world state so their statuses survive to later acts where they may reappear
- player scene is set to the first scene of the next act
- `act_turn` resets to `0`
- `fired_events` resets to `[]`
- game remains `active`

## 3. Full Scenario Schema

```yaml
slug: your_slug
title: "Scenario Title"
description: "One-line pitch."
turn_limit: 20
world_context: |
  Global setting constraints used by AI services.
narrator_style: |
  Writing style instructions for narrator.

theme:
  bg_color: "#0d0d0d"
  text_color: "#c8c8b4"
  accent_color: "#8ab4a0"
  font_family: "'Courier New', Courier, monospace"
  bg_image: ~

hero:
  slug: hero_slug
  name: "Hero Name"
  description: "Who the hero is."
  sex: male

acts:
  - number: 1
    title: "Act Title"
    intro: |
      Intro text shown as the opening prologue or act transition.

    scenes:
      - id: scene_a
        name: "Scene A"
        description: "What the place is."
        exits:
          - to: scene_b
            label: "Go to scene B"
            locked: true
          - to: finale
            label: "Exit"
            arena_exit: true

    actors:
      - id: npc_id
        name: "NPC Name"
        description: "Who this actor is."
        scene: scene_a
        status_options: [calm, alerted, dead]
        default_status: calm

    objects:
      - id: object_id
        name: "Object Name"
        scene: scene_a
        status_options: [intact, broken, taken]
        default_status: intact

    conditions:
      - id: act_done
        description: "Act completion condition"
        narrative: "Text shown in the ending/transition turn."
        type: act_goal
        next_act: 2
        check: player_at_scene
        scene: finale

      - id: act_fail
        description: "Failure condition"
        narrative: "Failure text"
        type: danger
        check: actor_has_status
        actor: npc_id
        status: alerted

    events:
      # Turn-triggered event (fires at a specific turn number)
      - id: timed_event
        act_turn: 2
        condition:
          actor_status:
            id: npc_id
            status: calm
        action:
          type: actor_enters
          actor_id: npc_id
          scene: scene_b
          new_status: alerted
        description: "Optional event description"

      # State-triggered event (fires when world state matches condition)
      - id: state_event
        trigger:
          actor_status:
            actor: npc_id
            status: alerted
        action:
          type: actor_enters
          actor_id: npc_id
          scene: scene_a
          new_status: dead
        description: "Fires once when npc_id becomes alerted."
```

## 4. Supported Condition Checks

Only these `check` values are evaluated in `conditions`:

- `player_at_scene`
  - required key: `scene`
- `actor_has_status`
  - required keys: `actor`, `status`
- `all_actors_have_status`
  - required keys: `actors` (array), `status`

If you use anything else, it will not trigger.

## 5. Supported Event Triggers and Actions

### Turn-triggered events

Use `act_turn` or `trigger_turn` to fire at a specific turn number:

- `act_turn`: compares against per-act turn number (recommended for act-scoped stories)
- `trigger_turn`: compares against global `turn_number`

Both support an optional `condition` block (see below).

```yaml
- id: guard_wakes
  act_turn: 3
  condition:
    actor_status:
      id: guard_rodriguez
      status: asleep
  action:
    type: actor_enters
    actor_id: guard_rodriguez
    scene: cell_block
    new_status: awake
```

Only this `condition` shape is supported:

```yaml
condition:
  actor_status:
    id: actor_id
    status: expected_status
```

### State-triggered events

Use a `trigger:` key (instead of `act_turn`/`trigger_turn`) to fire when the world state matches a condition. State-triggered events fire **exactly once** — they are tracked in `world_state["fired_events"]` and skipped on subsequent turns even if the condition remains true. `fired_events` is cleared on act transition.

Three trigger types are supported:

#### `actor_status` — fires when an actor reaches a given status

```yaml
- id: chen_alerted_by_rodriguez
  trigger:
    actor_status:
      actor: guard_rodriguez
      status: alerted
  action:
    type: actor_enters
    actor_id: guard_chen
    scene: cell_block
    new_status: alerted
  description: "Chen hears Rodriguez's shout and rushes to the cell block."
```

#### `object_status` — fires when an object reaches a given status

```yaml
- id: rope_noise_wakes_guard
  trigger:
    object_status:
      object: rope
      status: deployed
  action:
    type: actor_enters
    actor_id: guard_rodriguez
    scene: cell_block
    new_status: alerted
  description: "The scrape of a rope against concrete wakes the guard."
```

#### `player_at_scene` — fires when the player enters a given scene

```yaml
- id: rodriguez_spots_intruder
  trigger:
    player_at_scene: guard_station
  action:
    type: actor_enters
    actor_id: guard_rodriguez
    scene: guard_station
    new_status: alerted
  description: "Rodriguez spots the intruder the moment they enter."
```

### Event action support

- `actor_enters`
  - moves actor to a scene (`actor_moved_to`)
  - optionally updates status (`new_status`)

- `world_flag`
  - currently a no-op in state application (reserved for future use)

## 6. Narrator Diff Contract (What AI Can Change)

The narrator service outputs a `diff`. Supported keys:

- `actor_updates`: set actor status
  ```json
  { "actor_id": { "status": "new_status" } }
  ```
- `object_updates`: set object status and/or scene
  ```json
  { "object_id": { "status": "taken", "scene": "player_inventory" } }
  ```
- `actor_moved_to`: move actor to a scene
  ```json
  { "actor_id": "scene_id" }
  ```
- `player_moved_to`: move player to a scene (adjacency-validated)
  ```json
  "scene_id"
  ```

Notes:
- `player_moved_to` is silently ignored if the target scene is not adjacent to the player's current scene.
- Unknown actor/object IDs in diffs are resolved by slug if possible; unknown objects become `improvised_objects`.
- `"offstage"` is a valid scene target for actors.

### Player inventory

To place an item in the player's possession, set `"scene": "player_inventory"` in `object_updates`:

```json
{ "sword": { "status": "taken", "scene": "player_inventory" } }
```

To drop an item at a location, set `"scene": "scene_id"`. Improvised items (not in the scenario YAML) without a `scene` value are treated as carried by default.

## 7. Multi-Act Design Rules

For each act:

1. Include at least one scene.
2. Set an explicit act-ending condition:
   - `type: act_goal` for acts 1..N-1
   - `type: goal` or `type: danger` for the final act
3. Use `act_turn` events for per-act pacing.
4. Keep act scene IDs self-consistent (exits must target valid scene IDs within the same act).

### Switching the protagonist between acts

An act can optionally define its own `hero:` block. When the act transition fires, the game's hero is updated to the new one using the same `find_or_create_by!(slug:)` pattern as game start. If no `hero:` is defined on the new act, the previous hero carries forward unchanged.

```yaml
acts:
  - number: 1
    # no hero: → uses top-level hero
    scenes: ...

  - number: 2
    hero:
      slug: juliet
      name: "Juliet Capulet"
      description: "Clear-eyed and resolute, determined to control her own fate."
      sex: female
    intro: |
      ... written from Juliet's point of view ...
    scenes: ...
```

When using this feature:
- Update `world_context` at scenario level to reflect the shifting perspective.
- Rewrite the act `intro:` from the new protagonist's point of view.
- Health and momentum carry over between acts regardless of hero change.

### Cross-act status persistence

Actor and object statuses survive act transitions. If an NPC is killed or an object is broken in Act 1, that status carries forward to all later acts — even if the actor/object is absent from intermediate acts. Only actors/objects appearing for the first time in a new act receive their `default_status`.

This means you can rely on earlier-act outcomes mechanically:
- A dead NPC will still be dead when they reappear in a later act.
- A broken object stays broken.
- Scene placement (where an actor/object is located) resets to the new act's definition — only the status carries over.

Important:
- `turn_limit` is global across the whole scenario, not per act.
- Choose a large enough `turn_limit` for multi-act stories.

## 8. Localization Overlay Rules

Create `config/scenarios/locales/<slug>.<locale>.yml`.

Overlay merging is partial. Supported localized keys:

Top-level:
- `title`, `description`, `world_context`, `narrator_style`

Hero:
- `hero.name`, `hero.description`

Act-level:
- `acts[].title`, `acts[].intro`

Scene-level:
- `scenes[].name`, `scenes[].description`
- `scenes[].exits[].label` (matched by `to`)

Actor-level:
- `actors[].name`, `actors[].description`

Object-level:
- `objects[].name`

Condition-level:
- `conditions[].narrative`

Not merged by locale overlay:
- events
- status_options
- default_status
- structural additions (new acts/scenes/actors/objects)

## 9. Authoring Workflow

1. Copy a scenario template (`prison_break.yml` or `romeo_juliet.yml`).
2. Fill top-level metadata (`slug`, title, etc.).
3. Define act 1 completely (scenes, actors, objects, conditions, events).
4. Add later acts and act goals.
5. Add fail conditions (`danger`) for meaningful failure states.
6. Add optional locale overlay.
7. Reload and test.

## 10. Validation Commands

Reload scenarios in console:

```sh
bin/rails runner 'ScenarioCatalog.reload!; puts ScenarioCatalog.find!("your_slug")["title"]'
```

Run relevant tests:

```sh
bin/rails test test/services/scenario_catalog_test.rb
bin/rails test test/services/scenario_event_service_test.rb
bin/rails test test/services/arena_flows/continue_turn_flow_test.rb
```

Run full suite:

```sh
bin/rails test
```

## 11. Common Mistakes

- Using `stage` instead of `scene` for actor/object locations or condition/event keys.
- Using `chapter_turn` or `chapter_goal` — the correct keys are `act_turn` and `act_goal`.
- Using unsupported `check` names in `conditions`.
- Forgetting `next_act` on an `act_goal` condition.
- Setting `turn_limit` too low for multi-act scenarios.
- Adding locale entries for keys the merger does not support.
- Referencing scene IDs in exits/events that do not exist in that act.
- Expecting `world_flag` events to mutate world state (they currently do not).
- Assuming actor/object statuses reset between acts — statuses carry over; only scene placement resets.
- Giving state-triggered events no `id` — they need one to track firing in `fired_events`.

## 12. Quick Multi-Act Checklist

- [ ] Scenario has `acts` with ascending `number`
- [ ] Every act has `scenes`, `actors`, `objects`
- [ ] Acts 1..N-1 end via `type: act_goal`
- [ ] Final act has `goal` and/or `danger`
- [ ] Turn-triggered events use `act_turn` for act pacing
- [ ] State-triggered events have unique `id` values
- [ ] `turn_limit` fits total scenario length
- [ ] Cross-act status consequences are intentional (dead NPCs stay dead)
- [ ] Optional locale overlay added and merged keys are valid
