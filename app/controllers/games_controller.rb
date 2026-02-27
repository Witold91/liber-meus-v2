class GamesController < ApplicationController
  before_action :set_game
  before_action :set_game_locale

  def show
    @recent_turns = @game.turns.order(:turn_number)
    @scenario = ScenarioCatalog.find(@game.scenario_slug) if @game.arena_scenario?
    @presenter = Arena::ScenarioPresenter.new(@scenario, @game.world_state["chapter_number"] || 1, @game.world_state) if @scenario
    @stage_context = @presenter&.stage_context_for(@game.world_state["player_stage"], @game.world_state)
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
    @presenter = Arena::ScenarioPresenter.new(@scenario, @game.world_state["chapter_number"] || 1, @game.world_state) if @scenario
    @stage_context = @presenter&.stage_context_for(@game.world_state["player_stage"], @game.world_state)

    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: [
          turbo_stream.append("turn-log", partial: "games/turn", locals: { turn: turn }),
          turbo_stream.replace("stage-panel", partial: "games/stage_panel", locals: { stage_context: @stage_context, game: @game })
        ]
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

  private

  def set_game
    @game = Game.find(params[:id])
  end

  def set_game_locale
    locale = normalized_locale(@game.game_language)
    return unless locale

    I18n.locale = locale
    session[:locale] = locale.to_s
  end
end
