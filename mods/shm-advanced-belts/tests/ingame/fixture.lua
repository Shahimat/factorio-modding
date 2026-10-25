-- Оснастка тестов внутри игры: чистый участок мира, создание сущностей,
-- признаки прогона (с AAI, без него, с зондом).

local fixture = {}

fixture.KEYS = { 'superior', 'ultra', 'hyper', 'absolute' }
fixture.SPEEDS = { superior = 90, ultra = 105, hyper = 135, absolute = 150 }
fixture.UNDERGROUND = { superior = 13, ultra = 15, hyper = 17, absolute = 19 }

local AREA = { { -40, -40 }, { 40, 40 } }

--- Прогон с зондом: AAI в режиме expensive, «Ультра» выключен настройкой,
--- «Абсолютный» — через API, «Гипер» перенастроен через API
--- (`tests/ingame/probe/`).
function fixture.probe()
  return script.active_mods['shm-advanced-belts-probe'] ~= nil
end

--- Прогон с Krastorio 2: он сам выставляет улучшение турбо в свою ленту, и
--- по решению владельца мод это поле с ним не делит.
function fixture.k2()
  return script.active_mods['Krastorio2'] ~= nil
end

function fixture.aai()
  return script.active_mods['aai-loaders'] ~= nil
end

function fixture.belt(key)
  return 'shm-' .. key .. '-transport-belt'
end

function fixture.underground(key)
  return 'shm-' .. key .. '-underground-belt'
end

function fixture.splitter(key)
  return 'shm-' .. key .. '-splitter'
end

function fixture.loader(key)
  return 'aai-shm-' .. key .. '-loader'
end

--- Включённые тиры этого прогона по порядку.
function fixture.enabled_keys()
  local keys = {}
  for _, key in ipairs(fixture.KEYS) do
    if not (fixture.probe() and (key == 'ultra' or key == 'absolute')) then
      keys[#keys + 1] = key
    end
  end
  return keys
end

--- Ожидаемая скорость тира в этом прогоне, предм./с.
function fixture.speed(key)
  if fixture.probe() and key == 'hyper' then
    return 120
  end
  return fixture.SPEEDS[key]
end

function fixture.surface()
  return game.surfaces[1]
end

function fixture.clear()
  for _, entity in pairs(fixture.surface().find_entities_filtered({ area = AREA })) do
    if entity.type ~= 'character' then
      entity.destroy()
    end
  end
  game.forces.player.belt_stack_size_bonus = 0
end

--- @param name string
--- @param position MapPosition
--- @param extra table?
function fixture.create(name, position, extra)
  -- Постройка объявляется, как у игрока: AAI вешает трубу с лубрикантом
  -- на лоадер по событию постройки.
  local spec = { name = name, position = position, force = 'player', raise_built = true }
  for k, v in pairs(extra or {}) do
    spec[k] = v
  end
  local entity = fixture.surface().create_entity(spec)
  assert(entity, 'не создалась сущность ' .. name)
  return entity
end

--- Ингредиент рецепта по имени; nil — нет такого.
function fixture.ingredient(recipe_name, name)
  for _, ingredient in ipairs(prototypes.recipe[recipe_name].ingredients) do
    if ingredient.name == name then
      return ingredient
    end
  end
  return nil
end

--- Результат рецепта по имени; nil — нет такого.
function fixture.product(recipe_name, name)
  for _, product in ipairs(prototypes.recipe[recipe_name].products) do
    if product.name == name then
      return product
    end
  end
  return nil
end

function fixture.has(list, value)
  for _, item in pairs(list or {}) do
    if item == value or (type(item) == 'table' and item.name == value) then
      return true
    end
  end
  return false
end

--- Режим AAI Loaders в этом прогоне.
function fixture.aai_mode()
  return settings.startup['aai-loaders-mode'] and settings.startup['aai-loaders-mode'].value or nil
end

--- Сундук → лоадер → лента на восток. Лоадер стоит на (x, 0.5), берёт из
--- сундука слева и кладёт на ленту справа; в режиме `lubricated` его труба
--- получает лубрикант.
--- @param name string
--- @param x number
function fixture.loader_line(name, x)
  local chest = fixture.create('steel-chest', { x - 0.5, 0.5 })
  local loader = fixture.create(name, { x + 0.5, 0.5 }, { direction = defines.direction.east, type = 'output' })
  local belts = {}
  for i = 1, 4 do
    belts[i] = fixture.create('transport-belt', { x + 0.5 + i, 0.5 }, { direction = defines.direction.east })
  end
  fixture.lubricate(loader)
  return chest, loader, belts
end

--- Заливает лубрикант в трубу AAI при лоадере, если она есть.
function fixture.lubricate(loader)
  local pipe_name = loader.name .. '-pipe'
  if prototypes.entity[pipe_name] == nil then
    return nil
  end
  local pipe = fixture.surface().find_entity(pipe_name, { loader.position.x, loader.position.y + 1 / 32 })
  if pipe then
    pipe.insert_fluid({ name = 'lubricant', amount = 1000 })
  end
  return pipe
end

--- Стопки на лентах: список размеров всех стопок.
function fixture.belt_stacks(belts)
  local sizes = {}
  for _, belt in ipairs(belts) do
    for i = 1, belt.get_max_transport_line_index() do
      for _, item in ipairs(belt.get_transport_line(i).get_detailed_contents()) do
        sizes[#sizes + 1] = item.stack.count
      end
    end
  end
  return sizes
end

function fixture.sum(list)
  local total = 0
  for _, value in ipairs(list) do
    total = total + value
  end
  return total
end

return fixture
