# Liber Meus v2

Arena-based interactive fiction engine. Players navigate multi-stage scenarios driven by two AI calls per turn — one to rate action difficulty, one to narrate the outcome. World state is deterministic math on top of AI prose; everything is defined in YAML.

## Stack

- **Ruby** 3.4.8 / **Rails** 8.1.2
- **PostgreSQL** (jsonb for world state and options payloads)
- **Hotwire** (Turbo Streams + Stimulus) for live turn appending
- **OpenAI API** — `gpt-4o-mini` by default for both AI calls
- **Minitest + Mocha** for tests

---

## Prerequisites

- Ruby 3.4.8 (via mise, rbenv, or asdf)
- PostgreSQL 14+
- Bundler 2.x

---

## Setup

### 1. Clone and install dependencies

```sh
git clone <repo-url>
cd liber-meus-v2
bundle install
```

### 2. Configure environment

```sh
cp .env.example .env
```

Edit `.env` and fill in your values (see [Environment Variables](#environment-variables) below).

### 3. Create and migrate the database

```sh
rails db:create db:migrate
```

### 4. Start the server

```sh
rails server
```

Visit `http://localhost:3000` — you'll land on the scenario selection screen.

---

## Environment Variables

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `OPENAI_API_KEY` | **Yes** | — | OpenAI API key for AI calls |
| `AI_DIFFICULTY_MODEL` | No | `gpt-4o-mini` | Model used for difficulty rating (call 1) |
| `AI_NARRATOR_MODEL` | No | `gpt-4o-mini` | Model used for narration (call 2) |
| `DB_HOST` | No | local socket | PostgreSQL host |
| `DB_PORT` | No | `5432` | PostgreSQL port |
| `DB_USERNAME` | No | current OS user | PostgreSQL username |
| `DB_PASSWORD` | No | _(empty)_ | PostgreSQL password |
| `DB_NAME` | No | `liber_meus_v2_production` | Production database name |
| `RAILS_MASTER_KEY` | Production | — | Decrypts `config/credentials.yml.enc` |

---

## Running Tests

```sh
rails test
```

Tests use Mocha for mocking the OpenAI client. All 59 tests run without a live API key.

---

## How It Works

### Turn Pipeline (`ArenaFlows::ContinueTurnFlow`)

Each player action goes through a 10-step pipeline:

1. Load scenario from `ScenarioCatalog`
2. Determine turn number
3. Fetch the active chapter
4. Build stage context (which actors/objects are in the player's current stage)
5. **AI call 1** — `DifficultyRatingService` rates the action as `easy`, `medium`, or `hard`
6. **Deterministic** — `OutcomeResolutionService` resolves to `success`, `partial`, or `failure` based on difficulty + momentum
7. **AI call 2** — `ArenaNarratorService` writes the narrative and returns a world-state diff
8. Apply the world-state diff via `Arena::WorldStateManager`
9. Apply any scenario events triggered by the turn number
10. Persist the turn, check end conditions

### Scenarios

Scenarios live in `config/scenarios/*.yml`. Each defines:

- **Stages** — named locations with exits (one can be `arena_exit: true`)
- **Actors** — NPCs with `stage`, `default_status`, and `status_options`
- **Objects** — items with the same structure
- **Conditions** — win/lose checks (`player_at_stage`, `actor_has_status`, etc.)
- **Events** — turn-triggered world changes

`ScenarioCatalog` loads all scenarios at boot via `config.to_prepare` and caches them in memory. Call `ScenarioCatalog.reload!` to refresh without restarting.

### World State

Stored as jsonb on the `games` table:

```json
{
  "health": 100,
  "danger_level": 40,
  "momentum": 0,
  "arc_index": 1,
  "player_stage": "cell",
  "scenario_slug": "prison_break",
  "chapter_number": 1,
  "actors": { "guard_rodriguez": { "stage": "cell_block", "status": "awake" } },
  "objects": { "loose_grate": { "stage": "cell", "status": "in_place" } }
}
```

`momentum` tracks consecutive successes/failures and shifts outcome probabilities for medium/hard actions.

---

## Project Structure

```
app/
  controllers/
    games_controller.rb          # show + continue (Turbo Stream)
    scenario_select_controller.rb
  models/
    hero.rb  game.rb  chapter.rb  turn.rb
  services/
    scenario_catalog.rb          # YAML cache
    game_service.rb              # routes to arena or non-arena flow
    difficulty_rating_service.rb
    arena_narrator_service.rb
    outcome_resolution_service.rb
    end_condition_checker.rb
    scenario_event_service.rb
    turn_persistence_service.rb
    arena/
      scenario_presenter.rb      # stage context builder
      world_state_manager.rb     # apply diffs
    arena_flows/
      start_scenario_flow.rb
      continue_turn_flow.rb
    game_flows/
      continue_turn_flow.rb      # stub for non-arena games
  javascript/controllers/
    game_controller.js           # immediate user message + form submit
    stage_panel_controller.js    # toggle stage panel
  views/
    scenario_select/show.html.erb
    games/show.html.erb
    games/_turn.html.erb
    games/_stage_panel.html.erb

config/
  scenarios/
    prison_break.yml

lib/prompts/
  difficulty_rating.txt
  arena_narrator.txt
```

---

## Adding a Scenario

1. Create `config/scenarios/your_scenario.yml` following the structure of `prison_break.yml`
2. The scenario is auto-loaded at boot (or call `ScenarioCatalog.reload!` in the console)
3. No code changes required — the engine adapts to any stage/actor/object layout

---

## Deployment

The project ships with a `Dockerfile` and Kamal configuration in `.kamal/`. For production:

```sh
RAILS_MASTER_KEY=<key> kamal deploy
```

Required env vars in production: `OPENAI_API_KEY`, `DATABASE_URL` (or individual `DB_*` vars), `RAILS_MASTER_KEY`.
