class OutcomeResolutionService
  BASE_HEALTH = 100
  BASE_DANGER = 40
  BASE_MOMENTUM = 0
  BASE_ARC_INDEX = 1

  DIFFICULTY_THRESHOLD = { "easy" => 1, "medium" => 4, "hard" => 7 }.freeze
  HEALTH_LOSS = { "easy" => 0, "medium" => 10, "hard" => 25 }.freeze
  DANGER_INCREASE = { "success" => 0, "partial" => 5, "failure" => 15 }.freeze

  def self.initial_state
    {
      "health" => BASE_HEALTH,
      "danger_level" => BASE_DANGER,
      "momentum" => BASE_MOMENTUM,
      "arc_index" => BASE_ARC_INDEX,
      "player_stage" => nil,
      "actors" => {},
      "objects" => {},
      "player_inventory" => {}
    }
  end

  def self.resolve(game, action, turn_number, intent)
    world_state = game.world_state.dup
    difficulty = intent[:difficulty] || "medium"
    momentum = world_state["momentum"].to_i

    roll = rand(1..6)
    relevant = intent.fetch(:relevant, true)
    resolution_tag = determine_resolution(difficulty, momentum, roll)
    resolution_tag = "partial" if resolution_tag == "success" && !relevant
    health_loss = calculate_health_loss(difficulty, resolution_tag)

    world_state["health"] = [ (world_state["health"].to_i - health_loss), 0 ].max
    world_state["danger_level"] = [
      world_state["danger_level"].to_i + DANGER_INCREASE.fetch(resolution_tag, 0),
      100
    ].min
    world_state["momentum"] = update_momentum(momentum, resolution_tag)

    game.update!(world_state: world_state)

    { resolution_tag: resolution_tag, health_loss: health_loss, roll: roll }
  end

  private

  def self.determine_resolution(difficulty, momentum, roll)
    threshold = DIFFICULTY_THRESHOLD.fetch(difficulty, 4)
    total = roll + momentum
    if total > threshold
      "success"
    elsif total == threshold
      "partial"
    else
      "failure"
    end
  end

  def self.calculate_health_loss(difficulty, resolution_tag)
    base = HEALTH_LOSS.fetch(difficulty, 10)
    case resolution_tag
    when "success" then 0
    when "partial" then base / 2
    when "failure" then base
    else 0
    end
  end

  def self.update_momentum(current, resolution_tag)
    delta = case resolution_tag
    when "success" then 1
    when "partial" then 0
    when "failure" then -2
    else 0
    end
    [ [ current + delta, -3 ].max, 5 ].min
  end
end
