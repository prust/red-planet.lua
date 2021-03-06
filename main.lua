-- Generic red planet game engine
-- Initially for space shooters, then top-down shooters & eventually platformer shooters

-- TODO:
-- Start with $0
-- Left Panel with each kind of ships & number available, 2 missile launchers available, 1 factory available
   -- Start with 2 4-width ships, 3 3-width ships and 4 2-width ships
-- click once to select, click on the map to place -- have to place all things
-- factory & missile launchers need to be "your" side
-- ships cost 3, 6, 9
-- guns include small radar by default
-- ships need to be upgraded to get radar

-- once all players are done, 

-- Place ships by clicking
-- Scroll wheel to zoom, Cmd/Ctrl + -
-- Arrows keys to scroll
-- Mini versions of ships in top-left

-- IDEAS:
-- Up to 5 players (4 controllers + keyboard/mouse)
-- healing
-- shot energy that depletes & recharges
-- shield energy that depletes & recharges
-- enemy fire in bursts
-- Collectables (keys/doors, but custom text/images?)
-- Parameterized enemy types (turrets vs moving; speeds, shot intervals)
-- Win state (get to end w/ required collectables?)
-- Mini-map
-- fog/discovered state
-- turret-type enemies that don't move
-- heat-seeking bullets/missiles
-- intelligent aiming enemies (take into account your speed & aim where you'll be)

bump = require 'libs/bump'
sti = require 'libs/sti'
anim8 = require 'libs/anim8'
baton = require 'libs/baton'
sock = require 'libs/sock'
bitser = require "libs/bitser"

local level = 2

local entities = {}
local map, world
local player_quads, shot_quad, enemy_shot_quad
local win_w, win_h
local spritesheet
local shot_src
local bullet_speed = 10
local turret_bullet_speed = 4 -- 4=med; 8=hard
local player_speed = 7
local enemy_speed = 2 -- 2=med; 4=hard
local enemy_starting_health = 1
local scale = 1.5

local PLAYER = 1
local BULLET = 2
local TURRET = 3
local ENEMY_BULLET = 4

local players

local server = nil
local client = nil
local client_connected = false
local tile_x = -1
local tile_y = -1
local ships = {}
local ghosted_ship = nil

-- this slows the game; only run it when you're ready to drop into debugging
-- require("mobdebug").start()

function love.load()
  love.window.setMode(0, 0) -- 0 sets to width/height of desktop
  -- nearest neighbor makes player look ugly at most rotations
  -- BUT if I turn it off & do anti-aliasing, then I need 1px padding around sprites!
  love.graphics.setDefaultFilter('nearest') 
  win_w, win_h = love.graphics.getDimensions()
  
  spritesheet = love.graphics.newImage('images/battleship hexagons.png')
  ship_quads = {
    love.graphics.newQuad(0, 7 * 16, 4 * 16, 16, spritesheet:getDimensions()),
    love.graphics.newQuad(0, 8 * 16, 3 * 16, 16, spritesheet:getDimensions()),
    love.graphics.newQuad(0, 9 * 16, 2 * 16, 16, spritesheet:getDimensions())
  }
  -- player_quads = {
  --   love.graphics.newQuad(5 * 16, 0, 16, 16, spritesheet:getDimensions()),
  --   love.graphics.newQuad(6 * 16, 0, 16, 16, spritesheet:getDimensions()),
  --   love.graphics.newQuad(5 * 16, 1 * 16, 16, 16, spritesheet:getDimensions())
  -- }
  -- turret_quad = love.graphics.newQuad(9 * 16, 0, 16, 16, spritesheet:getDimensions())
  -- shot_quad = love.graphics.newQuad(8 * 16, 0, 2, 2, spritesheet:getDimensions())
  -- enemy_shot_quad = love.graphics.newQuad(8 * 16, 1 * 16, 2, 2, spritesheet:getDimensions())
  love.graphics.setBackgroundColor(0.15, 0.15, 0.15)

  local joysticks = love.joystick.getJoysticks()
  local num_players = #joysticks
  if num_players == 0 then
    num_players = 1
  end
  players = {}
  for i=1, num_players do
    local player = {
      x = 0,
      y = 0,
      dx = 0,
      dy = 0,
      w = 16,
      h = 16,
      rot = 0,
      quad = null, -- player_quads[i],
      type = PLAYER,
      health = 3,
      input = baton.new({
        controls = {
          move_left = {'key:a', 'axis:leftx-', 'button:dpleft'},
          move_right = {'key:d', 'axis:leftx+', 'button:dpright'},
          move_up = {'key:w', 'axis:lefty-', 'button:dpup'},
          move_down = {'key:s', 'axis:lefty+', 'button:dpdown'},
          
          -- TODO: add mouse-aiming to baton library
          aim_left = {'axis:rightx-', 'key:left'},
          aim_right = {'axis:rightx+', 'key:right'},
          aim_up = {'axis:righty-', 'key:up'},
          aim_down = {'axis:righty+', 'key:down'},
      
          shoot = {'mouse:1', 'axis:triggerright+', 'key:ralt'},
          zoom_in = {'button:rightshoulder'},
          zoom_out = {'button:leftshoulder'}
        },
        pairs = {
          move = {'move_left', 'move_right', 'move_up', 'move_down'},
          aim = {'aim_left', 'aim_right', 'aim_up', 'aim_down'}
        },
        joystick = joysticks[i]
      })
    }
    table.insert(players, player)
  end

  -- https://www.leshylabs.com/apps/sfMaker/
  -- w=Square,W=22050,f=1045,_=-0.9,b=0,r=0.1,s=52,S=21.23,z=Down,g=0.243,l=0.293
  shot_src = love.audio.newSource('sfx/shot.wav', 'static')

  pcall(playRandomSong)

  -- find-and-replace regex to transform .tsv from http://donjon.bin.sh/d20/dungeon/index.cgi
  -- into lua tiled format: [A-Z]+\t -> "0, " 
  world = bump.newWorld(64)
  map = sti("maps/battleship.lua", { "bump" })
  
  for k, object in pairs(map.objects) do
    if object.name == "player_spawn" then
      for i=1, #players do
        local player = players[i]
        player.x = object.x
        player.y = object.y
        world:add(player, player.x, player.y, player.w, player.h)
        table.insert(entities, player)
      end
    elseif object.name == "enemy" then
      local enemy = {
        x = object.x,
        y = object.y,
        dx = 0,
        dy = 0,
        w = 16,
        h = 16,
        health = enemy_starting_health,
        quad = turret_quad,
        rot = 0,
        type = TURRET
      }
      world:add(enemy, enemy.x, enemy.y, enemy.w, enemy.h)
      table.insert(entities, enemy)
    end
  end
  
  --map:removeLayer("Objects")

  map:bump_init(world)

--  love.window.setFullscreen(true)
  -- love.mouse.setVisible(false)
end

function playRandomSong()
  local songs = {
    'celldweller_tim_ismag_tough_guy.wav',
    'celldweller_just_like_you.wav',
    'celldweller_into_the_void.wav',
    'celldweller_end_of_an_empire.wav',
    'celldweller_down_to_earth.wav'
  }
  
  math.randomseed(os.time())
  local song = songs[math.random(#songs)]
  local song_src = love.audio.newSource('music/' .. song, "stream")
  song_src:play()
end

local turret_timer = 0
function love.update(dt)
  turret_timer = turret_timer + dt
  map:update(dt)

  -- Handle turret shooting every 1 seconds
  if turret_timer >= 1 then
    turret_timer = turret_timer - 1
    for i = 1, #entities do
      if entities[i].type == TURRET then
        local turret = entities[i]

        -- rudimentary calc to determine which player is closest
        local dist_closest_player = 1000 / scale
        local closest_player = nil
        for i = 1, #players do
          local dist = math.abs(players[i].x - turret.x) + math.abs(players[i].y - turret.y)
          if dist < dist_closest_player then
            dist_closest_player = dist
            closest_player = players[i]
          end
        end

        if closest_player and dist_closest_player < 1000 / scale then
          turret.rot = math.atan2(closest_player.y - turret.y, closest_player.x - turret.x)

          turret.dx = enemy_speed * math.cos(turret.rot)
          turret.dy = enemy_speed * math.sin(turret.rot)

          local bullet = {
            x = turret.x,
            y = turret.y,
            dx = turret_bullet_speed * math.cos(turret.rot),
            dy = turret_bullet_speed * math.sin(turret.rot),
            w = 2,
            h = 2,
            quad = enemy_shot_quad,
            type = ENEMY_BULLET -- TODO: use bitwise operations to add drawable/damageable/etc
          }
          table.insert(entities, bullet)

          world:add(bullet, bullet.x, bullet.y, bullet.w, bullet.h)

          if (shot_src:isPlaying()) then
            shot_src:stop()
          end
          shot_src:play()
        end
      end
    end

    if server then
      server:update()
    end

    if client then
      client:update()
    end
  end

  -- Hande player input & player shooting
  for i=1, #players do
    local player = players[i]
    player.input:update()
    local aim_x, aim_y = player.input:get('aim')
    if aim_x ~= 0 or aim_y ~= 0 then
      player.rot = math.atan2(aim_y, aim_x)
    end

    player.dx, player.dy = player.input:get('move')
    player.dx = player.dx * player_speed
    player.dy = player.dy * player_speed

    -- only first player can zoom in/out
    if i == 1 then
      if player.input:pressed('zoom_in') then
        scale = scale * 1.5
      end

      if player.input:pressed('zoom_out') then
        scale = scale / 1.5
      end
    end
    
    if player.input:pressed('shoot') then
      -- make shooting sound
      if (shot_src:isPlaying()) then
        shot_src:stop()
      end
      shot_src:play()

      -- create bullet going in the right direction
      local bullet = {
        x = player.x + player.w/2,
        y = player.y + player.h/2,
        dx = bullet_speed * math.cos(player.rot),
        dy = bullet_speed * math.sin(player.rot),
        w = 2,
        h = 2,
        quad = shot_quad,
        type = BULLET
      }
      table.insert(entities, bullet)

      -- TODO: due to scaling it should be more than / 2...
      world:add(bullet, bullet.x, bullet.y, bullet.w, bullet.h)
    end
  end

  -- Handle collisions & removals
  -- remove all entities *after* iterating, so we don't mess up iteration
  local entity_ix_to_remove = {}
  local entities_to_remove = {}

  for i = 1, #entities do
    local entity = entities[i]
    local cols
    entity.x, entity.y, cols = world:move(entity, entity.x + entity.dx, entity.y + entity.dy, getCollType)

    for j = 1, #cols do
      local col = cols[j]
      if entity.type == BULLET then
        if col.other.type == TURRET then
          col.other.health = col.other.health - 1
          if col.other.health <= 0 then
            local turret_ix = indexOf(entities, col.other)
            table.insert(entity_ix_to_remove, turret_ix)
            table.insert(entities_to_remove, col.other)
          end
        end

        if col.other.type ~= PLAYER then
          table.insert(entity_ix_to_remove, i)
          table.insert(entities_to_remove, entity)
          break
        end
      elseif entity.type == ENEMY_BULLET then
        if col.other.type == PLAYER then
          col.other.health = col.other.health - 1
          if col.other.health <= 0 then
            local player_ix = indexOf(entities, col.other)
            table.insert(entity_ix_to_remove, player_ix)
            table.insert(entities_to_remove, col.other)

            -- also remove player from players table
            table.remove(players, indexOf(players, col.other))
          end
        end
        
        if col.other.type ~= TURRET then
          table.insert(entity_ix_to_remove, i)
          table.insert(entities_to_remove, entity)
          break
        end
      end
    end
  end

  -- iterate backwards over indexes so removal doesn't mess up other indexes
  table.sort(entity_ix_to_remove)
  for i = #entity_ix_to_remove, 1, -1 do
    table.remove(entities, entity_ix_to_remove[i])
  end

  -- have to remove items from the world later (here) as well
  for i = 1, #entities_to_remove do
    world:remove(entities_to_remove[i])
  end
end

function indexOf(table, item)
  for i = 1, #table do
    if table[i] == item then
      return i
    end
  end
end

function getCollType(item, other)
  if other.name == 'player_spawn' or item.name == 'player_spawn' or other.name == 'enemy' or item.name == 'enemy' then
    return nil
  elseif item.type == BULLET or other.type == BULLET or item.type == ENEMY_BULLET or other.type == ENEMY_BULLET then
    return "cross"
  else
    return "slide"
  end
end

function love.draw()
  love.graphics.setColor(1, 1, 1, 1)
  local sum_player_x = 0
  local sum_player_y = 0
  for i = 1, #players do
    sum_player_x = sum_player_x + players[i].x
    sum_player_y = sum_player_y + players[i].y
  end
  tx = -(sum_player_x / #players) + ((win_w/2) / scale)
  ty = -(sum_player_y / #players) + ((win_h/2) / scale)

  -- this is a hacky work-around for a bug with the STI canvas size clipping issue at far-out zooms
  -- it keeps the map anchored in the top-left of the screen at far-out zooms
  if tx > 0 then
    tx = 0
  end
  if ty > 0 then
    ty = 0
  end
  
  map:draw(tx, ty, scale, scale)
  
  love.graphics.setColor(255, 255, 225, 255)
  --love.graphics.scale(sx, sy)
  love.graphics.translate(tx * scale, ty * scale)
  
  local num_turrets = 0
  for i=1, #entities do
    local entity = entities[i]
    love.graphics.draw(spritesheet, entity.quad, scale * (entity.x + entity.w / 2), scale * (entity.y + entity.h / 2), entity.rot or 0, scale, scale, entity.w / 2,  entity.h / 2)
    if entity.type == TURRET then
      num_turrets = num_turrets + 1
    end
  end
  -- map:bump_draw(world, tx, ty, sx, sy) -- debug the collision map

  if ghosted_ship then
    local ghost_x, ghost_y = map:convertTileToPixel(ghosted_ship.tile_x, ghosted_ship.tile_y)
    -- TODO:
      -- I need to actually draw at the correct scale
      -- and probably need to multiply by the scale but maybe the map is doing that for me? it's not rendering in *quite* the right hex...
      -- then on click I need to create a real permanent Entity out of the ghost and tell the server where it is
    -- ghost_x = ghost_x * scale
    -- ghost_y = ghost_y * scale
    love.graphics.draw(spritesheet, ghosted_ship.quad, ghost_x, ghost_y)

  end

  love.graphics.reset()
  love.graphics.setBackgroundColor(0.15, 0.15, 0.15) -- have to reset bgcolor after a reset()

  -- draw sidebar
  love.graphics.setColor(0.2, 0.2, 0.2)
  love.graphics.rectangle('fill', 0, 0, 300, win_h)
  love.graphics.setColor(0.3, 0.3, 0.3)
  love.graphics.rectangle('line', 0, 0, 300, win_h)

  love.graphics.setColor(0.6, 0.6, 0.6)

  love.graphics.print("FPS: " .. tostring(love.timer.getFPS()), 10, 10)
  if server then
    love.graphics.print("SERVER MODE", 10, 25)
  end

  if client_connected then
    love.graphics.print("Connected.", 10, 25)
  elseif client then
    love.graphics.print("Connecting...", 10, 25)
  end

  love.graphics.print('Place your ships:', 10, 50)
  
  love.graphics.draw(spritesheet, ship_quads[1], 10, 75)
  love.graphics.draw(spritesheet, ship_quads[2], 10, 90)
  love.graphics.draw(spritesheet, ship_quads[3], 10, 105)

  -- draw a ship for each unit of health the player has
  -- for i=1, #players do
  --   local player = players[i]
  --   for x = 1, player.health do
  --     love.graphics.draw(spritesheet, player.quad, -10 + 20 * x, 10 + 20 * i, 0, 1, 1)
  --   end
  -- end
end

function love.resize(w, h)
  map:resize(w*8, h*8)
  win_w = w
  win_h = h
end

function love.mousemoved(x, y, dx, dy, istouch)
  local new_tile_x, new_tile_y = map:convertPixelToTile(x / scale, y / scale)
  new_tile_x = math.floor(new_tile_x)
  new_tile_y = math.floor(new_tile_y)
  if new_tile_x >= 1 and new_tile_y >=1 then
    if new_tile_x ~= tile_x or new_tile_y ~= tile_y then
      if not ghosted_ship then
        ghosted_ship = {
          tile_x = new_tile_x,
          tile_y = new_tile_y,
          quad = ship_quads[1]
        }
      else
        ghosted_ship.tile_x = new_tile_x
        ghosted_ship.tile_y = new_tile_y
      end
      
      -- if server then
      --   server:sendToAll('setTile', {tile_x=new_tile_x, tile_y=new_tile_y})
      -- end
    end
  end
end

function setTile(new_tile_x, new_tile_y)
  if tile_x > -1 and tile_y > -1 then
    map:setLayerTile('Terrain', math.floor(tile_x), math.floor(tile_y), 1)
  end

  map:setLayerTile('Terrain', math.floor(new_tile_x), math.floor(new_tile_y), 2)
  tile_x = new_tile_x
  tile_y = new_tile_y
end

-- function love.mousemoved(x, y, dx, dy, istouch)
--   local tile_x, tile_y = map:convertPixelToTile(x, y)
--   map:setLayerTile('Terrain', tile_x, tile_y, 2)
-- end

function love.keypressed(key, scancode, isrepeat)
  if key == "escape" then
    love.event.quit()
  end

  if key == 's' then
    -- Creating a server on any IP, port 22122
    server = sock.newServer("*", 22122)
    server:setSerialization(bitser.dumps, bitser.loads)

    -- Called when someone connects to the server
    server:on("connect", function(data, client)
        -- Send a message back to the connected client
        local msg = "Hello from the server!"
        client:send("hello", msg)
    end)
  end

  if key == 'c' then
    -- Creating a new client on localhost:22122
    -- to connect to IP addr: newClient("198.51.100.0", 22122)
    client = sock.newClient("localhost", 22122) -- 10.0.0.93", 22122)    
    client:setSerialization(bitser.dumps, bitser.loads)

    -- Called when a connection is made to the server
    client:on("connect", function(data)
        print("Client connected to the server.")
    end)
    
    -- Called when the client disconnects from the server
    client:on("disconnect", function(data)
        print("Client disconnected from the server.")
    end)

    client:on('setTile', function(data)
      setTile(data.tile_x, data.tile_y)
    end)

    -- Custom callback, called whenever you send the event from the server
    client:on("hello", function(msg)
        print("The server replied: " .. msg)
        client_connected = true
    end)

    client:connect()
    
    --  You can send different types of data
    client:send("greeting", "Hello, my name is Inigo Montoya.")
    client:send("isShooting", true)
    client:send("bulletsLeft", 1)
    client:send("position", {
        x = 465.3,
        y = 50,
    })
  end
end
