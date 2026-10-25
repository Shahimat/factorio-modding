-- Оснастка тестов внутри игры: чистый участок мира с питанием и создание
-- сущностей одной строкой.

local fixture = {}

fixture.SUP = 'kr-superior-inserter'
fixture.LONG = 'kr-superior-long-inserter'
fixture.SUP_INSTANT = 'shm-kr-superior-inserter-instant'

local AREA = { { -40, -40 }, { 40, 40 } }

function fixture.surface()
  return game.surfaces[1]
end

--- Бонус вместимости массовых манипуляторов, чтобы рука вмещала больше
--- одного предмета и без исследований, и без K2 Spaced Out (он сам даёт
--- превосходным манипуляторам +4). Снимается в `fixture.reset_force`.
function fixture.widen_hands()
  game.forces.player.bulk_inserter_capacity_bonus = 4
end

function fixture.reset_force()
  game.forces.player.bulk_inserter_capacity_bonus = 0
  game.forces.player.belt_stack_size_bonus = 0
end

function fixture.clear()
  local surface = fixture.surface()
  for _, entity in pairs(surface.find_entities_filtered({ area = AREA })) do
    if entity.type ~= 'character' then
      entity.destroy()
    end
  end
end

--- @param name string
--- @param position MapPosition
--- @param extra table?
function fixture.create(name, position, extra)
  local spec = { name = name, position = position, force = 'player' }
  for k, v in pairs(extra or {}) do
    spec[k] = v
  end
  local entity = fixture.surface().create_entity(spec)
  assert(entity, 'не создалась сущность ' .. name)
  return entity
end

--- Источник бесконечной энергии и подстанция над рядом манипуляторов:
--- зона питания покрывает x от -5 до 13 и y от -15 до 3.
function fixture.power()
  local source = fixture.create('electric-energy-interface', { 8, -9 })
  source.power_production = 1e9
  source.electric_buffer_size = 1e9
  fixture.create('substation', { 4, -6 })
end

--- Сундук → манипулятор → сундук. Манипулятор с направлением по умолчанию
--- (север) берёт с севера и кладёт на юг.
--- @param name string
--- @param x number
function fixture.chest_line(name, x)
  local input = fixture.create('steel-chest', { x + 0.5, -0.5 })
  local inserter = fixture.create(name, { x + 0.5, 0.5 })
  local output = fixture.create('steel-chest', { x + 0.5, 1.5 })
  return input, inserter, output
end

--- Сколько предметов `name` в инвентаре сундука.
--- @param chest LuaEntity
--- @param name string
function fixture.count(chest, name)
  return chest.get_inventory(defines.inventory.chest).get_item_count(name)
end

return fixture
