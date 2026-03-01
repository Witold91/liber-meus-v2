class SessionsController < ApplicationController
  skip_before_action :require_authentication, only: [ :new, :create ]

  def new
    redirect_to root_path if current_user
  end

  def create
    auth = request.env["omniauth.auth"]
    user = User.find_or_create_by!(google_uid: auth["uid"]) do |u|
      u.email = auth.dig("info", "email")
      u.name  = auth.dig("info", "name")
    end
    session[:user_id] = user.id
    redirect_to root_path
  end

  def destroy
    session.delete(:user_id)
    redirect_to sign_in_path
  end
end
