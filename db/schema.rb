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

ActiveRecord::Schema[8.1].define(version: 2026_03_14_191738) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"
  enable_extension "vector"

  create_table "acts", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "game_id", null: false
    t.integer "number", default: 1, null: false
    t.string "status", default: "active", null: false
    t.datetime "updated_at", null: false
    t.jsonb "world_state_snapshot", default: {}
    t.index ["game_id", "number"], name: "index_acts_on_game_id_and_number", unique: true
    t.index ["game_id"], name: "index_acts_on_game_id"
  end

  create_table "ai_request_logs", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "duration_ms", default: 0
    t.string "error_message"
    t.jsonb "messages", default: [], null: false
    t.string "model", null: false
    t.jsonb "response_body", default: {}
    t.string "service_name", null: false
    t.float "temperature"
    t.integer "tokens_used", default: 0
    t.datetime "updated_at", null: false
    t.index ["created_at"], name: "index_ai_request_logs_on_created_at"
    t.index ["service_name"], name: "index_ai_request_logs_on_service_name"
  end

  create_table "games", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "game_language", default: "en", null: false
    t.bigint "hero_id", null: false
    t.text "memory_summary"
    t.string "mode", default: "scenario", null: false
    t.string "scenario_slug"
    t.string "status", default: "active", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id"
    t.jsonb "world_state", default: {}, null: false
    t.index ["hero_id"], name: "index_games_on_hero_id"
    t.index ["status"], name: "index_games_on_status"
    t.index ["user_id"], name: "index_games_on_user_id"
  end

  create_table "heroes", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "description"
    t.text "llm_description"
    t.string "name", null: false
    t.string "sex"
    t.string "slug", null: false
    t.datetime "updated_at", null: false
    t.index ["slug"], name: "index_heroes_on_slug", unique: true
  end

  create_table "impressions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.vector "embedding", limit: 1536
    t.text "fact", null: false
    t.bigint "game_id", null: false
    t.string "subject_id"
    t.string "subject_type", null: false
    t.integer "turn_number", null: false
    t.datetime "updated_at", null: false
    t.index ["game_id", "subject_type", "subject_id"], name: "index_impressions_on_game_id_and_subject_type_and_subject_id"
    t.index ["game_id", "turn_number"], name: "index_impressions_on_game_id_and_turn_number"
    t.index ["game_id"], name: "index_impressions_on_game_id"
  end

  create_table "saves", force: :cascade do |t|
    t.integer "act_number", null: false
    t.datetime "created_at", null: false
    t.bigint "game_id", null: false
    t.bigint "hero_id", null: false
    t.string "label", null: false
    t.text "memory_summary"
    t.integer "turn_number", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.jsonb "world_state", default: {}, null: false
    t.index ["game_id", "created_at"], name: "index_saves_on_game_id_and_created_at"
    t.index ["game_id"], name: "index_saves_on_game_id"
    t.index ["user_id"], name: "index_saves_on_user_id"
  end

  create_table "turns", force: :cascade do |t|
    t.bigint "act_id", null: false
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
    t.index ["act_id"], name: "index_turns_on_act_id"
    t.index ["game_id", "turn_number"], name: "index_turns_on_game_id_and_turn_number", unique: true
    t.index ["game_id"], name: "index_turns_on_game_id"
  end

  create_table "users", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "deleted_at"
    t.string "email", null: false
    t.string "google_uid", null: false
    t.string "name"
    t.integer "tokens_remaining", default: 100000, null: false
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["google_uid"], name: "index_users_on_google_uid", unique: true
  end

  add_foreign_key "acts", "games"
  add_foreign_key "games", "heroes"
  add_foreign_key "games", "users"
  add_foreign_key "impressions", "games"
  add_foreign_key "saves", "games"
  add_foreign_key "saves", "heroes"
  add_foreign_key "saves", "users"
  add_foreign_key "turns", "acts"
  add_foreign_key "turns", "games"
end
