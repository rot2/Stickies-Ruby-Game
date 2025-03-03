require 'gosu'
require 'socket'
require 'thread'
require 'json'

# Color definitions (unchanged)
WHITE = Gosu::Color.new(0xff_ffffff)
BLACK = Gosu::Color.new(0xff_000000)
GRASS_GREEN = Gosu::Color.new(0xff_228b22)
SKY_BLUE = Gosu::Color.new(0xff_87ceeb)
BROWN = Gosu::Color.new(0xff_8b4513)
GRAY = Gosu::Color.new(0xff_a9a9a9)
RED = Gosu::Color.new(0xff_ff0000)
SILVER = Gosu::Color.new(0xff_c0c0c0)
SAND = Gosu::Color.new(0xff_f5deb3)
DEEP_BLUE = Gosu::Color.new(0xff_00008b)
GREEN = Gosu::Color.new(0xff_006400)
BLOOD_RED = Gosu::Color.new(0xff_8a0707)
GOLD = Gosu::Color.new(0xff_ffd700)

class Map
  attr_reader :bg_color_top, :bg_color_bottom, :objects, :name

  def initialize(bg_color_top, bg_color_bottom, objects, name)
    @bg_color_top = bg_color_top
    @bg_color_bottom = bg_color_bottom
    @objects = objects
    @name = name
  end

  def draw(window)
    window.draw_quad(0, 0, @bg_color_top, window.width, 0, @bg_color_top,
                     0, window.height, @bg_color_top, window.width, window.height, @bg_color_top)
    window.draw_quad(0, window.height / 2, @bg_color_bottom, window.width, window.height / 2, @bg_color_bottom,
                     0, window.height, @bg_color_bottom, window.width, window.height, @bg_color_bottom)
    @objects.each(&:draw)
  end
end

class GameObject
  attr_reader :x, :y, :type, :rect, :interactive

  def initialize(x, y, type, interactive = false)
    @x = x
    @y = y
    @type = type
    @interactive = interactive
    @glow_timer = 0
    case type
    when "bank" then @rect = [x, y, 40, 20]
    when "tree" then @rect = [x + 15, y + 20, 20, 40]
    when "mall" then @rect = [x, y, 100, 60]
    when "coin" then @rect = [x, y, 10, 10]
    when "sword" then @rect = [x, y, 20, 10]
    when "car" then @rect = [x, y, 50, 30]
    end
  end

  def draw
    case @type
    when "bank"
      Gosu.draw_rect(@x, @y, 40, 20, BROWN)
    when "tree"
      Gosu.draw_triangle(@x, @y + 20, GRASS_GREEN, @x + 20, @y, GRASS_GREEN, @x + 40, @y + 20, GRASS_GREEN)
      Gosu.draw_rect(@x + 18, @y + 20, 4, 20, BROWN)
    when "mall"
      Gosu.draw_rect(@x, @y, 100, 60, GRAY)
      Gosu.draw_rect(@x + 40, @y + 10, 20, 40, BLACK)
    when "coin"
      @glow_timer = (@glow_timer + 1) % 60
      glow = (30 - @glow_timer).abs / 30.0
      size = 5 + glow
      Gosu.draw_rect(@x + 5 - size / 2, @y + 5 - size / 2, size, size, GOLD)
    when "sword"
      @glow_timer = (@glow_timer + 1) % 60
      glow = (30 - @glow_timer).abs / 30.0
      Gosu.draw_rect(@x, @y, 20, 10, SILVER)
      Gosu.draw_rect(@x - 2, @y - 2, 24, 14, Gosu::Color.argb(0xff_cccccc)) if glow > 0.5
    when "car"
      Gosu.draw_rect(@x, @y, 50, 30, RED)
      Gosu.draw_rect(@x + 10 - 5, @y + 30 - 5, 10, 10, BLACK)
      Gosu.draw_rect(@x + 40 - 5, @y + 30 - 5, 10, 10, BLACK)
    end
  end
end

class BloodEffect
  def initialize(x, y)
    @x = x
    @y = y
    @timer = 60
    @particles = 10.times.map do
      angle = rand * 2 * Math::PI
      speed = rand(1.0..3.0)
      { x: x, y: y, dx: speed * Math.cos(angle), dy: speed * Math.sin(angle), size: rand(2..5) }
    end
  end

  def update
    @timer -= 1
    @particles.each do |p|
      p[:x] += p[:dx]
      p[:y] += p[:dy]
      p[:size] = [0, p[:size] - 0.05].max
    end
  end

  def draw
    @particles.each do |p|
      Gosu.draw_rect(p[:x] - p[:size] / 2, p[:y] - p[:size] / 2, p[:size], p[:size], BLOOD_RED)
    end
  end

  def active?
    @timer > 0
  end
end

class NPC
  attr_accessor :hit_effect
  attr_reader :x, :y, :type, :rect, :health

  def initialize(x, y, type)
    @x = x
    @y = y
    @type = type
    @rect = [x, y, 30, 30]
    @health = 50
    @speed = 2
    @attack_timer = 0
    @spawn_time = Time.now
    @leg_angle = 0
    @direction = 1
    @attack_anim = 0
    @hit_effect = nil
  end

  def draw
    return if @health <= 0
    # NPC rengi yeşilden kırmızıya değiştirildi
    Gosu.draw_rect(@x, @y, 30, 30, @type == "monster" ? RED : GREEN)
    Gosu.draw_rect(@x, @y - 10, 30, 5, RED)
    Gosu.draw_rect(@x, @y - 10, 30 * (@health / 50.0), 5, GREEN)
    head_x, head_y = @x + 15, @y + 10
    Gosu.draw_rect(head_x - 8, head_y - 8, 16, 16, @type == "monster" ? RED : GREEN)
    Gosu.draw_line(head_x, head_y + 8, @type == "monster" ? RED : GREEN, head_x, @y + 25, @type == "monster" ? RED : GREEN)
    arm_angle = @attack_anim > 0 ? 30 : 0
    arm_length = 15
    arm_x = @direction == 1 ? head_x + arm_length * Math.cos(arm_angle * Math::PI / 180) : head_x - arm_length * Math.cos(arm_angle * Math::PI / 180)
    arm_y = head_y + 5 + arm_length * Math.sin(arm_angle * Math::PI / 180)
    Gosu.draw_line(head_x, head_y + 5, @type == "monster" ? RED : GREEN, arm_x, arm_y, @type == "monster" ? RED : GREEN)
    leg_sway = Math.sin(@leg_angle) * 10
    leg_left_x = @direction == 1 ? head_x - 8 + leg_sway : head_x - 8 - leg_sway
    leg_right_x = @direction == 1 ? head_x + 8 - leg_sway : head_x + 8 + leg_sway
    Gosu.draw_line(head_x, @y + 25, @type == "monster" ? RED : GREEN, leg_left_x, @y + 40, @type == "monster" ? RED : GREEN)
    Gosu.draw_line(head_x, @y + 25, @type == "monster" ? RED : GREEN, leg_right_x, @y + 40, @type == "monster" ? RED : GREEN)
    @hit_effect&.draw
  end

  def move_towards(target_x, target_y)
    return unless @health > 0
    dx = target_x - @x
    dy = target_y - @y
    dist = Math.sqrt(dx**2 + dy**2)
    @direction = dx > 0 ? 1 : -1
    @leg_angle += 0.2
    @leg_angle = 0 if @leg_angle > 2 * Math::PI
    if dist > 30
      dx, dy = dx / dist, dy / dist
      @x += dx * @speed
      @y += dy * @speed
      @rect[0], @rect[1] = @x, @y
    elsif dist <= 30 && @attack_timer <= 0
      @attack_anim = 10
    end
    if @hit_effect
      @hit_effect.update
      @hit_effect = nil unless @hit_effect.active?
    end
  end

  def attack(player)
    return unless @health > 0
    if collide?(player)
      if @attack_timer <= 0
        player.take_damage(10)
        player.hit_effect = BloodEffect.new(player.x + 10, player.y + 10)
        @attack_timer = 60
        @attack_anim = 10
      end
    end
    @attack_timer -= 1 if @attack_timer > 0
    @attack_anim -= 1 if @attack_anim > 0
  end

  def collide?(player)
    @rect[0] + @rect[2] > player.rect[0] && @rect[0] < player.rect[0] + player.rect[2] &&
      @rect[1] + @rect[3] > player.rect[1] && @rect[1] < player.rect[1] + player.rect[3]
  end

  def take_damage(amount)
    @health -= amount
    @health = 0 if @health < 0
  end
end

class Quest
  attr_accessor :description, :reward, :completed

  def initialize(description, reward)
    @description = description
    @reward = reward
    @completed = false
  end
end

class Player
  attr_accessor :x, :y, :health, :coins, :inventory, :map_index, :message, :message_timer, :holding_item, :clothes, :attack_timer, :experience, :level, :name, :speed, :quests, :hit_effect
  attr_reader :color

  def initialize(x, y, r, g, b, name)
    @x = x
    @y = y
    @color = Gosu::Color.argb(0xff_000000).dup
    @color.red, @color.green, @color.blue = r, g, b
    @name = name
    @health = 100
    @coins = 0
    @inventory = []
    @map_index = 0
    @rect = [x + 5, y + 10, 15, 50]
    @speed = 5
    @direction = 0
    @last_direction = 1
    @is_moving = false
    @leg_angle = 0
    @attack_timer = 0
    @attack_direction = 1
    @hit_effect = nil
    @experience = 0
    @level = 1
    @clothes = { "hat" => nil, "shirt" => nil }
    @holding_item = nil
    @message = ""
    @message_timer = 0
    @quests = [Quest.new("5 altın topla", 50)]
  end

  def draw(window)
    if @health <= 0
      Gosu.draw_rect(@x + 2, @y + 2, 16, 16, @color)
      Gosu.draw_line(@x - 5, @y + 20, @color, @x + 25, @y + 40, @color)
      Gosu.draw_line(@x + 25, @y + 20, @color, @x - 5, @y + 40, @color)
      return
    end

    Gosu.draw_rect(@x + 2, @y + 2, 16, 16, @color)
    Gosu.draw_line(@x + 10, @y + 20, @color, @x + 10, @y + 40, @color)

    if @attack_timer > 0
      sword_start_x = @attack_direction == 1 ? @x + 20 : @x
      sword_angle = @attack_direction == 1 ? -45 + (@attack_timer * 9) : 225 - (@attack_timer * 9)
      sword_length = 25
      sword_end_x = sword_start_x + sword_length * Math.cos(sword_angle * Math::PI / 180)
      sword_end_y = @y + 25 + sword_length * Math.sin(sword_angle * Math::PI / 180)
      Gosu.draw_line(@x + 10, @y + 25, @color, sword_start_x, @y + 25, @color)
      Gosu.draw_line(sword_start_x, @y + 25, SILVER, sword_end_x, sword_end_y, SILVER)
      Gosu.draw_line(@x + 10, @y + 25, @color, @x + (@attack_direction == 1 ? 0 : 20), @y + 25, @color)
      if (5..10).include?(@attack_timer)
        3.times do |i|
          offset = i * 5
          Gosu.draw_line(sword_end_x - offset, sword_end_y - offset, Gosu::Color.argb(0x80_cccccc), sword_end_x + offset, sword_end_y + offset, Gosu::Color.argb(0x80_cccccc))
        end
      end
    elsif @holding_item == "sword"
      sword_x = @direction >= 0 ? @x + 20 : @x - 20
      Gosu.draw_line(@x + 10, @y + 25, @color, @direction >= 0 ? @x : @x + 20, @y + 25, @color)
      Gosu.draw_line(@x + 10, @y + 25, @color, @direction >= 0 ? @x + 20 : @x, @y + 25, @color)
      Gosu.draw_line(@direction >= 0 ? @x + 20 : @x, @y + 25, SILVER, sword_x + (@direction >= 0 ? 20 : -20), @y + 35, SILVER)
    else
      dir = @direction != 0 ? @direction : @last_direction
      Gosu.draw_line(@x + 10, @y + 25, @color, @x - 5 + 10 * (dir > 0 ? 1 : 0), @y + 25, @color)
      Gosu.draw_line(@x + 10, @y + 25, @color, @x + 25 - 10 * (dir > 0 ? 1 : 0), @y + 25, @color)
    end

    leg_sway = @is_moving ? Math.sin(@leg_angle) * 10 : 0
    leg_left_x = @direction == 1 ? @x + 5 + leg_sway : @x + 5 - leg_sway
    leg_right_x = @direction == 1 ? @x + 15 - leg_sway : @x + 15 + leg_sway
    leg_left_x = @x if !@is_moving
    leg_right_x = @x + 20 if !@is_moving
    Gosu.draw_line(@x + 10, @y + 40, @color, leg_left_x, @y + 60, @color)
    Gosu.draw_line(@x + 10, @y + 40, @color, leg_right_x, @y + 60, @color)

    Gosu.draw_rect(@x, @y - 5, 20, 5, RED) if @clothes["hat"]
    Gosu.draw_rect(@x, @y + 20, 20, 20, RED) if @clothes["shirt"]

    window.font.draw_text(@name, @x - window.font.text_width(@name) / 2 + 10, @y - 50, 0, 1, 1, BLACK)
    window.font.draw_text("Lv#{@level}", @x - window.font.text_width("Lv#{@level}") / 2 + 10, @y - 35, 0, 1, 1, BLACK)
    window.font.draw_text("HP: #{@health}", @x - 10, @y - 20, 0, 1, 1, BLACK)
    Gosu.draw_rect(@x, @y - 15, 20, 5, RED)
    Gosu.draw_rect(@x, @y - 15, 20 * (@health / 100.0), 5, GREEN)

    if @message_timer > 0
      msg_width = window.font.text_width(@message)
      Gosu.draw_rect(@x - msg_width / 2 + 10, @y - 70, msg_width + 10, 20, Gosu::Color.argb(0xcc_000000)) # Siyah arka plan
      window.font.draw_text(@message, @x - msg_width / 2 + 15, @y - 68, 0, 1, 1, GOLD) # Yazı rengi sarı
    end

    if @hit_effect
      @hit_effect.draw
      @hit_effect.update
      @hit_effect = nil unless @hit_effect.active?
    end
  end

  def update
    @is_moving ? @leg_angle += 0.2 : @leg_angle = 0
    @leg_angle -= 2 * Math::PI if @leg_angle > 2 * Math::PI
    @attack_timer -= 1 if @attack_timer > 0
    @message_timer -= 1 if @message_timer > 0
  end

  def move(dx, dy, objects, window)
    @is_moving = dx != 0 || dy != 0
    @direction = dx > 0 ? 1 : dx < 0 ? -1 : 0
    @last_direction = @direction if @direction != 0
    new_x = @x + dx
    new_y = @y + dy
    new_rect = [@rect[0] + dx, @rect[1] + dy, @rect[2], @rect[3]]
    return if new_x < 0 || new_x + @rect[2] > window.width || new_y < window.height / 2 || new_y + @rect[3] > window.height

    objects.each do |obj|
      if collide?(new_rect, obj.rect)
        if obj.interactive && ["coin", "sword"].include?(obj.type)
          @inventory << obj.type
          @holding_item = "sword" if obj.type == "sword"
          @coins += 1 if obj.type == "coin"
          objects.delete(obj)
          check_quests
        elsif !obj.interactive
          return
        end
      end
    end

    @x, @y = new_x, new_y
    @rect[0], @rect[1] = @x + 5, @y + 10
  end

  def attack(players, npcs)
    return false unless @holding_item == "sword" && @attack_timer == 0
    @attack_timer = 15
    @attack_direction = @direction >= 0 ? 1 : -1
    attack_rect = @attack_direction == 1 ? [@x + 20, @y - 10, 40, 60] : [@x - 40, @y - 10, 40, 60]
    hit_any = false
    players.each_value do |player|
      next if player == self || player.map_index != @map_index
      if collide?(attack_rect, player.rect)
        player.take_damage(25)
        player.hit_effect = BloodEffect.new(player.x + 10, player.y + 10)
      end
    end
    npcs.each do |npc|
      if collide?(attack_rect, npc.rect)
        npc.take_damage(25)
        npc.hit_effect = BloodEffect.new(npc.x + 15, npc.y + 15)
        hit_any = true
        @experience += 5 if npc.type == "monster"
        if npc.health <= 0
          @experience += 20
          check_level_up
        end
      end
    end
    hit_any
  end

  def check_quests
    if @coins >= 5
      @quests.each do |quest|
        if quest.description == "5 altın topla" && !quest.completed
          quest.completed = true
          @coins += quest.reward
          @experience += 50
          check_level_up
        end
      end
    end
  end

  def check_level_up
    required_exp = @level * 100
    if @experience >= required_exp
      @level += 1
      @health = 100
      @experience -= required_exp
    end
  end

  def take_damage(amount)
    @health -= amount
    @health = 0 if @health < 0
  end

  def respawn(window)
    @health = 100
    @x = window.width / 2
    @y = window.height - 100
    @rect[0], @rect[1] = @x + 5, @y + 10
    @inventory = @inventory.reject { |item| item == "sword" }
    @holding_item = nil
  end

  def collide?(rect1, rect2)
    rect1[0] + rect1[2] > rect2[0] && rect1[0] < rect2[0] + rect2[2] &&
      rect1[1] + rect1[3] > rect2[1] && rect1[1] < rect2[1] + rect2[3]
  end

  def rect
    @rect
  end
end

class GameWindow < Gosu::Window
  attr_reader :font

  def initialize
    super(800, 600)
    self.caption = "Stickies"
    @font = Gosu::Font.new(20)
    @speed = 5
    @maps = [
      Map.new(SKY_BLUE, GRASS_GREEN, [
        GameObject.new(100, 400, "bank"), GameObject.new(600, 300, "bank"),
        GameObject.new(300, 350, "tree"), GameObject.new(500, 500, "tree"),
        GameObject.new(200, 300, "coin", true), GameObject.new(400, 450, "sword", true)
      ], "Park"),
      Map.new(SKY_BLUE, DEEP_BLUE, [
        GameObject.new(200, 350, "bank"), GameObject.new(400, 250, "car"),
        GameObject.new(600, 450, "car"), GameObject.new(300, 400, "coin", true),
        GameObject.new(500, 350, "sword", true)
      ], "Deniz"),
      Map.new(SKY_BLUE, SAND, [
        GameObject.new(200, 350, "bank"), GameObject.new(400, 250, "tree"),
        GameObject.new(600, 450, "coin", true), GameObject.new(300, 400, "sword", true)
      ], "Çöl"),
      Map.new(SKY_BLUE, GREEN, [
        GameObject.new(100, 400, "tree"), GameObject.new(600, 300, "tree"),
        GameObject.new(300, 200, "tree"), GameObject.new(500, 500, "coin", true),
        GameObject.new(400, 450, "sword", true)
      ], "Orman")
    ]
    @initial_npcs = [
      [NPC.new(300, 400, "monster"), NPC.new(500, 350, "monster")],
      [NPC.new(400, 400, "monster")],
      [NPC.new(600, 300, "monster"), NPC.new(200, 500, "monster")],
      [NPC.new(300, 300, "monster"), NPC.new(500, 400, "monster")]
    ]
    @npcs = @initial_npcs.map(&:dup)
    @respawn_times = @npcs.map { |n| n.map { 0 } }

    @game_state = :start_screen  # Oyun durumu: başlangıç ekranı
    @title_timer = 0  # Başlık animasyonu için zamanlayıcı
    @name_input = ""
    @name_entered = false
    @players = {}
    @local_player = nil
    @chat_messages = []
    @input_text = ""
    @input_active = false
    @inventory_open = false
    @last_key = nil

    setup_networking
  end

  def setup_networking
    @host = "127.0.0.1"
    @port = 5555
    begin
      @server = TCPServer.new(@host, @port)
      @clients = []
      Thread.new do
        loop do
          client = @server.accept
          @clients << client
          Thread.new { handle_client(client) }
        end
      end
    rescue Errno::EADDRINUSE
      puts "Port 5555 is already in use. Please free it or use a different port."
      exit
    end

    @client = TCPSocket.new(@host, @port)
    Thread.new { receive_data }
  end

  def handle_client(client)
    loop do
      data = client.gets&.chomp
      break unless data
      player_data = JSON.parse(data)
      @players[player_data["name"]] ||= Player.new(0, 0, player_data["r"], player_data["g"], player_data["b"], player_data["name"])
      update_player_from_data(@players[player_data["name"]], player_data)
      @clients.each { |c| c.puts(data) unless c == client }
    end
    @clients.delete(client)
    client.close
  end

  def update_player_from_data(player, data)
    player.x, player.y = data["x"], data["y"]
    player.message, player.message_timer = data["message"], data["message_timer"]
    player.map_index, player.coins = data["map_index"], data["coins"]
    player.inventory, player.clothes = data["inventory"], data["clothes"]
    player.holding_item, player.attack_timer = data["holding_item"], data["attack_timer"]
    player.health, player.experience, player.level = data["health"], data["experience"], data["level"]
  end

  def receive_data
    loop do
      data = @client.gets&.chomp
      next unless data
      player_data = JSON.parse(data)
      next if player_data["name"] == @local_player&.name
      @players[player_data["name"]] ||= Player.new(0, 0, player_data["r"], player_data["g"], player_data["b"], player_data["name"])
      update_player_from_data(@players[player_data["name"]], player_data)
    end
  end

  def send_data
    return unless @local_player
    data = {
      "name" => @local_player.name,
      "x" => @local_player.x,
      "y" => @local_player.y,
      "r" => @local_player.color.red,
      "g" => @local_player.color.green,
      "b" => @local_player.color.blue,
      "message" => @local_player.message,
      "message_timer" => @local_player.message_timer,
      "map_index" => @local_player.map_index,
      "coins" => @local_player.coins,
      "inventory" => @local_player.inventory,
      "quests" => @local_player.quests.map { |q| { "description" => q.description, "reward" => q.reward, "completed" => q.completed } },
      "clothes" => @local_player.clothes,
      "holding_item" => @local_player.holding_item,
      "attack_timer" => @local_player.attack_timer,
      "health" => @local_player.health,
      "experience" => @local_player.experience,
      "level" => @local_player.level
    }
    @client.puts(JSON.generate(data))
  end

  def update
    case @game_state
    when :start_screen
      @title_timer += 1
    when :name_input
      # İsim girme ekranında update gerekmez
    when :playing
      @local_player.move(-@speed, 0, @maps[@local_player.map_index].objects, self) if button_down?(Gosu::KB_A)
      @local_player.move(@speed, 0, @maps[@local_player.map_index].objects, self) if button_down?(Gosu::KB_D)
      @local_player.move(0, -@speed, @maps[@local_player.map_index].objects, self) if button_down?(Gosu::KB_W)
      @local_player.move(0, @speed, @maps[@local_player.map_index].objects, self) if button_down?(Gosu::KB_S)
      @local_player.update

      if @local_player.x <= 0 && @local_player.map_index > 0
        @local_player.map_index -= 1
        @local_player.x = width - 20
        @local_player.rect[0] = @local_player.x + 5
      elsif @local_player.x >= width - 20 && @local_player.map_index < @maps.length - 1
        @local_player.map_index += 1
        @local_player.x = 0
        @local_player.rect[0] = @local_player.x + 5
      end

      @local_player.respawn(self) if @local_player.health <= 0

      current_npcs = @npcs[@local_player.map_index]
      current_time = Time.now
      current_npcs.each_with_index do |npc, i|
        if npc.health <= 0
          if @respawn_times[@local_player.map_index][i] == 0
            @respawn_times[@local_player.map_index][i] = current_time + 10
          elsif current_time >= @respawn_times[@local_player.map_index][i]
            current_npcs << NPC.new(@initial_npcs[@local_player.map_index][i].x, @initial_npcs[@local_player.map_index][i].y, "monster")
            @respawn_times[@local_player.map_index][i] = 0
          end
          current_npcs.delete(npc)
          next
        end
        npc.move_towards(@local_player.x, @local_player.y)
        npc.attack(@local_player)
      end

      @local_player.attack(@players, current_npcs) if button_down?(Gosu::MS_LEFT)
      send_data
    end
  end

  def draw
    case @game_state
    when :start_screen
      draw_quad(0, 0, SKY_BLUE, width, 0, SKY_BLUE, 0, height, GRASS_GREEN, width, height, GRASS_GREEN)
      scale = 1.0 + Math.sin(@title_timer * 0.05) * 0.1
      @font.draw_text("Stickies", width / 2 - @font.text_width("Stickies") / 2, height / 3, 0, scale, scale, WHITE)
      @font.draw_text("Oyunu Başlat", width / 2 - @font.text_width("Oyunu Başlat") / 2, height / 2, 0, 1, 1, WHITE)
    when :name_input
      draw_quad(0, 0, SKY_BLUE, width, 0, SKY_BLUE, 0, height, GRASS_GREEN, width, height, GRASS_GREEN)
      @font.draw_text("Karakter ismini gir:", width / 2 - 100, height / 2 - 20, 0, 1, 1, WHITE)
      @font.draw_text(@name_input, width / 2 - 100, height / 2 + 10, 0, 1, 1, WHITE)
    when :playing
      @maps[@local_player.map_index].draw(self)
      @npcs[@local_player.map_index].each(&:draw)
      @players.each_value { |player| player.draw(self) if player.map_index == @local_player.map_index }

      # Mini Map
      Gosu.draw_rect(width - 110, 10, 100, 100, BLACK)
      map_scale = 0.1
      @maps[@local_player.map_index].objects.each do |obj|
        case obj.type
        when "bank" then Gosu.draw_rect(width - 110 + obj.x * map_scale, 10 + obj.y * map_scale, 4, 2, BROWN)
        when "tree" then Gosu.draw_rect(width - 110 + obj.x * map_scale, 10 + obj.y * map_scale, 2, 2, GRASS_GREEN)
        when "mall" then Gosu.draw_rect(width - 110 + obj.x * map_scale, 10 + obj.y * map_scale, 10, 6, GRAY)
        when "coin" then Gosu.draw_rect(width - 110 + obj.x * map_scale, 10 + obj.y * map_scale, 1, 1, GOLD)
        when "sword" then Gosu.draw_rect(width - 110 + obj.x * map_scale, 10 + obj.y * map_scale, 2, 1, SILVER)
        when "car" then Gosu.draw_rect(width - 110 + obj.x * map_scale, 10 + obj.y * map_scale, 5, 3, RED)
        end
      end
      @players.each_value do |player|
        Gosu.draw_rect(width - 110 + player.x * map_scale, 10 + player.y * map_scale, 2, 2, player.instance_variable_get(:@color)) if player.map_index == @local_player.map_index
      end
      @npcs[@local_player.map_index].each do |npc|
        Gosu.draw_rect(width - 110 + npc.x * map_scale, 10 + npc.y * map_scale, 3, 3, RED) # Mini haritada NPC kırmızı
      end

      # UI
      if @inventory_open
        Gosu.draw_rect(width / 2 - 150, height / 2 - 100, 300, 200, Gosu::Color.argb(0xcc_333333)) # Koyu gri arka plan
        @font.draw_text("Altın: #{@local_player.coins}", width / 2 - 140, height / 2 - 90, 0, 1, 1, GOLD)
        @font.draw_text("Can: #{@local_player.health}", width / 2 - 140, height / 2 - 70, 0, 1, 1, GOLD)
        @font.draw_text("EXP: #{@local_player.experience}/#{@local_player.level * 100}", width / 2 - 140, height / 2 - 50, 0, 1, 1, GOLD)
        @font.draw_text("Envanter:", width / 2 - 140, height / 2 - 30, 0, 1, 1, GOLD) # Başlık eklendi
        @local_player.inventory.each_with_index do |item, i|
          @font.draw_text(item, width / 2 - 140, height / 2 - 10 + i * 20, 0, 1, 1, GOLD) # Itemler aşağı kaydırıldı
        end
        @local_player.quests.each_with_index do |quest, i|
          @font.draw_text("#{quest.description} - #{quest.completed ? 'Tamamlandı' : 'Devam Ediyor'}", width / 2 - 140, height / 2 + 50 + i * 20, 0, 1, 1, GOLD) # Görevler daha aşağıda
        end
      end

      # Chat
      Gosu.draw_rect(10, height - 50, width - 20, 40, Gosu::Color.argb(0xcc_333333)) # Koyu gri arka plan
      @font.draw_text(@input_text, 15, height - 45, 0, 1, 1, GOLD) if @input_active # Chat yazısı sarı
      @chat_messages.last(5).each_with_index do |msg, i|
        @font.draw_text(msg, 15, height - 90 - i * 20, 0, 1, 1, GOLD) # Chat mesajları sarı
      end
    end
  end

  def button_down(id)
    return if @last_key == id

    @last_key = id
    close if id == Gosu::KB_ESCAPE

    case @game_state
    when :start_screen
      if id == Gosu::KB_RETURN
        @game_state = :name_input
      end
    when :name_input
      if id == Gosu::KB_RETURN && !@name_input.empty?
        @name_entered = true
        @players[@name_input] = Player.new(width / 2, height - 100, rand(255), rand(255), rand(255), @name_input)
        @local_player = @players[@name_input]
        @game_state = :playing
      elsif id == Gosu::KB_BACKSPACE
        @name_input = @name_input[0..-2]
      elsif (char = Gosu.button_id_to_char(id)) && char =~ /[a-zA-Z0-9]/
        @name_input += char
      end
    when :playing
      if id == Gosu::KB_RETURN
        if @input_active && !@input_text.empty?
          @chat_messages << @input_text
          @local_player.message = @input_text
          @local_player.message_timer = 180
          @input_text = ""
        end
        @input_active = !@input_active
      elsif id == Gosu::KB_BACKSPACE && @input_active
        @input_text = @input_text[0..-2]
      elsif @input_active && (char = Gosu.button_id_to_char(id))
        @input_text += char
      end
      @inventory_open = !@inventory_open if id == Gosu::KB_I
      if id == Gosu::KB_1 && @local_player.coins >= 10
        @local_player.coins -= 10
        @local_player.clothes["hat"] = "red_hat"
      end
      if id == Gosu::KB_2 && @local_player.coins >= 15
        @local_player.coins -= 15
        @local_player.clothes["shirt"] = "red_shirt"
      end
    end
  end

  def button_up(id)
    @last_key = nil if @last_key == id
  end

  def button_down_id
    (Gosu::KB_A..Gosu::KB_Z).find { |id| button_down?(id) } || (Gosu::KB_0..Gosu::KB_9).find { |id| button_down?(id) }
  end
end

window = GameWindow.new
window.show
