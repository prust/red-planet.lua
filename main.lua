-- Red Planet Game Engine
-- A 2D game engine to make it fun & easy to build 2d top-down and side-scrolling games (platformers, shooters, etc)

-- Owen's Wish List:
-- [x] Have to hit "X" button when you're touching the goal to win
-- [x] Make enemies move

-- Peter's Wish List:
-- [x] Keep the aim (for selecting blocks) centered on the current player
--     - but make the selection move when the joystick is pushed from center (experiment w/ diff speeds)
--     - and stop moving (but not go back to the player) when it is centered
--     - and don't allow the selection to go off screen
--     - that keeps all the benefits of simultaneously playing & editing, and editing with controllers
-- [ ] Make the viewport move with a 1/4-screen padding in all directions
-- [ ] Add a virtual border 1/3-screen in all directions from the nearest content
--     - so players & enemies don't fall forever
--     - there'll be an option to make them die (and maybe respawn) if they hit a border
--     - but the default behavior will be for the border to be "solid" (can walk/jump on it, bounce off of it, etc)

-- Vector Editor Improvements:
-- [ ] Allow creating new sprites, in addition to the 3 built-ins (enemy/stone/goal)
-- [ ] Allow editing the player sprite(s)
-- [ ] Allow creating new layers, changing/setting the color of a layer, changing the order of layers

-- Other Ideas:
--   in-game level design (block placing)
--   encourages game designers to prototype & test game ideas with simple shapes before investing in artwork & animation
--   (in code) toggleable/configurable "behaviors" (components)

-- include dialog/narrative support via talkies lib (consider Erogodic as well)
-- we'll need to pick something for the UI, it'd be nice to avoid nuklear/imgui embedding
-- pure lua/love alternatives seem to be:
-- * airstruck/luigi (the example looks like retained mode)
-- * linux-man/LoveFrames (uses middleclass)
-- * vrld/suit (immediate mode)
-- I'd like to try SUIT, since I want experience w/ immediate-mode GUIs
-- (and eventually would like to go in the direction of layout.c/quarks and the flutter architecture/pipeline but without its OOP & layers of abstractions)

if os.getenv("LOCAL_LUA_DEBUGGER_VSCODE") == "1" then
  require("lldebugger").start()
end

bump = require 'libs/bump'
anim8 = require 'libs/anim8'
baton = require 'libs/baton'
bitser = require 'libs/bitser'

vector_editor = require 'vector-editor'

local curr_level_file = 'owen-pit.dat' -- 'dad_level_01.dat'
local level = {
  red_planet_ver = 0,
  entities = {}
}
local entities = level.entities
local players = {}

local world
local win_w, win_h
local spritesheet
local player_quads
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
local ENEMY = 6
local GOAL = 7
local PORTAL = 8

local blocks_to_place = {'stone', 'enemy', 'goal', 'portal1', 'portal2'}
local block_to_place_ix = 1

local confirm = nil
local is_paused = false

-- some built-in default vector graphics
local vectors = {
  stone = {
    {color = {0.325, 1, 0.957}, style = 'fill', vertices = {0,0, 1,0, 1,1/4, 0,1/4}},
    {color = {0.204, 0.204, 0.204}, style = 'fill', vertices = {0,1/4, 1,1/4, 1,1, 0,1}}
  },
  enemy = {
    {color = {0.29, 0, 1}, style = 'line', is_closed = true, vertices = {0,0, 0,1, 1,1, 1,0}}, -- , 0,0
    {color = {0.63, 0, 1}, style = 'fill', vertices = {1/4,1/2, 1/2,1/4, 3/4,1/2, 1/2,3/4}}
  },
  goal = {
    {color = {0, 0.76, 1}, style = 'fill', vertices = {0,1, 1/2,0, 1,1, 3/4,3/4, 1/2,1, 1/4,3/4}}
  },
  portal1 = {
    {color = {1, 0, 0.815}, style = 'fill', vertices = {4/10,0, 6/10,0, 6/10,1, 4/10,1}, hit = {4/10,0,2/10,1}}
  },
  portal2 = {
    {color = {0.403, 0.831, 1}, style = 'fill', vertices = {4/10,0, 6/10,0, 6/10,1, 4/10,1}, hit = {4/10,0,2/10,1}}
  }
}

if os.getenv("LOCAL_LUA_DEBUGGER_VSCODE") == "1" then
  require("lldebugger").start()
end

function love.load()
  love.window.setMode(0, 0) -- mode 0 sets to the width/height of desktop

  -- nearest neighbor (default is anti-aliasing)
  --love.graphics.setDefaultFilter('nearest')
  win_w, win_h = love.graphics.getDimensions()
  
  spritesheet = love.graphics.newImage('images/tilesheet.png')

  love.graphics.setBackgroundColor(0, 0, 0)

  local joysticks = love.joystick.getJoysticks()
  local num_players = #joysticks
  if num_players == 0 then
    num_players = 1 -- if there are no joysticks, fallback to one keyboard/mouse player
  end

  local player_inputs = {}
  for i=1, num_players do
    table.insert(player_inputs, bitser.register('player_' .. i .. '_input', baton.new({
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
        action = {'key:return', 'button:x'},
        back = {'button:b'},
        focus_right = {'button:rightshoulder'},
        focus_left = {'button:leftshoulder'},
      },
      pairs = {
        move = {'move_left', 'move_right', 'move_up', 'move_down'},
        aim = {'aim_left', 'aim_right', 'aim_up', 'aim_down'}
      },
      deadzone = 0.2,
      joystick = joysticks[i]
    })))
  end

  -- https://www.leshylabs.com/apps/sfMaker/
  -- shot: w=Square,W=22050,f=1045,_=-0.9,b=0,r=0.1,s=52,S=21.23,z=Down,g=0.243,l=0.293
  -- place: w=Noise,f=203.836,v=180.025,V=663.565,t=118.076,T=0.097,_=0.08,d=124.898,D=0.195,p=1.788,a=0.2,A=1.4,b=0.8,r=2.8,s=25,S=1.477,z=Down,g=0.564,l=0.091,e=Sawtooth,N=998,F=231.972,B=Fixed,E=4948
  place_src = love.audio.newSource('sfx/place.wav', 'static')

  world = bump.newWorld(64)

  -- load level
  if love.filesystem.getInfo(curr_level_file) then
    level = bitser.loadLoveFile(curr_level_file)
    entities = level.entities

    for i = 1, #entities do
      local entity = entities[i]
      world:add(entity, entity.x, entity.y, entity.w, entity.h)
      if entity.type == PLAYER then
        table.insert(players, entity)
      end
    end
  else
    -- TODO: determine if the saved level has more or fewer players
    -- spawn more/fewer, as necessary?
    -- if there are fewer players than before, probably best to rehydrate all of them but leave them frozen?
    for i=1, num_players do
      local player = {
        x = 0,
        y = 0,
        dx = 0,
        dy = 0,
        w = tile_size,
        h = tile_size,
        rot = 0,
        aim_x = 0,
        aim_y = 0,
        sel_x = nil,
        sel_y = nil,
        tile_ix = 1,
        placing_mode = true,
        is_input_controlled = true,
        shape = 'rect',
        color = {0, 0.62, 0.16},
        type = PLAYER,
        health = 3,

        input = player_inputs[i]
      }
      
      table.insert(players, player)
    end

    -- create new level
    for i=1, #players do
      local player = players[i]
      player.x = 5 * tile_size
      player.y = 5 * tile_size
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
      shape = 'stone',
      color = {0.2, 0.5, 0.2},
      type = BLOCK
    }
    table.insert(entities, block)
    world:add(block, block.x, block.y, block.w, block.h)  
  end

  love.window.setFullscreen(true)
  love.mouse.setVisible(false)
end

function love.update(dt)
  if is_paused then
    return
  end

  -- Hande player input & player shooting
  local block_indexes_to_remove = {}
  for i=1, #entities do
    local entity = entities[i]

    if entity.input then
      entity.input:update()

      local aim_x, aim_y = entity.input:get('aim')
      local delta_x = (aim_x * 4)^2
      if aim_x < 0 then
        delta_x = -delta_x
      end
      local delta_y = (aim_y * 4)^2
      if aim_y < 0 then
        delta_y = -delta_y
      end
      entity.aim_x = entity.aim_x + delta_x
      entity.aim_y = entity.aim_y + delta_y

      -- ensure the player's selection box never goes offscreen
      local round_win_w = math.floor(win_w / tile_size) * tile_size
      local round_win_h = math.floor(win_h / tile_size) * tile_size
      entity.aim_x = clamp(entity.aim_x, -entity.x, win_w - entity.x - tile_size)
      entity.aim_y = clamp(entity.aim_y, -entity.y, win_h - entity.y - tile_size)
      
      entity.sel_x = math.floor((entity.x + (entity.w / 2) + entity.aim_x) / tile_size)
      entity.sel_y = math.floor((entity.y + (entity.h / 2) + entity.aim_y) / tile_size)

      -- for ships (and cars?) rotate the image
      -- if aim_x ~= 0 or aim_y ~= 0 then
      --   player.rot = math.atan2(aim_y, aim_x)
      -- end

      local dx, dy = entity.input:get('move')
      entity.dx = dx * entity_speed
      
      -- jumping
      if entity.input:pressed('jump_or_select') then
        -- check if there's a block under the player, to jump from
        local is_block_under_player = false
        for j = 1, #entities do
          local candidate = entities[j]

          -- check for gaps between rectangles to detect collision
          if (candidate.type == BLOCK or candidate.type == GOAL) and (candidate.x <= entity.x + entity.w) and (candidate.x + candidate.w >= entity.x) and (candidate.y <= entity.y + entity.h) and (candidate.h + candidate.y >= entity.y) then
            is_block_under_player = true
          end
        end
        if is_block_under_player then
          entity.dy = -10
        end
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
            if candidate.x == dest_x and candidate.y == dest_y then
              is_block_already = true
              block_ix = j
              block = candidate
            end
          end
        end

        if entity.input:pressed('place') then
          entity.placing_mode = not is_block_already -- "placing" if a block isn't already there, "removing" if it is
        end
        
        -- when placing enemy blocks, only place them once (if the button was pressed this frame)
        -- when placing all other blocks, place them if the button is still down
        local shape = blocks_to_place[block_to_place_ix];
        local should_place
        if shape == 'enemy' then
          should_place = entity.input:pressed('place')
        else
          should_place = entity.input:down('place')
        end

        if should_place then
          if (entity.placing_mode and not is_block_already) or (not entity.placing_mode and is_block_already) then
            -- make placing sound
            if (place_src:isPlaying()) then
              place_src:stop()
            end
            place_src:play()

            -- create block
            if entity.placing_mode then
              block = {
                x = dest_x,
                y = dest_y,
                dx = (shape == 'enemy') and 5 or 0,
                dy = 0,
                w = 32,
                h = 32,
                shape = shape,
                color = {0, 0.76, 1}
              }
              if block.shape == 'goal' then
                block.type = GOAL
              elseif block.shape == 'enemy' then
                block.type = ENEMY
              elseif block.shape == 'stone' then
                block.type = BLOCK
              elseif block.shape == 'portal1' or block.shape == 'portal2' then
                block.type = PORTAL
              end
              table.insert(entities, block)

              -- TODO: FIX THIS! hit area should be on the sprite as a whole, not specific shapes
              if vectors[block.shape][1].hit then
                local hit = vectors[block.shape][1].hit
                local hit_x = math.floor(hit[1] * tile_size)
                local hit_y = math.floor(hit[2] * tile_size)
                local hit_w = math.floor(hit[3] * tile_size)
                local hit_h = math.floor(hit[4] * tile_size)
                world:add(block, block.x+hit_x, block.y+hit_y, hit_w, hit_h)
              else
                world:add(block, block.x, block.y, block.w, block.h)
              end
            -- remove block
            else
              table.insert(block_indexes_to_remove, block_ix)
              world:remove(block)
            end
          end
        end
      end

      if entity.input:pressed('focus_right') then
        if block_to_place_ix < #blocks_to_place then
          block_to_place_ix = block_to_place_ix + 1
        end
      elseif entity.input:pressed('focus_left') then
        if block_to_place_ix > 1 then
          block_to_place_ix = block_to_place_ix - 1
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

    -- gravity (players & enemies)
    if entity.input or entity.shape == 'enemy' then
      entity.dy = entity.dy + 0.5
    end

    -- cap the entity velocity
    entity.dx = clamp(entity.dx, -entity_max_speed, entity_max_speed)
    entity.dy = clamp(entity.dy, -entity_max_speed, entity_max_speed)

    local cols
    if entity.dx ~= 0 or entity.dy ~= 0 then
      entity.x, entity.y, cols = world:move(entity, entity.x + entity.dx, entity.y + entity.dy, getCollType)

      for j = 1, #cols do
        local col = cols[j]
        if entity.type == ENEMY and col.other.type ~= PLAYER then
          if col.normal.x ~= 0 then
            entity.dx = -entity.dx -- bounce off things in horiz axis
          end
        end

        if entity.type == PLAYER and col.other.type == PORTAL and col.normal.x ~= 0 then
          local other_portal = nil
          for k = 1, #entities do
            local other = entities[k]
            if other ~= col.other and other.type == PORTAL and other.shape ~= col.other.shape then
              other_portal = other
            end
          end

          if other_portal ~= nil then
            entity.y = other_portal.y
            if entity.dx > 0 then
              local hit = vectors[other_portal.shape][1].hit
              local hit_x = math.floor(hit[1] * tile_size)
              local hit_w = math.floor(hit[3] * tile_size)
              entity.x = other_portal.x + hit_x + hit_w
            elseif entity.dx < 0 then
              local hit = vectors[other_portal.shape][1].hit
              local hit_x = math.floor(hit[1] * tile_size)
              local hit_w = math.floor(hit[3] * tile_size)
              entity.x = other_portal.x + hit_x - entity.w
            end
            world:update(entity, entity.x, entity.y)
          end
        end

        -- if player bonks on ceiling, stop vertical velocity
        if entity.type == PLAYER and col.normal.y > 0 then
          entity.dy = 0
        end
        
        if (entity.type == PLAYER and col.other.type == ENEMY) or
          (entity.type == ENEMY and col.other.type == PLAYER) then
            is_paused = true
            confirm = {text = 'Game Over (Esc to Quit, Enter to Respawn)'}
        end

        if entity.type == PLAYER and col.other.type == GOAL and entity.input:pressed('action') then
          is_paused = true
          confirm = {text = 'You won! (Esc to Quit, Enter to Respawn)'}
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

function clamp(val, min, max)
  if val < min then
    return min
  elseif val > max then
    return max
  else
    return val
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

  -- translate to that average x,y
  love.graphics.translate(tx * scale, ty * scale)
  --love.graphics.scale(sx, sy)
  
  for i=1, #entities do
    local entity = entities[i]
    if entity.shape then
      love.graphics.setColor(entity.color or {1, 1, 1})
      local style = entity.style or 'fill'
      local x = entity.x
      local y = entity.y

      local is_stone_above = false
      if entity.shape == 'stone' then
        for j = 1, #entities do
          local candidate = entities[j]
          -- check for a block immediately above (same x and a y+height that equals the block's y)
          if (candidate.type == BLOCK) and (candidate.x == entity.x) and (candidate.y + candidate.h == entity.y) then
            is_stone_above = true
          end
        end
      end

      if is_stone_above then
        -- no moss, just solid grey stone
        love.graphics.setColor(0.204, 0.204, 0.204)
        love.graphics.rectangle('fill', x, y, tile_size, tile_size)
      elseif entity.shape == 'rect' then
        love.graphics.rectangle(style, x, y, tile_size, tile_size)
      else
        if vectors[entity.shape] == nil then
          error('Unknown shape: ' .. entity.shape)
        end
        
        -- custom vector drawing
        -- TODO: pull into shared function to avoid DRY violation w/ vector-editor.lua?
        -- But we do want the vector editor and this game engine to be fully decoupled
        love.graphics.push()
        love.graphics.translate(x, y)
        love.graphics.scale(tile_size)

        for x, layer in ipairs(vectors[entity.shape]) do
          love.graphics.setColor(layer.color)
          local vertices = layer.vertices
          if layer.style == 'fill' then
            if #vertices > 3*2 then
              local triangles = love.math.triangulate(vertices)
              for i, triangle in ipairs(triangles) do
                love.graphics.polygon('fill', triangle)
              end
            end
          elseif layer.style == 'line' then
            love.graphics.setLineWidth(1 / tile_size)
            if layer.is_closed then
              love.graphics.polygon('line', vertices)
            else
              love.graphics.line(vertices)
            end
          end
        end
        love.graphics.pop()
      end
    else
      love.graphics.setColor({1, 1, 1})
      love.graphics.draw(spritesheet, entity.quad, scale * (entity.x + entity.w / 2), scale * (entity.y + entity.h / 2), entity.rot or 0, scale, scale, entity.w / 2,  entity.h / 2)
    end

    -- draw selected square
    if entity.sel_x and entity.sel_y then
      love.graphics.setColor(0.3, 0.3, 0.3)
      love.graphics.rectangle('line', scale * entity.sel_x * 32, scale * entity.sel_y * 32, 32, 32)
      love.graphics.setColor(1, 1, 1)
    end
  end

  -- map:bump_draw(world, tx, ty, sx, sy) -- debug the collision map

  love.graphics.reset()
  love.graphics.setBackgroundColor(0, 0, 0) -- have to reset bgcolor after a reset()

  -- draw tilesheet
  local w = tile_size * 10
  local h = tile_size * 1
  local tilesheet_x = scale * ((win_w - w) / 2)
  local tilesheet_y = scale * (win_h - 32 - h)
  --love.graphics.draw(spritesheet, tilesheet_quad, tilesheet_x, tilesheet_y)
  love.graphics.setColor(0.3, 0.3, 0.3)
  love.graphics.rectangle('line', tilesheet_x, tilesheet_y, w, h)

  -- draw selected tile in tilesheet for each player
  love.graphics.setColor(1, 1, 1)
  love.graphics.rectangle('line', tilesheet_x + (block_to_place_ix - 1) * tile_size, tilesheet_y, 32, 32)

  love.graphics.setColor(0.3, 0.3, 0.3)
  love.graphics.print("FPS: " .. tostring(love.timer.getFPS()), 10, 10)

  -- TODO: systems that render points & hearts/health per player

  if confirm ~= null then
    local horiz_center = math.floor(win_w/2)
    local vert_middle = math.floor(win_h/2)
    local w = 300
    local h = 20
    love.graphics.setColor(0, 0, 0, 0.8)
    love.graphics.rectangle('fill', horiz_center-w/2,vert_middle-h/2, w, h)
    love.graphics.setColor(0.9, 0.9, 0.9)
    love.graphics.rectangle('line', horiz_center-w/2,vert_middle-h/2, w, h)
    love.graphics.print(confirm.text, horiz_center-w/2 + 22,vert_middle-h/2 + 2) -- https://love2d.org/wiki/love.graphics.newText
  end
end

function love.resize(w, h)
  win_w = w
  win_h = h
end

function love.keypressed(key, scancode, isrepeat)
  if key == "escape" then -- 'esc' to quit the game
    love.event.quit()
  elseif key == 'return' then
    confirm = nil
    is_paused = false
    local player = players[1]
    player.x = 5 * tile_size
    player.y = 5 * tile_size
    player.dx = 0
    player.dy = 0
    world:update(player, player.x, player.y)
  elseif key == 'e' then -- 'e' for editor
    local shape = blocks_to_place[block_to_place_ix];
    vector_editor.initialize(vectors[shape])
    vector_editor.onSave = function(obj)
      vectors[shape] = obj
    end
  elseif key == 'f5' then -- 'F5' to save the level design
    bitser.dumpLoveFile(curr_level_file, level)
  end
end
