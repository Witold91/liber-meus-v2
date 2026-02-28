class OutcomeResolutionService
  BASE_HEALTH = 100
  BASE_DANGER = 40
  BASE_MOMENTUM = 0
  BASE_ARC_INDEX = 1

  DIFFICULTY_THRESHOLD = { "easy" => 1, "medium" => 4, "hard" => 7 }.freeze

  HEALTH_LOSS = {
    "none"   => { "success" => 0, "partial" =>  0, "failure" =>  0 },
    "low"    => { "success" => 0, "partial" =>  0, "failure" =>  8 },
    "medium" => { "success" => 0, "partial" =>  5, "failure" => 18 },
    "high"   => { "success" => 0, "partial" => 12, "failure" => 35 }
  }.freeze

  DANGER_INCREASE = { "success" => 0, "partial" => 5, "failure" => 15 }.freeze

  MOMENTUM_DELTA = {
    "negative" => { "success" => -1, "partial" => -1, "failure" => -3 },
    "none"     => { "success" =>  0, "partial" =>  0, "failure" => -1 },
    "positive" => { "success" => +1, "partial" =>  0, "failure" => -2 },
    "major"    => { "success" => +2, "partial" => +1, "failure" => -2 }
  }.freeze

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
    danger     = intent[:danger]     || "none"
    impact     = intent[:impact]     || "positive"
    momentum   = world_state["momentum"].to_i

    roll, resolution_tag = determine_resolution(difficulty, momentum)
    health_loss = calculate_health_loss(danger, resolution_tag)

    world_state["health"] = [ (world_state["health"].to_i - health_loss), 0 ].max
    world_state["danger_level"] = [
      world_state["danger_level"].to_i + DANGER_INCREASE.fetch(resolution_tag, 0),
      100
    ].min
    world_state["momentum"] = update_momentum(momentum, resolution_tag, impact)

    game.update!(world_state: world_state)

    { resolution_tag: resolution_tag, health_loss: health_loss, roll: roll }
  end

  private

  def self.determine_resolution(difficulty, momentum)
    case difficulty
    when "trivial"   then return [ nil, "success" ]
    when "impossible" then return [ nil, "failure" ]
    end

    roll = rand(1..6)
    threshold = DIFFICULTY_THRESHOLD.fetch(difficulty, 4)
    total = roll + momentum
    tag = if total > threshold then "success"
          elsif total == threshold then "partial"
          else "failure"
          end
    [ roll, tag ]
  end

  def self.calculate_health_loss(danger, resolution_tag)
    HEALTH_LOSS.fetch(danger, HEALTH_LOSS["none"]).fetch(resolution_tag, 0)
  end

  def self.update_momentum(current, resolution_tag, impact)
    deltas = MOMENTUM_DELTA.fetch(impact, MOMENTUM_DELTA["positive"])
    delta  = deltas.fetch(resolution_tag, 0)
    [ [ current + delta, -3 ].max, 5 ].min
  end
end
