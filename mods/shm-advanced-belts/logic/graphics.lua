-- Перекраска копий прототипов турбо: каждый спрайт турбо получает поверх
-- себя слой маски цвета, который красит `tint`. Маски порождает
-- `tools/recolor-sprites.ts`, правило имени файла — то же, что там
-- (`maskPath` в `tools/lib/recolor-jobs.ts`).
--
-- Чистый модуль: работает с таблицами прототипов и к `data` не обращается.

local graphics = {}

local SOURCE_PREFIX = '__space-age__/graphics/'
local MASK_PREFIX = '__shm-advanced-belts__/graphics/'

--- Путь маски для файла турбо; nil — у файла маски нет (не турбо, замёрзший
--- патч, остатки).
function graphics.mask_path(filename)
  if type(filename) ~= 'string' or filename:sub(1, #SOURCE_PREFIX) ~= SOURCE_PREFIX then
    return nil
  end
  local relative = filename:sub(#SOURCE_PREFIX + 1)
  if not relative:find('turbo%-') or relative:find('frozen') or relative:find('remnants') then
    return nil
  end
  if relative:sub(-4) ~= '.png' then
    return nil
  end
  return MASK_PREFIX .. relative:sub(1, -5):gsub('turbo%-', '') .. '-mask.png'
end

local function shallow(value)
  local copy = {}
  for k, v in pairs(value) do
    copy[k] = v
  end
  return copy
end

local function mask_of(sprite, tint)
  local mask = shallow(sprite)
  mask.filename = graphics.mask_path(sprite.filename)
  mask.tint = tint
  mask.draw_as_shadow = nil
  mask.draw_as_glow = nil
  mask.draw_as_light = nil
  return mask
end

local function is_sprite(node)
  return type(node) == 'table' and type(node.filename) == 'string'
end

local recolor

--- Перекрашивает узел на месте. Спрайт с файлом турбо превращается в пару
--- слоёв; лист `sheet` в `Sprite4Way` — в список `sheets`, потому что слоёв у
--- листа нет.
recolor = function(node, tint)
  if type(node) ~= 'table' then
    return
  end
  -- Снимок ключей: ветка `sheet` добавляет в узел новый ключ, а добавлять
  -- ключи во время `pairs` Lua не разрешает.
  local keys = {}
  for key in pairs(node) do
    keys[#keys + 1] = key
  end
  for _, key in ipairs(keys) do
    local child = node[key]
    if key == 'sheet' and is_sprite(child) and graphics.mask_path(child.filename) then
      node.sheet = nil
      node.sheets = { child, mask_of(child, tint) }
    elseif key == 'sheets' and type(child) == 'table' then
      -- Новый список, а не дописывание в старый: копия прототипа может
      -- делить таблицы между полями, и дописанное попало бы туда дважды.
      local result = {}
      for _, sheet in ipairs(child) do
        result[#result + 1] = sheet
      end
      for _, sheet in ipairs(child) do
        if is_sprite(sheet) and graphics.mask_path(sheet.filename) then
          result[#result + 1] = mask_of(sheet, tint)
        end
      end
      node.sheets = result
    elseif key == 'layers' and type(child) == 'table' then
      local result = {}
      for _, layer in ipairs(child) do
        result[#result + 1] = layer
        if is_sprite(layer) and graphics.mask_path(layer.filename) then
          result[#result + 1] = mask_of(layer, tint)
        else
          recolor(layer, tint)
        end
      end
      node.layers = result
    elseif is_sprite(child) and graphics.mask_path(child.filename) then
      node[key] = { layers = { child, mask_of(child, tint) } }
    else
      recolor(child, tint)
    end
  end
end

--- Перекрашивает графику прототипа на месте.
function graphics.recolor(prototype, tint)
  recolor(prototype, tint)
end

--- Иконки прототипа: исходная иконка и маска поверх неё. Поддерживает и
--- `icon`, и `icons`; иконка без маски остаётся как была.
function graphics.recolor_icons(prototype, tint)
  local layers = prototype.icons
  if layers == nil and prototype.icon ~= nil then
    layers = { { icon = prototype.icon, icon_size = prototype.icon_size } }
  end
  if layers == nil then
    return
  end
  local result = {}
  for _, layer in ipairs(layers) do
    result[#result + 1] = layer
    local mask = graphics.mask_path(layer.icon)
    if mask then
      local masked = shallow(layer)
      masked.icon = mask
      masked.tint = tint
      result[#result + 1] = masked
    end
  end
  prototype.icon = nil
  prototype.icon_size = nil
  prototype.icons = result
end

return graphics
