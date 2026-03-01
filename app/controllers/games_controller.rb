class GamesController < ApplicationController
  DEFAULT_THEME = {
    "bg_color"     => "#0d0d0d",
    "text_color"   => "#c8c8b4",
    "accent_color" => "#8ab4a0",
    "font_family"  => "'Courier New', Courier, monospace",
    "bg_image"     => nil
  }.freeze

  before_action :set_game
  before_action :set_game_locale
  before_action :set_theme

  def show
    @recent_turns = @game.turns.order(:turn_number)
    @scenario = ScenarioCatalog.find(@game.scenario_slug) if @game.arena_scenario?
    @presenter = Arena::ScenarioPresenter.new(@scenario, @game.world_state["act_number"] || 1, @game.world_state) if @scenario
    @scene_context = @presenter&.scene_context_for(@game.world_state["player_scene"], @game.world_state)
    @acts_for_replay = @game.acts.order(:number)
  end

  def continue
    action = params[:action_text].to_s.strip

    if action.blank?
      respond_to do |format|
        message = t("controllers.games.alerts.enter_action")
        format.turbo_stream { render turbo_stream: turbo_stream.replace("flash", partial: "shared/flash", locals: { message: message }) }
        format.html { redirect_to game_path(@game), alert: message }
      end
      return
    end

    turn = GameService.continue_turn(game: @game, action: action)
    @game.reload

    @scenario = ScenarioCatalog.find(@game.scenario_slug) if @game.arena_scenario?
    @presenter = Arena::ScenarioPresenter.new(@scenario, @game.world_state["act_number"] || 1, @game.world_state) if @scenario
    @scene_context = @presenter&.scene_context_for(@game.world_state["player_scene"], @game.world_state)
    ending_turn = @game.turns.ending.find_by(turn_number: turn.turn_number + 1)
    prologue_turn = @game.turns.find_by(turn_number: turn.turn_number + 2)

    respond_to do |format|
      format.turbo_stream do
        streams = [
          turbo_stream.append("turn-log", partial: "games/turn", locals: { turn: turn }),
          turbo_stream.replace("turn-counter", html: helpers.content_tag(:span, t("views.games.turn", number: turn.turn_number), class: "console-status", id: "turn-counter")),
          turbo_stream.replace("hero-stats", partial: "games/hero_stats", locals: { game: @game }),
          turbo_stream.replace("inventory-panel", partial: "games/inventory", locals: { inventory: @scene_context&.dig(:inventory) || [] }),
          turbo_stream.replace("scene-panel", partial: "games/scene_panel", locals: { scene_context: @scene_context, game: @game })
        ]
        streams << turbo_stream.append("turn-log", partial: "games/turn", locals: { turn: ending_turn }) if ending_turn
        streams << turbo_stream.append("turn-log", partial: "games/turn", locals: { turn: prologue_turn }) if prologue_turn&.options_payload&.dig("prologue")
        render turbo_stream: streams
      end
      format.html { redirect_to game_path(@game) }
    end
  rescue AIConnectionError
    message = t("controllers.games.alerts.ai_connection_error")
    respond_to do |format|
      format.turbo_stream { render turbo_stream: turbo_stream.replace("flash", partial: "shared/flash", locals: { message: message }) }
      format.html { redirect_to game_path(@game), alert: message }
    end
  rescue => e
    Rails.logger.error("[GamesController#continue] #{e.message}\n#{e.backtrace.first(5).join("\n")}")
    message = t("controllers.games.alerts.error", message: e.message)
    respond_to do |format|
      format.turbo_stream { render turbo_stream: turbo_stream.replace("flash", partial: "shared/flash", locals: { message: message }) }
      format.html { redirect_to game_path(@game), alert: message }
    end
  end

  def replay_act
    act_number = params[:act_number].to_i
    ArenaFlows::ReplayActFlow.call(game: @game, act_number: act_number)
    redirect_to game_path(@game)
  rescue ArgumentError => e
    redirect_to game_path(@game), alert: e.message
  rescue => e
    Rails.logger.error("[GamesController#replay_act] #{e.message}\n#{e.backtrace.first(5).join("\n")}")
    redirect_to game_path(@game), alert: t("controllers.games.alerts.error", message: e.message)
  end

  private

  def set_game
    @game = Game.find(params[:id])
  end

  def set_theme
    scenario = ScenarioCatalog.find(@game.scenario_slug)
    raw_theme = scenario&.dig("theme") || {}
    @theme = DEFAULT_THEME.merge(raw_theme)
  end

  def set_game_locale
    locale = normalized_locale(@game.game_language)
    return unless locale

    I18n.locale = locale
    session[:locale] = locale.to_s
  end
end
