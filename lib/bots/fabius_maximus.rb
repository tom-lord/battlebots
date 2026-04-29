require 'bots/bot'

# Fabius Maximus. Wins by attrition under the 60s timeout rule:
# stay ahead on health, deny the opponent clean shots, escalate only if the
# clock will draw both bots if we do nothing.
#
# Phase selection is driven entirely by the timeout's tiebreaker (best health
# wins; full-health tie = draw = both eliminated).
#
#   FLEE  – ahead on health: run, tail-gun, defend the lead.
#   HUNT  – behind on health, OR mirror-stalemate near the time limit: force
#           the resolution at point-blank with predictive aim.
#   SNIPE – default: medium-range pot-shots while strafing.
class FabiusMaximus < BattleBots::Bots::Bot
  WALL_BUFFER          = 100
  ENGAGE_DISTANCE      = 1200
  SNIPE_RANGE_MIN      = 400
  SNIPE_RANGE_MAX      = 650
  TURRET_LOCK_DEG      = 6
  PREDICT_HORIZON      = 30
  REACQUIRE_TICKS      = 60          # 1s of cached pursuit after losing sight
  STALEMATE_TICKS      = 40 * 60     # 40s with no hits → break the tie or lose to draw
  HEALTH_EPSILON       = 1.0

  def initialize
    @name = "Fabius Maximus"
    # Speed 40: 240°/sec turret + fast evasion. Stamina 30: doubles effective HP.
    # Strength 20: enough to actually land scoring hits at mid-range.
    @strength, @speed, @stamina, @sight = [20, 40, 30, 10]
    @ticks = 0
    @last_seen = nil
    @last_seen_tick = -1
    @last_known_enemy_health = 100.0
    @sweep_dir = 1
  end

  def think
    @ticks += 1
    enemy = current_enemy
    record_sighting(enemy) if enemy

    case current_phase
    when :flee  then flee_mode(enemy)
    when :hunt  then hunt_mode(enemy)
    else             snipe_mode(enemy)
    end

    avoid_walls
  end

  private

  # 1v1 — `@contacts` holds at most one entry, but be defensive.
  def current_enemy
    return nil if @contacts.nil? || @contacts.empty?
    @contacts.first
  end

  def record_sighting(enemy)
    @last_seen = { x: enemy[:x], y: enemy[:y], heading: enemy[:heading], health: enemy[:health] }
    @last_seen_tick = @ticks
    @last_known_enemy_health = enemy[:health]
  end

  # The whole strategy lives here. The timeout rule (TournamentHealthTimeout):
  #   - both at full health → draw → both eliminated
  #   - higher health wins; tie at <100 = random
  # So: keep our health > theirs, AND make sure at least one hit has landed by
  # the time the clock runs out.
  def current_phase
    enemy_h = @last_known_enemy_health

    return :flee if @health > enemy_h + HEALTH_EPSILON
    return :hunt if @health < enemy_h - HEALTH_EPSILON

    # Tied. If both still at full, the clock is our enemy: a draw eliminates us.
    both_full = @health > 99 && enemy_h > 99
    return :hunt if both_full && @ticks > STALEMATE_TICKS

    :snipe
  end

  ## --- SNIPE: hold mid-range, strafe perpendicular, lead the shot ---

  def snipe_mode(enemy)
    enemy ||= ghost_target
    return hunt_for_contact unless enemy

    bearing, distance = calculate_vector_to(enemy)
    lead = predict_bearing(enemy, distance)
    aim_at(lead)

    drive_bearing =
      if distance < SNIPE_RANGE_MIN
        (bearing + 180) % 360            # too close — back off
      elsif distance > SNIPE_RANGE_MAX
        bearing                          # too far — close a little
      else
        (bearing + 90) % 360             # in-band — strafe perpendicular
      end
    drive_toward(drive_bearing)

    fire_at_will(lead, distance)
  end

  ## --- FLEE: run, tail-gun, take any free shots ---------------------

  def flee_mode(enemy)
    enemy ||= ghost_target
    if enemy
      bearing, distance = calculate_vector_to(enemy)
      drive_toward((bearing + 180) % 360)
      lead = predict_bearing(enemy, distance)
      aim_at(lead)
      fire_at_will(lead, distance)
    else
      # Lead is banked, opponent unseen — keep moving and sweep for them.
      hunt_for_contact
      @shoot = false
    end
  end

  ## --- HUNT: close, predictive aim, ram -----------------------------

  def hunt_mode(enemy)
    enemy ||= ghost_target
    return hunt_for_contact unless enemy

    bearing, distance = calculate_vector_to(enemy)
    lead = predict_bearing(enemy, distance)
    aim_at(lead)
    drive_toward(bearing)
    fire_at_will(lead, distance)
  end

  ## --- Targeting helpers --------------------------------------------

  # If we briefly lost sight, treat the last-seen position as the target so we
  # don't drop strategy mid-engagement.
  def ghost_target
    return nil unless @last_seen
    return nil if @ticks - @last_seen_tick > REACQUIRE_TICKS
    @last_seen
  end

  def predict_bearing(enemy, distance)
    bullet_speed = 100.0 * skill(@strength)
    return calculate_vector_to(enemy).first if bullet_speed <= 0

    flight_time = [distance / bullet_speed, PREDICT_HORIZON].min
    enemy_speed = skill(@speed) * 3.5
    rad = (enemy[:heading] || 0) * Math::PI / 180.0
    future = {
      x: enemy[:x] + Math.cos(rad) * enemy_speed * flight_time,
      y: enemy[:y] + Math.sin(rad) * enemy_speed * flight_time
    }
    calculate_vector_to(future).first
  end

  ## --- Control primitives -------------------------------------------

  def aim_at(bearing)
    @aim = signed_delta(bearing, @turret)
  end

  def drive_toward(bearing)
    @turn  = signed_delta(bearing, @heading).clamp(-3, 3)
    @drive = 1
  end

  def fire_at_will(bearing, distance)
    @shoot = false
    return if distance > ENGAGE_DISTANCE
    off = signed_delta(bearing, @turret).abs
    tolerance = distance < 300 ? TURRET_LOCK_DEG * 3 : TURRET_LOCK_DEG
    @shoot = off <= tolerance
  end

  def hunt_for_contact
    centre = { x: @arena_width * 0.5, y: @arena_height * 0.5 }
    bearing, _ = calculate_vector_to(centre)
    drive_toward(bearing)
    @aim = @sweep_dir * skill(@speed) * 10
    @sweep_dir = -@sweep_dir if rand < 0.02
    @shoot = false
  end

  def avoid_walls
    margin = @arena_margin.to_f
    min_x = margin + WALL_BUFFER
    max_x = @arena_width  - margin - WALL_BUFFER
    min_y = margin + WALL_BUFFER
    max_y = @arena_height - margin - WALL_BUFFER

    return unless @x < min_x || @x > max_x || @y < min_y || @y > max_y

    centre_bearing, _ = calculate_vector_to(x: @arena_width * 0.5, y: @arena_height * 0.5)
    @turn  = signed_delta(centre_bearing, @heading).clamp(-3, 3)
    @drive = 1
  end

  def signed_delta(target_deg, current_deg)
    delta = (target_deg - current_deg) % 360
    delta -= 360 if delta > 180
    delta
  end

  def skill(value)
    value.to_f / 100.0
  end
end
