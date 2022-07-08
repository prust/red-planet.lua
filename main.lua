-- Red Planet Game Engine
-- A 2D game engine to make it fun & easy to build 2d top-down and side-scrolling games (platformers, shooters, etc)

-- priorities:
--   in-game level design (block placing)
--   encourages game designers to prototype & test game ideas with simple shapes before investing in artwork & animation
--   (in code) toggleable/configurable "behaviors" (components)

bump = require 'libs/bump'
anim8 = require 'libs/anim8'
baton = require 'libs/baton'

local entities = {}
local players = {}

local world
local win_w, win_h
local spritesheet
local player_quads
local tilesheet_quad
local scale = 1
local entity_speed = 7
local entity_max_speed = 14
local selection_color = {0, 0.55, 1, 1}
local tile_size = 32

-- types of entities
local PLAYER = 1
local BULLET = 2
local TURRET = 3
local ENEMY_BULLET = 4
local BLOCK = 5

if os.getenv("LOCAL_LUA_DEBUGGER_VSCODE") == "1" then
  require("lldebugger").start()
end

function love.load()
  love.window.setMode(0, 0) -- mode 0 sets to the width/height of desktop

  -- nearest neighbor (default is anti-aliasing)
  --love.graphics.setDefaultFilter('nearest')
  win_w, win_h = love.graphics.getDimensions()
  
  spritesheet = love.graphics.newImage('images/tilesheet.png')

  -- the tiles of tilesheet represent the first 3 players
  player_quads = {
    love.graphics.newQuad(0, 0, 32, 64, spritesheet:getDimensions()),
    love.graphics.newQuad(6 * 16, 0, 16, 16, spritesheet:getDimensions()),
    love.graphics.newQuad(5 * 16, 1 * 16, 16, 16, spritesheet:getDimensions())
  }

  -- grass_quad = love.graphics.newQuad(32, 32, 32, 32, spritesheet:getDimensions())
  tilesheet_quad = love.graphics.newQuad(0, 0, 32 * 10, 32 * 2, spritesheet:getDimensions())

  love.graphics.setBackgroundColor(0.21, 0.18, 0.18)

  local joysticks = love.joystick.getJoysticks()
  local num_players = #joysticks
  if num_players == 0 then
    num_players = 1 -- if there are no joysticks, fallback to one keyboard/mouse player
  end

  for i=1, num_players do
    local player = {
      x = 0,
      y = 0,
      dx = 0,
      dy = 0,
      w = tile_size,
      h = tile_size * 2,
      rot = 0,
      aim_x = nil,
      aim_y = nil,
      sel_x = nil,
      sel_y = nil,
      tile_ix = 1,
      focus_area = 'level', -- or 'tilesheet' or 'behaviors' or 'systems'
      placing_mode = true,
      is_input_controlled = true,
      quad = player_quads[i],
      type = PLAYER,
      health = 3,

      -- "A" is the jump button when the focus is on the level (right trigger is for placing blocks)
      -- but when the focus is on the tilesheet or on the behaviors or systems, then "A" is 'select' and "B" is 'back'
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
      
          place = {'mouse:1', 'axis:triggerright+', 'key:ralt'},
          jump_or_select = {'key:space', 'button:a'},
          back = {'button:b'},
          focus_right = {'button:rightshoulder'},
          focus_left = {'button:leftshoulder'},
        },
        pairs = {
          move = {'move_left', 'move_right', 'move_up', 'move_down'},
          aim = {'aim_left', 'aim_right', 'aim_up', 'aim_down'}
        },
        deadzone = 0.5,
        joystick = joysticks[i]
      })
    }
    table.insert(players, player)
  end

  -- https://www.leshylabs.com/apps/sfMaker/
  -- shot: w=Square,W=22050,f=1045,_=-0.9,b=0,r=0.1,s=52,S=21.23,z=Down,g=0.243,l=0.293
  -- place: w=Noise,f=203.836,v=180.025,V=663.565,t=118.076,T=0.097,_=0.08,d=124.898,D=0.195,p=1.788,a=0.2,A=1.4,b=0.8,r=2.8,s=25,S=1.477,z=Down,g=0.564,l=0.091,e=Sawtooth,N=998,F=231.972,B=Fixed,E=4948
  place_src = love.audio.newSource('sfx/place.wav', 'static')

  world = bump.newWorld(64)

  for i=1, #players do
    local player = players[i]
    player.x = 10 * 16
    player.y = 10 * 16
    world:add(player, player.x, player.y, player.w, player.h)
    table.insert(entities, player)
  end

  -- create a single block under the player, so the player doesn't immediately fall
  local block = {
    x = 5 * tile_size,
    y = 7 * tile_size,
    dx = 0,
    dy = 0,
    w = tile_size,
    h = tile_size,
    quad = love.graphics.newQuad(tile_size, tile_size, tile_size, tile_size, spritesheet:getDimensions()),
    type = BLOCK
  }
  table.insert(entities, block)
  world:add(block, block.x, block.y, block.w, block.h)


  love.window.setFullscreen(true)
  love.mouse.setVisible(false)
end

function love.update(dt)
  -- Hande player input & player shooting
  local block_indexes_to_remove = {}
  for i=1, #entities do
    local entity = entities[i]

    if entity.input then
      entity.input:update()

      local aim_x, aim_y = entity.input:get('aim')
      if aim_x ~= 0 and aim_y ~= 0 then
        local len = math.sqrt(aim_x^2 + aim_y^2)
        aim_x = aim_x / len
        aim_y = aim_y / len
        entity.aim_x = aim_x
        entity.aim_y = aim_y
      end

      if entity.aim_x and entity.aim_y then
        entity.sel_x = math.floor((entity.x + (entity.w / 2) + (entity.aim_x * 50)) / 32)
        entity.sel_y = math.floor((entity.y + (entity.h / 2) + (entity.aim_y * 50)) / 32)
      else
        entity.sel_x = nil
        entity.sel_y = nil
      end

      -- for ships (and cars?) rotate the image
      -- if aim_x ~= 0 or aim_y ~= 0 then
      --   player.rot = math.atan2(aim_y, aim_x)
      -- end

      if entity.focus_area == 'level' then
        local dx, dy = entity.input:get('move')
        entity.dx = dx * entity_speed
      elseif entity.focus_area == 'tilesheet' then
        if entity.input:pressed('move_left') then
          entity.tile_ix = entity.tile_ix - 1
        elseif entity.input:pressed('move_right') then
          entity.tile_ix = entity.tile_ix + 1
        end
      end
      
      -- gravity
      entity.dy = entity.dy + 0.5
      
      -- jumping
      if entity.input:pressed('jump_or_select') then
        -- check if there's a block under the player, to jump from
        local is_block_under_player = false
        for j = 1, #entities do
          local candidate = entities[j]

          -- check for gaps between rectangles to detect collision
          if (candidate.type == BLOCK) and (candidate.x <= entity.x + entity.w) and (candidate.x + candidate.w >= entity.x) and (candidate.y <= entity.y + entity.h) and (candidate.h + candidate.y >= entity.y) then
            is_block_under_player = true
          end
        end
        if is_block_under_player then
          entity.dy = -10
        end
      end

      -- cap the player velocity
      if entity.dx > 0 then
        entity.dx = math.min(entity.dx, entity_max_speed)
      elseif entity.dx < 0 then
        entity.dx = math.max(entity.dx, -entity_max_speed)
      end
      if entity.dy > 0 then
        entity.dy = math.min(entity.dy, entity_max_speed)
      elseif entity.dy < 0 then
        entity.dy = math.max(entity.dy, -entity_max_speed)
      end
      
      if entity.sel_x and entity.sel_y then
        local block
        local is_block_already = false
        local block_ix = nil
        local dest_x = entity.sel_x * 32
        local dest_y = entity.sel_y * 32
        if entity.input:down('place') then
          for j = 1, #entities do
            local candidate = entities[j]
            if candidate.x == dest_x and candidate.y == dest_y and candidate.type == BLOCK then
              is_block_already = true
              block_ix = j
              block = candidate
            end
          end
        end

        if entity.input:pressed('place') then
          entity.placing_mode = not is_block_already -- "placing" if a block isn't alreday there, "removing" if it is
        end
        
        if entity.input:down('place') then
          if (entity.placing_mode and not is_block_already) or (not entity.placing_mode and is_block_already) then
            -- make shooting sound
            if (place_src:isPlaying()) then
              place_src:stop()
            end
            place_src:play()

            -- create block
            if entity.placing_mode then
              block = {
                x = dest_x,
                y = dest_y,
                dx = 0,
                dy = 0,
                w = 32,
                h = 32,
                quad = love.graphics.newQuad(entity.tile_ix * 32, 32, 32, 32, spritesheet:getDimensions()),
                type = BLOCK
              }
              table.insert(entities, block)

              -- TODO: due to scaling it should be more than / 2...
              world:add(block, block.x, block.y, block.w, block.h)
            -- remove block
            else
              table.insert(block_indexes_to_remove, block_ix)
              world:remove(block)
            end
          end
        end
      end

      if entity.input:pressed('focus_right') or entity.input:pressed('focus_left') then
        if entity.focus_area == 'level' then
          entity.focus_area = 'tilesheet'
        else
          entity.focus_area = 'level'
        end
      end
    end
  end

  -- iterate backwards over indexes so removal doesn't mess up other indexes
  -- DRY violation w/ backwards iteration post-collisions
  table.sort(block_indexes_to_remove)
  for i = #block_indexes_to_remove, 1, -1 do
    table.remove(entities, block_indexes_to_remove[i])
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

  -- calc the avg x,y across all players
  local sum_player_x = 0
  local sum_player_y = 0
  for i = 1, #players do
    sum_player_x = sum_player_x + players[i].x
    sum_player_y = sum_player_y + players[i].y
  end

  -- translation is commented out for now b/c it makes it hard to see the player is moving
  -- tx = -(sum_player_x / #players) + ((win_w/2) / scale)
  -- ty = -(sum_player_y / #players) + ((win_h/2) / scale)
  tx = 0
  ty = 0
  
  love.graphics.setColor(1, 1, 1, 1)

  -- translate to that average x,y
  love.graphics.translate(tx * scale, ty * scale)
  --love.graphics.scale(sx, sy)
  
  for i=1, #entities do
    local entity = entities[i]
    love.graphics.draw(spritesheet, entity.quad, scale * (entity.x + entity.w / 2), scale * (entity.y + entity.h / 2), entity.rot or 0, scale, scale, entity.w / 2,  entity.h / 2)
    
    -- draw selected square
    if entity.sel_x and entity.sel_y then
      love.graphics.setColor(0.3, 0.3, 0.3)
      love.graphics.rectangle('line', scale * entity.sel_x * 32, scale * entity.sel_y * 32, 32, 32)
      love.graphics.setColor(1, 1, 1)
    end
  end

  -- map:bump_draw(world, tx, ty, sx, sy) -- debug the collision map

  love.graphics.reset()
  love.graphics.setBackgroundColor(0.21, 0.18, 0.18) -- have to reset bgcolor after a reset()

  -- draw tilesheet
  local x, y, w, h = tilesheet_quad:getViewport()
  local tilesheet_x = scale * ((win_w - w) / 2)
  local tilesheet_y = scale * (win_h - 32 - h)
  love.graphics.draw(spritesheet, tilesheet_quad, tilesheet_x, tilesheet_y)
  love.graphics.setColor(0.3, 0.3, 0.3)
  love.graphics.rectangle('line', tilesheet_x, tilesheet_y, w, h)

  -- draw selected tile in tilesheet for each player
  love.graphics.setColor(1, 1, 1)
  for i = 1, #players do
    local player = players[i]
    love.graphics.rectangle('line', tilesheet_x + player.tile_ix * 32, tilesheet_y + 32, 32, 32)
  end

  -- draw sidebar
  -- love.graphics.setColor(0.2, 0.2, 0.2)
  -- love.graphics.rectangle('fill', 0, 0, 300, win_h)
  -- love.graphics.setColor(0.3, 0.3, 0.3)
  -- love.graphics.rectangle('line', 0, 0, 300, win_h)

  love.graphics.setColor(0.3, 0.3, 0.3)
  love.graphics.print("FPS: " .. tostring(love.timer.getFPS()), 10, 10)

  -- draw a ship for each unit of health the player has
  -- for i=1, #players do
  --   local player = players[i]
  --   for x = 1, player.health do
  --     love.graphics.draw(spritesheet, player.quad, -10 + 20 * x, 10 + 20 * i, 0, 1, 1)
  --   end
  -- end
end

function love.resize(w, h)
  --map:resize(w*8, h*8)
  win_w = w
  win_h = h
end

function love.keypressed(key, scancode, isrepeat)
  if key == "escape" then
    love.event.quit()
  end
end
