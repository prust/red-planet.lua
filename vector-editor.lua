local win_w, win_h
local scale, margin_top, margin_left
local selection_color = {0, 0.55, 1, 1}
local grid_color = {0.2, 0.2, 0.2}
local white = {1, 1, 1}
local margin = 0.1
local snap_amount = 1/8

local curr_layer = 1
local potential_x = nil
local potentail_y = nil
local dragging_pt_ix = nil
function mousepressed(x, y, button, istouch)
  if button == 1 then
    local layer_ix, pt_ix = nearby_pt(x, y)
    if pt_ix ~= nil then
      curr_layer = layer_ix
      dragging_pt_ix = pt_ix
    else
      x,y = snap(fromScreen(x, y))
      local vertices = layers[curr_layer].vertices
      table.insert(vertices, x)
      table.insert(vertices, y)
    end
  end
end

function mousereleased(x, y)
  if dragging_pt_ix ~= nil then
    dragging_pt_ix = nil
  end
end

function mousemoved(x, y)
  if dragging_pt_ix ~= nil then
    local vertices = layers[curr_layer].vertices
    x,y = snap(fromScreen(x, y))
    vertices[dragging_pt_ix] = x
    potential_x = x
    vertices[dragging_pt_ix + 1] = y
    potential_y = y
  else
    local layer_ix, pt_ix = nearby_pt(x, y)
    if pt_ix ~= nil then
      curr_layer = layer_ix
      local vertices = layers[curr_layer].vertices
      potential_x = vertices[pt_ix]
      potential_y = vertices[pt_ix + 1]
    end
  end
end

function fromScreen(x, y)
  return (x - margin_left) / scale, (y - margin_top) / scale
end

function snap(x, y)
  return snapVal(x), snapVal(y)
end

function snapVal(val)
  val = val / snap_amount
  val = round(val)
  return val * snap_amount
end

function round(num) 
  if num >= 0 then
    return math.floor(num + 0.5) 
  else
    return math.ceil(num - 0.5)
  end
end

function nearby_pt(x, y)
  x,y = fromScreen(x, y)

  -- iterate layers backwards, so top-most layers are selected 1st
  for j = #layers, 1, -1
  do
    local vertices = layers[j].vertices
    for i = 1, #vertices, 2
    do
      local other_x, other_y = vertices[i], vertices[i + 1]
      if math.abs(other_x - x) < snap_amount and math.abs(other_y - y) < snap_amount then
        return j,i
      end
    end
  end
  return nil, nil
end

function draw()  
  -- horiz grid lines
  love.graphics.setColor(grid_color)
  for i = 0, 1, 0.25
  do
    love.graphics.line(margin_left,margin_top + i * scale, margin_left + scale,margin_top + i * scale)
  end

  -- vert grid lines
  for i = 0, 1, 0.25
  do
    love.graphics.line(margin_left + i * scale,margin_top, margin_left + i * scale,margin_top + scale)
  end

  love.graphics.setColor(1, 1, 1, 1)

  love.graphics.translate(margin_left, margin_top)
  love.graphics.scale(scale)

  love.graphics.setLineWidth(1 / scale)

  -- polygon() can only draw convex shapes, since the goal is concave, we need to decompose it via triangulate()
  for x, layer in ipairs(layers) do
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
      if layer.is_closed then
        love.graphics.polygon('line', vertices)
      else
        love.graphics.line(vertices)
      end
    else
      -- TODO: throw an error
    end
  end

  if potential_x ~= nil then
    love.graphics.circle('line', potential_x, potential_y, 3 / scale)
  end

  love.graphics.reset()
  love.graphics.setBackgroundColor(0, 0, 0) -- have to reset bgcolor after a reset()

  love.graphics.setColor(0.3, 0.3, 0.3)
  love.graphics.print("FPS: " .. tostring(love.timer.getFPS()), 10, 10)
end

function resize(w, h)
  win_w = w
  win_h = h
  
  if w < h then
    margin_left = w * margin
    local grid = w - (margin_left * 2)
    scale = grid
    margin_top = (h - grid) / 2
  else
    margin_top = h * margin
    local grid = h - (margin_top * 2)
    scale = grid
    margin_left = (w - grid) / 2
  end
end

function keypressed(key, scancode, isrepeat)
  if key == "escape" then
    uninitialize()
  end
end

local orig_keypressed, orig_resize, orig_draw, orig_update, orig_mousemoved, orig_mousepressed, orig_mousereleased
function initialize(_layers)
  if _layers == nil then
    layers = {{color = white, style = 'fill', vertices = {}}}
  else
    layers = deepcopy(_layers)
  end

  orig_keypressed = love.keypressed
  orig_resize = love.resize
  orig_draw = love.draw
  orig_update = love.update
  orig_mousemoved = love.mousemoved
  orig_mousepressed = love.mousepressed
  orig_mousereleased = love.mousereleased

  love.resize = resize
  love.keypressed = keypressed
  love.draw = draw
  love.mousemoved = mousemoved
  love.mousepressed = mousepressed
  love.mousereleased = mousereleased

  -- TODO: store the original values, so we can undo this in uninitialize
  -- nearest neighbor (default is anti-aliasing)
  --love.graphics.setDefaultFilter('nearest')
  local w, h
  w, h = love.graphics.getDimensions()
  resize(w, h)

  love.graphics.setBackgroundColor(0, 0, 0)

  love.window.setFullscreen(true)
  love.mouse.setVisible(true)
end

function uninitialize()
  if vector_editor.onSave then
    vector_editor.onSave(layers)
  end

  love.keypressed = orig_keypressed
  love.resize = orig_resize
  love.draw = orig_draw
  love.update = orig_update
  love.mousemoved = orig_mousemoved
  love.mousepressed = orig_mousepressed
  love.mousereleased = orig_mousereleased
end

function deepcopy(orig)
  local copy
  if type(orig) == 'table' then
    copy = {}
    for key, value in next, orig, nil do
      copy[key] = deepcopy(value)
    end
  else -- number, string, boolean, etc
      copy = orig
  end
  return copy
end

local vector_editor = {
  initialize = initialize,
  uninitialize = uninitialize
}

return vector_editor
