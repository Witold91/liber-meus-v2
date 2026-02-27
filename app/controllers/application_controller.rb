class ApplicationController < ActionController::Base
  before_action :set_locale

  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  def default_url_options
    { locale: I18n.locale }
  end

  private

  def set_locale
    requested_locale = params[:locale] || session[:locale]
    I18n.locale = normalized_locale(requested_locale) || I18n.default_locale
    session[:locale] = I18n.locale.to_s
  end

  def normalized_locale(value)
    locale = value.to_s.presence&.to_sym
    return if locale.blank?
    return locale if I18n.available_locales.include?(locale)
  end
end
