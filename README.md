# Liber Meus v2

Arena-based interactive fiction engine. Players navigate multi-act scenarios driven by two AI calls per turn — one to rate action difficulty, one to narrate the outcome. World state is deterministic math on top of AI prose; everything is defined in YAML.

## Stack

- **Ruby** 3.4.8 / **Rails** 8.1.2
- **PostgreSQL** + **pgvector** (jsonb for world state, vector embeddings for narrative impressions)
- **Hotwire** (Turbo Streams + Stimulus) for live turn appending
- **OpenAI API** — `gpt-4o-mini` by default for both AI calls
- **Minitest + Mocha** for tests

---

## Prerequisites

- Ruby 3.4.8 (via mise, rbenv, or asdf)
- PostgreSQL 14+ with **pgvector** extension
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

Visit `http://localhost:3000` — you'll land on the game index screen.

---

## Environment Variables

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `OPENAI_API_KEY` | **Yes** | — | OpenAI API key for AI calls |
| `AI_DIFFICULTY_MODEL` | No | `gpt-4o-mini` | Model used for difficulty rating (call 1) |
| `AI_NARRATOR_MODEL` | No | `gpt-4o-mini` | Model used for narration (call 2) |
| `AI_EMBEDDING_MODEL` | No | `text-embedding-3-small` | Model used for narrative impression embeddings |
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

Tests use Mocha for mocking the OpenAI client. All 171 tests run without a live API key.

---

## How It Works

### Turn Pipeline (`ArenaFlows::ContinueTurnFlow`)

Each player action goes through a multi-step pipeline:

1. Load scenario from `ScenarioCatalog`
2. Determine turn number
3. Fetch the active act
4. Build scene context (which actors/objects are in the player's current scene)
5. Retrieve established facts (vector impressions) for narrator context
6. **AI call 1** — `DifficultyRatingService` rates the action as `easy`, `medium`, or `hard`
7. **Deterministic** — `OutcomeResolutionService` resolves to `success`, `partial`, or `failure` based on difficulty + momentum
8. **AI call 2** — `ArenaNarratorService` writes the narrative and returns a world-state diff
9. Store narrative impressions via `ImpressionService`
10. Apply the world-state diff via `Arena::WorldStateManager`
11. Apply any scenario events triggered by the turn number
12. Persist the turn, check end conditions

### Scenarios

Scenarios live in `config/scenarios/*.yml`. Each defines:

- **Acts** — numbered story arcs, each containing scenes
- **Scenes** — named locations with exits (one can be `arena_exit: true`)
- **Actors** — NPCs with `scene`, `default_status`, and `status_options`
- **Objects** — items with the same structure
- **Conditions** — win/lose checks (`player_at_scene`, `actor_has_status`, etc.)
- **Events** — turn-triggered or state-triggered world changes

`ScenarioCatalog` loads all scenarios at boot via `config.to_prepare` and caches them in memory. Call `ScenarioCatalog.reload!` to refresh without restarting.

### World State

Stored as jsonb on the `games` table:

```json
{
  "health": 100,
  "momentum": 0,
  "player_scene": "tavern_main",
  "actors": { "barkeep": { "scene": "tavern_main", "status": "working" } },
  "objects": { "ruby": { "scene": "tavern_vault", "status": "locked" } },
  "improvised_objects": {}
}
```

`momentum` tracks consecutive successes/failures and shifts outcome probabilities for medium/hard actions.

### Narrative Impressions (pgvector)

In long games, the AI narrator can lose track of established facts about characters and locations. To fix this, the engine extracts short factual "impressions" from each narrator response and stores them with vector embeddings in PostgreSQL via pgvector.

Before each turn's AI calls, relevant impressions are retrieved via hybrid search (deterministic by scene/actor ID + semantic nearest-neighbor by action text) and injected as "ESTABLISHED FACTS" into the prompts.

- **`ImpressionService.store!`** — extracts impressions from narrator JSON, batch-embeds via `EmbeddingService`, persists to `impressions` table
- **`ImpressionService.retrieve`** — hybrid retrieval (max 10 facts), excludes memory-type entries
- **`EmbeddingService`** — thin wrapper around the OpenAI embeddings endpoint (model: `AI_EMBEDDING_MODEL`)
- Impressions are tagged by `subject_type` (`actor`, `scene`, `memory`) and `subject_id`
- Non-fatal: if the embedding API is down, the game continues without impressions

---

## Project Structure

```
app/
  controllers/
    games_controller.rb              # index, show, continue (Turbo Stream), replay_act, save/load
    scenario_select_controller.rb    # scenario picker
    random_setup_controller.rb       # random game creation wizard
    profiles_controller.rb           # user profile
    sessions_controller.rb           # Google OAuth sign-in
  models/
    hero.rb  game.rb  act.rb  turn.rb
    impression.rb  save.rb  user.rb  a_i_request_log.rb
  services/
    ai_client.rb                     # OpenAI API wrapper
    scenario_catalog.rb              # YAML cache
    game_service.rb                  # routes to arena or non-arena flow
    difficulty_rating_service.rb
    arena_narrator_service.rb
    outcome_resolution_service.rb
    end_condition_checker.rb
    scenario_event_service.rb
    turn_persistence_service.rb
    embedding_service.rb
    impression_service.rb
    memory_compression_service.rb
    arena/
      scenario_presenter.rb          # scene context builder
      world_state_manager.rb         # apply diffs
    arena_flows/
      start_scenario_flow.rb
      continue_turn_flow.rb
      replay_act_flow.rb
      save_game_flow.rb
      load_save_flow.rb
    game_flows/
      continue_turn_flow.rb          # stub for non-arena games
  javascript/controllers/
    game_controller.js               # immediate user message + form submit
    scene_panel_controller.js        # toggle scene panel
  views/
    games/
      index.html.erb
      show.html.erb
      _turn.html.erb
      _scene_panel.html.erb
      _hero_stats.html.erb
      _save_panel.html.erb
      _inventory.html.erb
      _act_replay.html.erb
    scenario_select/show.html.erb
    random_setup/new.html.erb
    profiles/show.html.erb
    sessions/new.html.erb

config/
  scenarios/
    tavern_heist.yml
    romeo_juliet.yml
    camillas_way_home.yml

lib/prompts/
  difficulty_rating.txt
  arena_narrator.txt
  arena_prologue.txt
  arena_epilogue.txt
  memory_compression.txt
  random_narrator.txt
  random_hero_generator.txt
  random_world_generator.txt
  random_scene_generator.txt
```

---

## Routes

All game routes are scoped under an optional locale prefix (`/en/...` or `/pl/...`).

| Method | Path | Controller#Action |
|--------|------|-------------------|
| GET | `/` | `games#index` |
| GET | `/scenario_select` | `scenario_select#show` |
| POST | `/scenario_select` | `scenario_select#create` |
| GET | `/random_setup/new` | `random_setup#new` |
| GET | `/games/:id` | `games#show` |
| POST | `/games/:id/continue` | `games#continue` (Turbo Stream) |
| POST | `/games/:id/replay_act` | `games#replay_act` |
| POST | `/games/:id/save_game` | `games#save_game` |
| POST | `/games/:id/load_save` | `games#load_save` |
| GET | `/profile` | `profiles#show` |
| GET | `/sign_in` | `sessions#new` |

---

## Adding a Scenario

1. Create `config/scenarios/your_scenario.yml` following the structure of `tavern_heist.yml`
2. The scenario is auto-loaded at boot (or call `ScenarioCatalog.reload!` in the console)
3. No code changes required — the engine adapts to any scene/actor/object layout

For full authoring details (multi-act scenarios, endings, events, localization, and validation), see [`SCENARIO_MANUAL.md`](SCENARIO_MANUAL.md).

---

## Deployment

The project ships with a `Dockerfile` and Kamal configuration in `.kamal/`. For production:

```sh
RAILS_MASTER_KEY=<key> kamal deploy
```

Required env vars in production: `OPENAI_API_KEY`, `DATABASE_URL` (or individual `DB_*` vars), `RAILS_MASTER_KEY`.
