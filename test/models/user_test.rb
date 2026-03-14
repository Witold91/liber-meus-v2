require "test_helper"

class UserTest < ActiveSupport::TestCase
  test "deduct_tokens! reduces balance" do
    user = users(:one)
    user.deduct_tokens!(500)
    assert_equal 99_500, user.reload.tokens_remaining
  end

  test "deduct_tokens! floors at zero" do
    user = users(:one)
    user.update!(tokens_remaining: 100)
    user.deduct_tokens!(500)
    assert_equal 0, user.reload.tokens_remaining
  end

  test "out_of_tokens? returns true when zero" do
    user = users(:broke)
    assert user.out_of_tokens?
  end

  test "out_of_tokens? returns false when positive" do
    user = users(:one)
    refute user.out_of_tokens?
  end

  test "deleted? checks deleted_at" do
    user = users(:one)
    refute user.deleted?

    user.update!(deleted_at: Time.current)
    assert user.deleted?
  end

  test "tokens_remaining cannot be negative" do
    user = users(:one)
    user.tokens_remaining = -1
    refute user.valid?
  end
end
