require 'bots/bot'

# Loiters near centre of the arena and heckles everyone. Won’t shoot — purely verbal & brick-wall stamina.
class Heckler < BattleBots::Bots::Bot
  def self.bot_source = :ai

  BORDER = 80
  ORBIT_RADIUS = 96

  INSULTS = [
    'Your pathfinding called — it wants an apology.',
    'Bold strategy: shipping straight to prod.',
    'I’ve seen smoother turning on a supermarket trolley.',
    'Is that your release branch or did your cat walk on the keyboard?',
    'Nice shot. No — actually that one was tragic.',
    'Keep hugging that wall — it’s the only fan you’ve got.',
    'Git blame says hi. Surprise — it’s still you.',
    'Roomba energy. Not in the good way.',
    'Your gun arc matches your ambition: modest.',
    'They say iterate fast — you’re just wandering.'
  ].freeze

  # Game ticks per insult (~180 ≈ 3s at 60fps before the bubble advances).
  INSULT_ROTATION_TICKS = 180

  def initialize
    @name = "Josh's Heckler"
    @strength, @speed, @stamina, @sight = [2, 12, 81, 5]
    @bubble_tick = 0
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
    # Dramatic gesticulation — no intent to hit anyone.
    @aim = (@bubble_tick % 90 < 45) ? 1 : -1
    @shoot = false

    stay_clear_of_walls
  end

  def speech_bubble_line
    INSULTS[(@bubble_tick / INSULT_ROTATION_TICKS) % INSULTS.size]
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

# Opt-in speech bubble: patch Proxy from the bot file (no changes to lib/proxy.rb).
unless BattleBots::Proxy.instance_methods(false).include?(:draw_without_speech_bubble__heckler)
  BattleBots::Proxy.class_eval do
    alias_method :draw_without_speech_bubble__heckler, :draw

    def draw
      draw_without_speech_bubble__heckler
      return unless @health.to_f > 0
      return unless @bot.respond_to?(:speech_bubble_line)

      line = @bot.speech_bubble_line
      return if line.nil? || (s = line.to_s.strip).empty?

      scale = 0.72
      pad_x = 10
      pad_y = 5
      tw = @font.text_width(s) * scale + pad_x * 2
      th = @font.height * scale + pad_y * 2
      left = @x - (tw / 2.0)
      top = @y - 38 - th
      z = 3
      c_fill = 0xff_fffcf5
      c_edge = 0xff_2a2a2a
      c_text = 0xff_1a1a1a

      Gosu.draw_rect(left - 2, top - 2, tw + 4, th + 4, c_edge, z)
      Gosu.draw_rect(left, top, tw, th, c_fill, z + 1)
      @font.draw_text(s, left + pad_x, top + pad_y, z + 2, scale, scale, c_text)

      y_base = top + th
      Gosu.draw_triangle(
        @x - 6, y_base, c_fill,
        @x + 6, y_base, c_fill,
        @x, y_base + 12, c_fill,
        z + 1
      )
    end
  end
end
