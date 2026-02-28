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

A scenario is chapter-based.

- A scenario has one or more `chapters`.
- Each chapter has its own stages, actors, objects, conditions, and events.
- Game flow uses:
  - global turn number (`turn_number`) across the whole game
  - chapter turn number (`chapter_turn`) that resets to `0` when a new chapter starts

### End condition behavior

Conditions are checked in this order:
1. Turn limit reached (`turn_limit`)
2. Health depleted
3. Chapter conditions

Supported condition `type` values in practice:
- `goal`: complete the game
- `danger`: fail the game
- `chapter_goal`: move to the next chapter if `next_chapter` exists

If `chapter_goal` is met and next chapter exists:
- current chapter is marked completed
- next chapter is created/activated
- world state for actors/objects resets to defaults of next chapter
- player stage is set to the first stage of next chapter
- `chapter_turn` resets to `0`
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

hero:
  slug: hero_slug
  name: "Hero Name"
  description: "Who the hero is."
  sex: male

chapters:
  - number: 1
    title: "Chapter Title"
    intro: |
      Intro text for prologue/transition.

    stages:
      - id: stage_a
        name: "Stage A"
        description: "What the place is."
        exits:
          - to: stage_b
            label: "Go to stage B"
            locked: true
          - to: finale
            label: "Exit"
            arena_exit: true

    actors:
      - id: npc_id
        name: "NPC Name"
        description: "Who this actor is."
        stage: stage_a
        status_options: [calm, alerted, dead]
        default_status: calm

    objects:
      - id: object_id
        name: "Object Name"
        stage: stage_a
        status_options: [intact, broken, taken]
        default_status: intact

    conditions:
      - id: chapter_done
        description: "Chapter completion condition"
        narrative: "Text shown in ending/transition turn."
        type: chapter_goal
        next_chapter: 2
        check: player_at_stage
        stage: finale

      - id: chapter_fail
        description: "Failure condition"
        narrative: "Failure text"
        type: danger
        check: actor_has_status
        actor: npc_id
        status: alerted

    events:
      - id: timed_event
        chapter_turn: 2
        condition:
          actor_status:
            id: npc_id
            status: calm
        action:
          type: actor_enters
          actor_id: npc_id
          stage: stage_b
          new_status: alerted
        description: "Optional event description"
```

## 4. Supported Condition Checks

Only these `check` values are evaluated:

- `player_at_stage`
  - required key: `stage`
- `actor_has_status`
  - required keys: `actor`, `status`
- `all_actors_have_status`
  - required keys: `actors` (array), `status`

If you use anything else, it will not trigger.

## 5. Supported Event Triggers and Actions

### Event timing keys

- `trigger_turn`: compares against global `turn_number`
- `chapter_turn`: compares against per-chapter turn number (recommended for chapter-scoped stories)

If both are present, `chapter_turn` wins.

### Event condition support

Only this condition shape is supported:

```yaml
condition:
  actor_status:
    id: actor_id
    status: expected_status
```

### Event action support

- `actor_enters`
  - moves actor to stage (`actor_moved_to`)
  - optionally updates status (`new_status`)

- `world_flag`
  - currently a no-op in state application (kept for future use)

## 6. Narrator Diff Contract (What AI Can Change)

The narrator service can output a `diff`. Supported keys:

- `actor_updates`: set actor status
- `object_updates`: set object status
- `actor_moved_to`: move actor to stage
- `player_moved_to`: move player to stage

Notes:
- Unknown object IDs in `object_updates` become `improvised_objects`.
- `offstage` is a valid stage target for actors and player.

## 7. Multi-Chapter Design Rules

For each chapter:

1. Include at least one stage.
2. Set an explicit chapter-ending condition:
   - `type: chapter_goal` for Acts 1..N-1
   - `type: goal` or `type: danger` for final act
3. Use `chapter_turn` events for per-act pacing.
4. Keep chapter stage IDs self-consistent (exits must target valid stage IDs in that chapter).

Important:
- `turn_limit` is global across the whole scenario, not per chapter.
- Choose a large enough `turn_limit` for multi-act stories.

## 8. Localization Overlay Rules

Create `config/scenarios/locales/<slug>.<locale>.yml`.

Overlay merging is partial. Supported localized keys:

Top-level:
- `title`, `description`, `world_context`, `narrator_style`

Hero:
- `hero.name`, `hero.description`

Chapter-level:
- `chapters[].title`, `chapters[].intro`

Stage-level:
- `stages[].name`, `stages[].description`
- `stages[].exits[].label` (matched by `to`)

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
- structural additions (new chapters/stages/actors/objects)

## 9. Authoring Workflow

1. Copy a scenario template (`prison_break.yml` or `romeo_juliet.yml`).
2. Fill top-level metadata (`slug`, title, etc.).
3. Define chapter 1 completely (stages, actors, objects, conditions, events).
4. Add later chapters and chapter goals.
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

- Using unsupported `check` names in `conditions`.
- Forgetting `next_chapter` on `chapter_goal`.
- Setting `turn_limit` too low for multi-act scenarios.
- Adding locale entries for keys the merger does not support.
- Referencing stage IDs in exits/events that do not exist in that chapter.
- Expecting `world_flag` events to mutate world state (they currently do not).

## 12. Quick Multi-Act Checklist

- [ ] Scenario has `chapters` with ascending `number`
- [ ] Every chapter has `stages`, `actors`, `objects`
- [ ] Acts 1..N-1 end via `type: chapter_goal`
- [ ] Final act has `goal` and/or `danger`
- [ ] Events use `chapter_turn` for chapter pacing
- [ ] `turn_limit` fits total scenario length
- [ ] Optional locale overlay added and merged keys are valid
