class RandomSetupController < ApplicationController
  def new
    # Step 1: Setting description form
  end

  def create_setting
    setting_description = params[:setting_description].to_s.strip
    game_language = (normalized_locale(params[:game_language]) || I18n.default_locale).to_s

    if setting_description.blank?
      redirect_to new_random_setup_path, alert: t("controllers.random_setup.alerts.enter_setting", default: "Please describe your setting.")
      return
    end

    world_data, _tokens = RandomMode::WorldGeneratorService.generate(
      setting_description,
      game_language: game_language
    )

    cache_key = "random_setup:#{current_user.id}:#{SecureRandom.hex(8)}"
    Rails.cache.write(cache_key, { world_data: world_data, game_language: game_language }, expires_in: 1.hour)
    session[:random_setup_key] = cache_key

    redirect_to setting_random_setup_path
  rescue => e
    Rails.logger.error("[RandomSetupController#create_setting] #{e.message}")
    redirect_to new_random_setup_path, alert: t("controllers.random_setup.alerts.generation_error", default: "Could not generate world: %{message}", message: e.message)
  end

  def setting
    cached = load_cached_setup
    unless cached
      redirect_to new_random_setup_path, alert: t("controllers.random_setup.alerts.session_expired", default: "Session expired. Please start over.")
      return
    end
    @world_data = cached[:world_data]
    @game_language = cached[:game_language] || "en"
  end

  def create_hero
    hero_description = params[:hero_description].to_s.strip
    cached = load_cached_setup
    unless cached
      redirect_to new_random_setup_path, alert: t("controllers.random_setup.alerts.session_expired", default: "Session expired. Please start over.")
      return
    end

    if hero_description.blank?
      redirect_to setting_random_setup_path, alert: t("controllers.random_setup.alerts.enter_hero", default: "Please describe your hero.")
      return
    end

    hero_data, _tokens = RandomMode::HeroGeneratorService.generate(
      hero_description,
      world_context: cached[:world_data]["world_context"],
      game_language: cached[:game_language] || "en"
    )

    cached[:hero_data] = hero_data
    Rails.cache.write(session[:random_setup_key], cached, expires_in: 1.hour)

    redirect_to hero_random_setup_path
  rescue => e
    Rails.logger.error("[RandomSetupController#create_hero] #{e.message}")
    redirect_to new_random_setup_path, alert: t("controllers.random_setup.alerts.generation_error", default: "Could not generate hero: %{message}", message: e.message)
  end

  def hero
    cached = load_cached_setup
    unless cached && cached[:hero_data]
      redirect_to new_random_setup_path, alert: t("controllers.random_setup.alerts.session_expired", default: "Session expired. Please start over.")
      return
    end
    @world_data = cached[:world_data]
    @hero_data = cached[:hero_data]
  end

  def create_game
    cached = load_cached_setup
    unless cached && cached[:world_data] && cached[:hero_data]
      redirect_to new_random_setup_path, alert: t("controllers.random_setup.alerts.session_expired", default: "Session expired. Please start over.")
      return
    end

    game_language = cached[:game_language] || "en"
    selected_locale = normalized_locale(game_language) || I18n.default_locale
    I18n.locale = selected_locale
    session[:locale] = selected_locale.to_s

    game = GameService.start_random_game(
      world_data: cached[:world_data],
      hero_data: cached[:hero_data],
      game_language: game_language,
      user: current_user
    )

    # Clean up
    Rails.cache.delete(session.delete(:random_setup_key))

    redirect_to game_path(game, locale: selected_locale)
  rescue => e
    Rails.logger.error("[RandomSetupController#create_game] #{e.message}")
    redirect_to new_random_setup_path, alert: t("controllers.random_setup.alerts.could_not_start", default: "Could not start game: %{message}", message: e.message)
  end

  private

  def load_cached_setup
    key = session[:random_setup_key]
    return nil unless key
    Rails.cache.read(key)
  end
end
