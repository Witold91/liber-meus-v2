require "test_helper"

class ProfilesControllerTest < ActionDispatch::IntegrationTest
  setup do
    OmniAuth.config.test_mode = true
    @user = users(:one)
    OmniAuth.config.mock_auth[:google_oauth2] = OmniAuth::AuthHash.new(
      uid: @user.google_uid,
      info: { email: @user.email, name: @user.name }
    )
    get "/auth/google_oauth2/callback"
  end

  teardown do
    OmniAuth.config.test_mode = false
    OmniAuth.config.mock_auth[:google_oauth2] = nil
  end

  test "show displays profile" do
    get profile_path
    assert_response :success
    assert_select ".profile-value", text: @user.email
  end

  test "destroy soft-deletes and redirects to sign in" do
    delete profile_path
    assert_redirected_to sign_in_path(locale: "en")

    @user.reload
    assert @user.deleted?
    assert_equal 100_000, @user.tokens_remaining
  end

  test "destroy nullifies games and destroys saves" do
    game = Game.create!(
      hero: heroes(:romeo),
      scenario_slug: "prison_break",
      world_state: {},
      status: "active",
      user: @user
    )
    Save.create!(
      game: game,
      user: @user,
      hero: heroes(:romeo),
      act_number: 1,
      turn_number: 1,
      label: "test",
      world_state: {}
    )

    saves_before = @user.saves.count
    assert saves_before > 0

    delete profile_path

    assert_equal 0, Save.where(user_id: @user.id).count

    assert_nil game.reload.user_id
  end
end
