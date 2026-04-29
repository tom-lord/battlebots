require 'bots/bot'

class RoombaChicken < BattleBots::Bots::Bot
  def initialize
    @name = "The Roomba Chicken"
    @speed, @strength, @stamina, @sight = [50, 25, 25, 0]
    @drive, @turn, @aim, @shoot = [1, 0, 0, true]
    @rand_counter = rand(1..150)

    @hit_wall = false

    @state = nil
  end

  def think
    @aim = 100
    @shoot = true
    # Drive down
    if !@hit_wall
      if ((@heading % 360) - 180).abs > 1
        @turn = 1
        return
      end
      @turn = 0


      if @y == @arena_height - @arena_margin
        @hit_wall = true
        @state = :turning_left
        @drive = 0
      end

      return
    end

    if @state == :turning_left
      if ((@heading % 360) - 270).abs > 1
        @turn = 1
        return
      else
        @turn = 0
        @drive = 1
        @turning_left = false
        @state = :going_left
      end
    end


    if @state == :going_left
      if @x == @arena_margin
        @state = :turning_right
        @drive = 0
      else
        return
      end
    end

    if @state == :turning_right
      if ((@heading % 360) - 90).abs > 1
        @turn = 1
        return
      else
        @turn = 0
        @drive = 1
        @state = :going_right
      end
    end

    if @state == :going_right
      if @x == @arena_width - @arena_margin
        @state = :turning_left
        @turn = 1
      else
        return
      end
    end


    #return if !hit_wall?
    #turn_sideways if hit_wall?

    # @turn = rand(1..360)
    # @aim = rand(0..360)
    # if rand(0..3) == 3
    #   @shoot = true
    # end
  end

  def turn_sideways
    @turn = (@heading % 360) >= (bearing % 360) ? 1 : -1
  end

  def hit_wall?
    @x <= @area_margin || x
  end
end
