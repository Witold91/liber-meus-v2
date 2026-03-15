class ScenarioSelectController < ApplicationController
  PER_PAGE = 10

  def show
    all_scenarios = ScenarioCatalog.visible
    @page = [ params.fetch(:page, 1).to_i, 1 ].max
    @scenarios = all_scenarios.slice((@page - 1) * PER_PAGE, PER_PAGE) || []
    @has_next_page = all_scenarios.length > @page * PER_PAGE
  end

  def create
    if current_user.out_of_tokens?
      redirect_to scenario_select_path, alert: t("controllers.scenario_select.alerts.out_of_tokens")
      return
    end

    scenario_slug = params[:scenario_slug]
    selected_locale = normalized_locale(params[:game_language]) || I18n.default_locale
    I18n.locale = selected_locale
    session[:locale] = selected_locale.to_s
    game_language = selected_locale.to_s

    unless ScenarioCatalog.find(scenario_slug)
      redirect_to scenario_select_path, alert: t("controllers.scenario_select.alerts.unknown_scenario")
      return
    end

    game = GameService.start_game(
      scenario_slug: scenario_slug,
      game_language: game_language,
      user: current_user
    )

    redirect_to game_path(game, locale: selected_locale)
  rescue => e
    Rails.logger.error("[ScenarioSelectController] #{e.message}")
    redirect_to scenario_select_path, alert: t("controllers.scenario_select.alerts.could_not_start", message: e.message)
  end
end
