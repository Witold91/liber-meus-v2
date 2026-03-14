class ProfilesController < ApplicationController
  def show
    @user = current_user
  end

  def destroy
    user = current_user
    user.games.update_all(user_id: nil)
    user.saves.destroy_all
    user.update!(deleted_at: Time.current)
    session.delete(:user_id)
    redirect_to sign_in_path, notice: t("controllers.profiles.notices.account_deleted")
  end
end
