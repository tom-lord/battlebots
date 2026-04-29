require 'bots/bot'

# Loiters near centre; contextual insults + occasional pot-shots.
class Heckler < BattleBots::Bots::Bot
  def self.bot_source = :ai

  BORDER = 80
  ORBIT_RADIUS = 96

  # Game ticks per insult (~180 ≈ 3s at 60fps before the bubble advances).
  INSULT_ROTATION_TICKS = 180

  SHOOT_CHANCE = [0.50 * 1.3, 1.0].min

  # --- Ridiculous contextual insult engine (templates use Kernel#format keys) ---
  module InsultEngine
    module_function

    def fallback_pool
      @fallback_pool ||= [
        'You’re filler with a hitbox.',
        'Trash arc. Trash reads. Same you.',
        'Die slower — I’m not done laughing.',
        'They let you compile this?',
        'Zero threat. Loud mistakes.',
        'Save it for someone who misses slower.',
        'You’re the tutorial tank they skip.'
      ].freeze
    end

    # Templates: %{me_hp} %{enemy_hp} %{d_round} %{contacts} %{center} %{shoot_under}
    POOLS = {
      dying: [
        "%{me_hp} HP — still smarter shots than yours.",
        'Half dead — still outplaying you.',
        'Bleeding — you’re still the joke.',
        'I’m dying up here — you’re dying inside.'
      ],
      hurting: [
        '%{me_hp}%% left — you’ve done nothing useful.',
        'Hurt — you’re worse.',
        'Damaged — you’re still the weak link.'
      ],
      healthy: [
        'Full HP — you’re still empty.',
        'I’m fine — you’re the problem.',
        'Healthy — you’re hopeless.'
      ],
      no_contacts: [
        'Can’t find you — coward or invisible?',
        'Screen’s empty — like your odds.',
        'Nobody — fits your skill bracket.',
        'No threats — except your build.'
      ],
      melee: [
        '%{d_round}px — breathe mint before you rush me.',
        'This close — still coward shots.',
        'In my face — still no nerve.',
        '%{d_round}px — panic parking.'
      ],
      mid_range: [
        '%{d_round}px — chicken range.',
        'Mid — mid brain.',
        '%{d_round}px out — zero guts.',
        'Comfort zone — you’re still useless.'
      ],
      long_range: [
        '%{d_round}px — scared pixels.',
        'Far — scared.',
        '%{d_round}px back — hiding.',
        'Snail mail engagement.'
      ],
      crowd: [
        '%{contacts} of you — still the worst.',
        "%{contacts} targets — you're the free kill.",
        'Crowd — you’re the embarrassment.',
        "%{contacts} bots — you're bottom tier."
      ],
      duel: [
        'Just us — you lose solo too.',
        '1v1 — you fold.',
        'You alone — still not enough.'
      ],
      vulture: [
        '%{enemy_hp}%% — finish them, coward.',
        'They’re %{enemy_hp} — steal like you mean it.',
        '%{enemy_hp} HP left — you’re late and useless.'
      ],
      bully_the_strong: [
        '%{enemy_hp}%% — pick fights you can lose.',
        'Healthy target — you’ll still choke.',
        '%{enemy_hp} HP — you’re scared anyway.'
      ],
      spotlight: [
        'Centre ring — you’re wallpaper.',
        '%{center}px in — still irrelevant.',
        'Spotlight me — forget you.'
      ],
      perimeter: [
        'Edge rat — stay there.',
        'Wall hugger — owns you.',
        'Corners — your ceiling.'
      ],
      in_range: [
        '< %{shoot_under}px — shoot or quit.',
        'In range — still whiffing.',
        'Gift range — waste it.'
      ],
      out_of_range: [
        '> %{shoot_under}px — scared tube.',
        'Too far — cope.',
        'Out of range — out of league.'
      ]
    }.freeze

    SHOOT_UNDER = 400

    def pick_line(bot, rng)
      ctx = situation(bot)
      pools = []
      pools.concat(POOLS[:dying]) if ctx[:me_hp] < 22
      pools.concat(POOLS[:hurting]) if ctx[:me_hp] >= 22 && ctx[:me_hp] < 55
      pools.concat(POOLS[:healthy]) if ctx[:me_hp] >= 85

      if ctx[:contacts].zero?
        pools.concat(POOLS[:no_contacts])
      elsif ctx[:contacts] >= 2
        pools.concat(POOLS[:crowd])
      else
        pools.concat(POOLS[:duel])
      end

      if ctx[:nearest_dist]
        d = ctx[:nearest_dist]
        if d < 130
          pools.concat(POOLS[:melee])
        elsif d < 340
          pools.concat(POOLS[:mid_range])
        else
          pools.concat(POOLS[:long_range])
        end

        if ctx[:enemy_hp]
          if ctx[:enemy_hp] < 30
            pools.concat(POOLS[:vulture])
          elsif ctx[:enemy_hp] > 85
            pools.concat(POOLS[:bully_the_strong])
          end
        end

        if d < SHOOT_UNDER
          pools.concat(POOLS[:in_range])
        else
          pools.concat(POOLS[:out_of_range])
        end
      end

      if ctx[:from_center] < 110
        pools.concat(POOLS[:spotlight])
      elsif ctx[:near_wall]
        pools.concat(POOLS[:perimeter])
      end

      pools.concat(fallback_pool) if pools.empty?

      raw = pools.sample(random: rng)
      format_line(raw, ctx)
    end

    def situation(bot)
      cx = bot.instance_variable_get(:@arena_width).to_f * 0.5
      cy = bot.instance_variable_get(:@arena_height).to_f * 0.5
      px = bot.instance_variable_get(:@x).to_f
      py = bot.instance_variable_get(:@y).to_f
      from_center = Math.hypot(px - cx, py - cy)

      margin = bot.instance_variable_get(:@arena_margin).to_f
      aw = bot.instance_variable_get(:@arena_width).to_f
      ah = bot.instance_variable_get(:@arena_height).to_f
      left = margin
      right = aw - margin
      top = margin
      bottom = ah - margin
      near_wall = px < left + BORDER || px > right - BORDER || py < top + BORDER || py > bottom - BORDER

      contacts = bot.instance_variable_get(:@contacts)
      contacts = [] if contacts.nil?
      n = contacts.size
      me_hp = bot.instance_variable_get(:@health)
      me_hp = me_hp.nil? ? 100 : me_hp.to_f.round

      nearest = nil
      nearest_dist = nil
      enemy_hp = nil
      if n.positive?
        nearest = contacts.min_by { |c| Math.hypot(c[:x].to_f - px, c[:y].to_f - py) }
        _b, nearest_dist = bot.send(:calculate_vector_to, nearest)
        enemy_hp = nearest[:health].to_f.round if nearest[:health]
      end

      {
        me_hp: me_hp,
        contacts: n,
        nearest_dist: nearest_dist,
        enemy_hp: enemy_hp,
        from_center: from_center.round,
        near_wall: near_wall,
        shoot_under: SHOOT_UNDER
      }
    end

    def format_line(template, ctx)
      d = ctx[:nearest_dist]
      d_round = d ? d.round : 0
      fmt = {
        me_hp: ctx[:me_hp],
        enemy_hp: ctx[:enemy_hp] || '?',
        contacts: ctx[:contacts],
        center: ctx[:from_center],
        d_round: d_round,
        dist: d_round,
        shoot_under: ctx[:shoot_under]
      }
      format(template, **fmt)
    rescue ArgumentError, KeyError
      template
    end
  end

  def initialize
    @name = "Josh's Heckler"
    @strength, @speed, @stamina, @sight = [6, 18, 71, 5]
    @bubble_tick = 0
    @insult_slot_persist = -1
    @insult_line_cache = InsultEngine.fallback_pool.sample
  end

  def think
    @bubble_tick += 1

    cx = @arena_width * 0.5
    cy = @arena_height * 0.5
    t = @bubble_tick * 0.017
    wobble_x = Math.sin(t * 2.05) * 28
    wobble_y = Math.cos(t * 1.62) * 20
    tx = cx + Math.cos(t) * ORBIT_RADIUS + wobble_x
    ty = cy + Math.sin(t * 0.92) * ORBIT_RADIUS * 0.82 + wobble_y

    drive_toward(tx, ty, stop_within: 42)

    enemy = select_target
    if enemy
      bearing, distance = calculate_vector_to(enemy)
      aim_turret(bearing, distance)
      @shoot &&= rand < SHOOT_CHANCE
    else
      @aim = (@bubble_tick % 90 < 45) ? 1 : -1
      @shoot = false
    end

    stay_clear_of_walls
  end

  def speech_bubble_line
    slot = @bubble_tick / INSULT_ROTATION_TICKS
    if slot != @insult_slot_persist
      @insult_slot_persist = slot
      seed = slot * 482_711 ^ (@health.to_i & 0xff) ^ (@contacts&.size || 0) * 97
      rng = Random.new(seed)
      @insult_line_cache = InsultEngine.pick_line(self, rng)
    end
    @insult_line_cache
  end

  private

  def drive_toward(tx, ty, stop_within:)
    bearing, distance = calculate_vector_to({ x: tx, y: ty })
    if distance > stop_within
      @turn = (@heading - bearing) % 360 > 180 ? 1 : -1
      @drive = 1
    else
      @turn = 0
      @drive = 0
    end
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

  def stay_clear_of_walls
    turn_right = 3
    turn_left = -3
    bearing = @heading % 360
    right = play_max_x
    left = play_min_x
    bottom = play_max_y
    top = play_min_y

    if @x > (right - BORDER) && east?(bearing) && north?(bearing)
      @turn = turn_left
    elsif @x > (right - BORDER) && east?(bearing) && south?(bearing)
      @turn = turn_right
    elsif @x < (left + BORDER) && west?(bearing) && north?(bearing)
      @turn = turn_right
    elsif @x < (left + BORDER) && west?(bearing) && south?(bearing)
      @turn = turn_left
    elsif @y > (bottom - BORDER) && south?(bearing) && east?(bearing)
      @turn = turn_left
    elsif @y > (bottom - BORDER) && south?(bearing) && west?(bearing)
      @turn = turn_right
    elsif @y < (top + BORDER) && north?(bearing) && east?(bearing)
      @turn = turn_right
    elsif @y < (top + BORDER) && north?(bearing) && west?(bearing)
      @turn = turn_left
    end
  end

  def east?(b)
    b >= 0 && b <= 180
  end

  def south?(b)
    b >= 90 && b <= 270
  end

  def west?(b)
    b >= 180 && b <= 360
  end

  def north?(b)
    (b >= 0 && b <= 90) || (b >= 270 && b <= 360)
  end
end

unless BattleBots::Proxy.instance_methods(false).include?(:draw_without_speech_bubble__heckler)
  BattleBots::Proxy.class_eval do
    alias_method :draw_without_speech_bubble__heckler, :draw

    def draw
      draw_without_speech_bubble__heckler
      return unless @health.to_f > 0
      return unless @bot.respond_to?(:speech_bubble_line)

      line = @bot.speech_bubble_line
      return if line.nil? || (s = line.to_s.strip).empty?

      scale = 0.962 # ~0.74 × 1.3 — text size
      pad_x = 16    # ~12 × 1.3 — bubble padding
      pad_y = 9     # ~7 × 1.3
      tw = @font.text_width(s) * scale + pad_x * 2
      th = @font.height * scale + pad_y * 2
      left = @x - (tw / 2.0)
      top = @y - 57 - th # ~44 × 1.3 — clearance above hull
      z = 3
      c_fill = 0xff_fffcf5
      c_edge = 0xff_2a2a2a
      c_text = 0xff_1a1a1a

      Gosu.draw_rect(left - 4, top - 4, tw + 8, th + 8, c_edge, z)
      Gosu.draw_rect(left, top, tw, th, c_fill, z + 1)
      @font.draw_text(s, left + pad_x, top + pad_y, z + 2, scale, scale, c_text)

      y_base = top + th
      Gosu.draw_triangle(
        @x - 9, y_base, c_fill,
        @x + 9, y_base, c_fill,
        @x, y_base + 18, c_fill,
        z + 1
      )
    end
  end
end
