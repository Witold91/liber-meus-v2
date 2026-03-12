class OutcomeResolutionService
  BASE_HEALTH = 100
  BASE_MOMENTUM = 0

  DIFFICULTY_THRESHOLD = { "easy" => 1, "medium" => 4, "hard" => 7 }.freeze

  HEALTH_LOSS = {
    "none"   => { "success" => 0, "partial" =>  0, "failure" =>  0 },
    "low"    => { "success" => 0, "partial" =>  0, "failure" =>  8 },
    "medium" => { "success" => 0, "partial" =>  5, "failure" => 18 },
    "high"   => { "success" => 0, "partial" => 12, "failure" => 35 }
  }.freeze

  HEALTH_GAIN = {
    "success" => 15,
    "partial" =>  8,
    "failure" =>  0
  }.freeze

  MOMENTUM_DELTA = {
    "negative" => { "success" => -1, "partial" => -1, "failure" => -1 },
    "none"     => { "success" =>  0, "partial" =>  0, "failure" =>  0 },
    "positive" => { "success" => +1, "partial" =>  0, "failure" => -1 },
    "major"    => { "success" => +2, "partial" => +1, "failure" => -1 }
  }.freeze

  def self.initial_state
    {
      "health" => BASE_HEALTH,
      "momentum" => BASE_MOMENTUM,
      "player_scene" => nil,
      "actors" => {},
      "objects" => {},
      "improvised_objects" => {}
    }
  end

  def self.resolve(game, action, turn_number, intent)
    world_state = game.world_state.dup
    difficulty = intent[:difficulty] || "medium"
    danger     = intent[:danger]     || "none"
    impact     = intent[:impact]     || "positive"
    momentum   = world_state["momentum"].to_i

    healing    = intent[:healing] || false

    roll, resolution_tag = determine_resolution(difficulty, momentum)
    health_loss  = calculate_health_loss(danger, resolution_tag)
    health_gain  = healing ? calculate_health_gain(resolution_tag) : 0

    new_health = world_state["health"].to_i - health_loss + health_gain
    world_state["health"] = [ [ new_health, 0 ].max, BASE_HEALTH ].min
    world_state["momentum"] = update_momentum(momentum, resolution_tag, impact)

    game.update!(world_state: world_state)

    { resolution_tag: resolution_tag, health_loss: health_loss, health_gain: health_gain, roll: roll }
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

  def self.calculate_health_gain(resolution_tag)
    HEALTH_GAIN.fetch(resolution_tag, 0)
  end

  def self.update_momentum(current, resolution_tag, impact)
    deltas = MOMENTUM_DELTA.fetch(impact, MOMENTUM_DELTA["positive"])
    delta  = deltas.fetch(resolution_tag, 0)
    [ [ current + delta, -1 ].max, 2 ].min
  end
end
