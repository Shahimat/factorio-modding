-- Демонстрационный сценарий стенда: показывает, что оснастка умеет всё, на
-- чём стоят проверки механик из целей 1.3–1.6 — создать сущности в пустом
-- мире, промотать тики и сверить результат.
--
-- Механики самого мода здесь не проверяются: печь взята как заведомо
-- ванильное поведение, не требующее электричества, — её плавка и служит
-- доказательством, что промотанные тики двигают мир.

local AREA = { { -16, -16 }, { 16, 16 } }

local function clear(surface)
  for _, entity in pairs(surface.find_entities_filtered({ area = AREA })) do
    if entity.type ~= 'character' then
      entity.destroy()
    end
  end
end

describe('оснастка стенда', function()
  local surface

  before_each(function()
    surface = game.surfaces[1]
    clear(surface)
  end)

  after_each(function()
    clear(surface)
  end)

  it('создаёт сущности в пустом мире и находит их поиском', function()
    local chest = surface.create_entity({
      name = 'iron-chest',
      position = { 0, 0 },
      force = 'player',
    })
    assert(chest ~= nil, 'сундук не создался')
    assert(chest.valid, 'сундук создался невалидным')

    local found = surface.find_entities_filtered({ area = AREA, name = 'iron-chest' })
    assert(#found == 1, 'поиск вернул сущностей: ' .. #found)
  end)

  it('скрипт загружает хранилище здания', function()
    local furnace = surface.create_entity({
      name = 'stone-furnace',
      position = { 0, 0 },
      force = 'player',
    })
    assert(furnace ~= nil, 'печь не создалась')

    local ore = furnace.insert({ name = 'iron-ore', count = 10 })
    assert(ore == 10, 'в печь вошло руды: ' .. ore)

    local fuel = furnace.insert({ name = 'coal', count = 5 })
    assert(fuel == 5, 'в печь вошло угля: ' .. fuel)
  end)

  it('промотка тиков двигает мир: печь выплавляет пластины', function()
    local furnace = surface.create_entity({
      name = 'stone-furnace',
      position = { 0, 0 },
      force = 'player',
    })
    furnace.insert({ name = 'iron-ore', count = 10 })
    furnace.insert({ name = 'coal', count = 5 })

    local started = game.tick

    after_ticks(400, function()
      assert(game.tick - started >= 400, 'тики не промотались: ' .. (game.tick - started))

      local produced = furnace.get_output_inventory().get_item_count('iron-plate')
      assert(produced > 0, 'за 400 тиков печь не выплавила ни одной пластины')

      local left = furnace.get_inventory(defines.inventory.crafter_input).get_item_count('iron-ore')
      assert(left < 10, 'руда не расходуется, в источнике осталось: ' .. left)
    end)
  end)
end)
