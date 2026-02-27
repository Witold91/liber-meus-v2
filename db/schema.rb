# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_02_27_163956) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "chapters", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "game_id", null: false
    t.integer "number", default: 1, null: false
    t.string "status", default: "active", null: false
    t.datetime "updated_at", null: false
    t.index ["game_id", "number"], name: "index_chapters_on_game_id_and_number", unique: true
    t.index ["game_id"], name: "index_chapters_on_game_id"
  end

  create_table "games", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "game_language", default: "en", null: false
    t.bigint "hero_id", null: false
    t.string "scenario_slug"
    t.string "status", default: "active", null: false
    t.datetime "updated_at", null: false
    t.jsonb "world_state", default: {}, null: false
    t.index ["hero_id"], name: "index_games_on_hero_id"
    t.index ["status"], name: "index_games_on_status"
  end

  create_table "heroes", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "description"
    t.string "name", null: false
    t.string "sex"
    t.string "slug", null: false
    t.datetime "updated_at", null: false
    t.index ["slug"], name: "index_heroes_on_slug", unique: true
  end

  create_table "turns", force: :cascade do |t|
    t.bigint "chapter_id", null: false
    t.text "content"
    t.datetime "created_at", null: false
    t.bigint "game_id", null: false
    t.text "llm_memory"
    t.string "option_selected"
    t.jsonb "options_payload", default: {}, null: false
    t.string "resolution_tag"
    t.integer "tokens_used", default: 0, null: false
    t.integer "turn_number", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["chapter_id"], name: "index_turns_on_chapter_id"
    t.index ["game_id", "turn_number"], name: "index_turns_on_game_id_and_turn_number"
    t.index ["game_id"], name: "index_turns_on_game_id"
  end
end
