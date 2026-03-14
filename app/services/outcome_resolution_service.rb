class OutcomeResolutionService
  BASE_HEALTH = 100
  BASE_MOMENTUM = 0

  DIFFICULTY_THRESHOLD = { "easy" => 1, "medium" => 4, "hard" => 7 }.freeze

  # Damage dice: number of d6 to roll for health loss
  DAMAGE_DICE = {
    "none"   => { "success" => 0, "partial" => 0, "failure" => 0 },
    "low"    => { "success" => 0, "partial" => 1, "failure" => 2 },
    "medium" => { "success" => 0, "partial" => 2, "failure" => 4 },
    "high"   => { "success" => 0, "partial" => 4, "failure" => 8 }
  }.freeze

  HEALING_DICE = { "success" => 4, "partial" => 2, "failure" => 0 }.freeze

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

    stance     = intent[:stance] || intent[:exposure] || "active"
    healing    = intent[:healing] || false

    roll, resolution_tag = determine_resolution(difficulty, momentum)
    damage = roll_damage(danger, resolution_tag, stance)
    heal = healing ? roll_healing(resolution_tag) : { dice: [], total: 0 }

    new_health = world_state["health"].to_i - damage[:total] + heal[:total]
    world_state["health"] = [ [ new_health, 0 ].max, BASE_HEALTH ].min
    world_state["momentum"] = update_momentum(momentum, resolution_tag, impact)

    game.update!(world_state: world_state)

    { resolution_tag: resolution_tag, health_loss: damage[:total], damage_dice: damage[:dice], health_gain: heal[:total], healing_dice: heal[:dice], roll: roll }
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

  def self.roll_damage(danger, resolution_tag, stance = "active")
    effective_resolution = case stance
    when "safe", "none" then return { dice: [], total: 0 }
    when "exposed", "undefended" then "failure"
    else resolution_tag
    end

    num_dice = DAMAGE_DICE.fetch(danger, DAMAGE_DICE["none"]).fetch(effective_resolution, 0)
    return { dice: [], total: 0 } if num_dice == 0

    dice = Array.new(num_dice) { rand(1..6) }
    { dice: dice, total: dice.sum }
  end

  def self.roll_healing(resolution_tag)
    num_dice = HEALING_DICE.fetch(resolution_tag, 0)
    return { dice: [], total: 0 } if num_dice == 0

    dice = Array.new(num_dice) { rand(1..6) }
    { dice: dice, total: dice.sum }
  end

  def self.update_momentum(current, resolution_tag, impact)
    deltas = MOMENTUM_DELTA.fetch(impact, MOMENTUM_DELTA["positive"])
    delta  = deltas.fetch(resolution_tag, 0)
    [ [ current + delta, -1 ].max, 2 ].min
  end
end
