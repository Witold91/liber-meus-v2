class SessionsController < ApplicationController
  skip_before_action :require_authentication, only: [ :new, :create ]

  def new
    redirect_to root_path if current_user
  end

  def create
    auth = request.env["omniauth.auth"]
    email = auth.dig("info", "email")

    # Check for soft-deleted user by email first (preserves token balance across re-signups)
    user = User.find_by(email: email)
    if user
      user.update!(deleted_at: nil, google_uid: auth["uid"], name: auth.dig("info", "name"))
    else
      user = User.create!(
        google_uid: auth["uid"],
        email: email,
        name: auth.dig("info", "name")
      )
    end

    session[:user_id] = user.id
    redirect_to root_path
  end

  def destroy
    session.delete(:user_id)
    redirect_to sign_in_path
  end
end
