require "test_helper"

class ImpressionTest < ActiveSupport::TestCase
  test "valid impression" do
    impression = Impression.new(
      game: games(:prison_game),
      turn_number: 1,
      subject_type: "actor",
      subject_id: "guard_rodriguez",
      fact: "Rodriguez is grumpy",
      embedding: [0.1] * 1536
    )
    assert impression.valid?
  end

  test "invalid without fact" do
    impression = Impression.new(
      game: games(:prison_game),
      turn_number: 1,
      subject_type: "actor"
    )
    assert_not impression.valid?
    assert_includes impression.errors[:fact], "can't be blank"
  end

  test "invalid with wrong subject_type" do
    impression = Impression.new(
      game: games(:prison_game),
      turn_number: 1,
      subject_type: "invalid",
      fact: "some fact"
    )
    assert_not impression.valid?
    assert impression.errors[:subject_type].any?
  end

  test "accepts actor, scene, and memory subject types" do
    %w[actor scene memory].each do |type|
      impression = Impression.new(
        game: games(:prison_game),
        turn_number: 1,
        subject_type: type,
        fact: "some fact",
        embedding: [0.1] * 1536
      )
      assert impression.valid?, "Expected subject_type '#{type}' to be valid"
    end
  end

  test "belongs to game" do
    impression = impressions(:one)
    assert_equal games(:prison_game), impression.game
  end
end
