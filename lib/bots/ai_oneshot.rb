require 'bots/bot'

# DeathRoomba by Elliott — revised: correct @aim semantics, lead, wall escape.*
class DeathRoomba < BattleBots::Bots::Bot
  BULLET_SPEED_PER_TICK = 42.0
  LOCK_TOLERANCE_DEG = 5.0
  ENGAGE_DISTANCE = 420
  IDEAL_RANGE = 280
  WALL_MARGIN = 95

  def initialize
    @name = "DeathRoomba"
    @speed, @strength, @stamina, @sight = [24, 28, 26, 22]
    @drive = 1
    @turn = 0
    @aim = 0
    @shoot = false
    @scan_phase = 1
    @last_ex = @last_ey = nil
    @dance_ticks = rand(40..120)
  end

  def think
    @shoot = false
    enemy = select_target
    update_enemy_tracking(enemy)

    if enemy
      engage(enemy)
    else
      patrol_and_scan
    end

    avoid_walls!
  end

  private

  def update_enemy_tracking(enemy)
    if enemy && @last_ex
      @enemy_dx = enemy[:x] - @last_ex
      @enemy_dy = enemy[:y] - @last_ey
    else
      @enemy_dx = @enemy_dy = 0.0
    end
    if enemy
      @last_ex = enemy[:x]
      @last_ey = enemy[:y]
    else
      @last_ex = @last_ey = nil
    end
  end

  def lead_enemy(enemy)
    return enemy if (@enemy_dx.abs + @enemy_dy.abs) < 0.01

    _, dist = calculate_vector_to(enemy)
    ticks = dist / BULLET_SPEED_PER_TICK
    {
      x: enemy[:x] + @enemy_dx * ticks,
      y: enemy[:y] + @enemy_dy * ticks,
      heading: enemy[:heading],
      health: enemy[:health],
      turret: enemy[:turret]
    }
  end

  def shortest_turn(from_deg, to_deg)
    diff = (to_deg - from_deg + 540) % 360 - 180
    diff
  end

  def aim_turn_toward(bearing)
    delta = shortest_turn(@turret, bearing)
    @aim = delta.positive? ? 1 : (delta.negative? ? -1 : 0)
    delta.abs
  end

  def engage(enemy)
    target = lead_enemy(enemy)
    bearing, distance = calculate_vector_to(target)

    aim_error = aim_turn_toward(bearing)
    @shoot = aim_error < LOCK_TOLERANCE_DEG && distance < ENGAGE_DISTANCE

    move_for_engagement(bearing, distance)
  end

  def move_for_engagement(bearing, distance)
    if distance > IDEAL_RANGE + 40
      drive_toward(bearing)
    elsif distance < IDEAL_RANGE - 80
      drive_away(bearing)
    else
      strafe(bearing)
    end
  end

  def drive_toward(bearing)
    err = shortest_turn(@heading, bearing)
    @turn = err.positive? ? 1 : -1
    @drive = 1
  end

  def drive_away(bearing)
    away = (bearing + 180) % 360
    err = shortest_turn(@heading, away)
    @turn = err.positive? ? 1 : -1
    @drive = 1
  end

  def strafe(bearing)
    perp = (bearing + 90) % 360
    err = shortest_turn(@heading, perp)
    @turn = err.positive? ? 1 : -1
    @drive = 1
  end

  def patrol_and_scan
    @drive = 1
    @dance_ticks -= 1
    if @dance_ticks <= 0
      @turn = [-1, 0, 1].sample
      @dance_ticks = rand(30..90)
    end
    @aim = @scan_phase
    @scan_phase *= -1 if rand < 0.02
  end

  def play_min_x
    @arena_margin.to_f
  end

  def play_max_x
    @arena_width.to_f - @arena_margin.to_f
  end

  def play_min_y
    @arena_margin.to_f
  end

  def play_max_y
    @arena_height.to_f - @arena_margin.to_f
  end

  def avoid_walls!
    return unless defined?(@arena_width) && @arena_width

    cx = (play_min_x + play_max_x) / 2.0
    cy = (play_min_y + play_max_y) / 2.0
    near = @x < play_min_x + WALL_MARGIN ||
      @x > play_max_x - WALL_MARGIN ||
      @y < play_min_y + WALL_MARGIN ||
      @y > play_max_y - WALL_MARGIN
    return unless near

    home_bearing, = calculate_vector_to(
      { x: cx, y: cy, health: 0, heading: 0, turret: 0 }
    )
    err = shortest_turn(@heading, home_bearing)
    @turn = err.positive? ? 1 : -1
    @drive = 1
  end
end
