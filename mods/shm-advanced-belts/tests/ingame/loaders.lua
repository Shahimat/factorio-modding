-- Лоадеры: лоадеры AAI тиров, делитель цены, стак, ожидание полной стопки.

local f = require('tests.ingame.fixture')

describe('лоадеры AAI тиров', function()
  it('есть у каждого включённого тира только при AAI', function()
    for _, key in ipairs(f.KEYS) do
      local expected = f.aai() and f.has(f.enabled_keys(), key)
      assert((prototypes.entity[f.loader(key)] ~= nil) == expected, f.loader(key))
    end
  end)

  it('скорость лоадера — скорость ленты тира', function()
    if not f.aai() then
      return
    end
    for _, key in ipairs(f.enabled_keys()) do
      local loader = prototypes.entity[f.loader(key)].belt_speed
      local belt = prototypes.entity[f.belt(key)].belt_speed
      assert(loader == belt, ('%s: %s против %s'):format(key, loader, belt))
    end
  end)

  it('рецепт: лента тира и лоадер предыдущего включённого тира, первый — после турбо-лоадера', function()
    if not f.aai() then
      return
    end
    local previous = 'aai-turbo-loader'
    for _, key in ipairs(f.enabled_keys()) do
      local recipe = f.loader(key)
      assert(f.ingredient(recipe, f.belt(key)), recipe .. ': нет ленты тира')
      assert(f.ingredient(recipe, previous), recipe .. ': нет ' .. previous)
      assert(prototypes.technology[recipe].prerequisites[f.belt(key)], recipe .. ': технология без ленты тира')
      previous = recipe
    end
  end)

  it('в режиме lubricated лоадер тира без лубриканта стоит', function()
    if f.aai_mode() ~= 'lubricated' then
      return
    end
    f.clear()
    local chest = f.create('steel-chest', { -0.5, 0.5 })
    f.create(f.loader('superior'), { 0.5, 0.5 }, { direction = defines.direction.east, type = 'output' })
    f.create('transport-belt', { 1.5, 0.5 }, { direction = defines.direction.east })
    chest.insert({ name = 'iron-plate', count = 10 })
    after_ticks(180, function()
      local left = chest.get_inventory(defines.inventory.chest).get_item_count('iron-plate')
      f.clear()
      assert(left == 10, 'лоадер без лубриканта выгрузил ' .. (10 - left))
    end)
  end)

  it('улучшение идёт по лоадерам тиров (без K2 — и от турбо-лоадера AAI)', function()
    if not f.aai() then
      return
    end
    local keys = f.enabled_keys()
    local from = prototypes.entity['aai-turbo-loader']
    if f.k2() then
      from = prototypes.entity[f.loader(table.remove(keys, 1))]
    end
    for _, key in ipairs(keys) do
      assert(from.next_upgrade and from.next_upgrade.name == f.loader(key), from.name .. ' → ' .. tostring(from.next_upgrade and from.next_upgrade.name))
      from = prototypes.entity[f.loader(key)]
    end
  end)
end)

describe('делитель цены', function()
  it('режим AAI в прогоне тот, что задан: expensive с зондом, lubricated без', function()
    if not f.aai() then
      return
    end
    local expected = f.probe() and 'expensive' or 'lubricated'
    assert(f.aai_mode() == expected, 'режим AAI: ' .. tostring(f.aai_mode()))
  end)

  it('в режиме expensive делит рецепты всех лоадеров AAI, предыдущий лоадер не делит', function()
    if f.aai_mode() ~= 'expensive' then
      return
    end
    local turbo = f.ingredient('aai-turbo-loader', 'tungsten-plate')
    assert(turbo and turbo.amount == 60, 'турбо-лоадер AAI: вольфрам ' .. tostring(turbo and turbo.amount))
    local superior = f.ingredient(f.loader('superior'), 'holmium-plate')
    assert(superior and superior.amount == 60, 'превосходный: гольмий ' .. tostring(superior and superior.amount))
    local previous = f.ingredient(f.loader('superior'), 'aai-turbo-loader')
    assert(previous and previous.amount == 1, 'предыдущий лоадер поделён')
  end)

  it('в режиме expensive переработка лоадера следует за поделённым рецептом', function()
    if f.aai_mode() ~= 'expensive' then
      return
    end
    local tungsten = f.product('aai-turbo-loader-recycling', 'tungsten-plate')
    assert(tungsten and tungsten.amount == 15, 'переработка отдаёт вольфрам ' .. tostring(tungsten and tungsten.amount))
  end)

  it('в режиме lubricated рецепты AAI не меняются', function()
    if f.aai_mode() ~= 'lubricated' then
      return
    end
    local turbo = f.ingredient('aai-turbo-loader', 'tungsten-plate')
    assert(turbo and turbo.amount == 30, 'турбо-лоадер AAI: вольфрам ' .. tostring(turbo and turbo.amount))
  end)
end)

describe('стак и полная стопка', function()
  before_each(f.clear)
  after_each(f.clear)

  it('все видимые лоадеры кладут стопки с настраиваемым размером', function()
    local max = prototypes.utility_constants.max_belt_stack_size
    for name, prototype in pairs(prototypes.get_entity_filtered({ { filter = 'type', type = 'loader-1x1' } })) do
      assert(prototype.loader_max_belt_stack_size == max, name .. ': ' .. prototype.loader_max_belt_stack_size)
      assert(prototype.loader_adjustable_belt_stack_size, name .. ': размер стопки не настраивается')
    end
  end)

  it('исходный лоадер ждёт полную стопку, скрытая копия — нет; у копии AAI своя труба', function()
    if not f.aai() then
      return
    end
    local base = prototypes.entity[f.loader('superior')]
    local alt = prototypes.entity[f.loader('superior') .. '-shm-alt']
    assert(base.loader_wait_for_full_stack == true, 'исходный не ждёт')
    assert(alt and alt.loader_wait_for_full_stack == false, 'копия ждёт или её нет')
    assert(alt.hidden, 'копия не скрыта')
    assert(alt.items_to_place_this[1].name == base.name, 'копия ставится не предметом исходного')
    if f.aai_mode() == 'lubricated' then
      assert(prototypes.entity[alt.name .. '-pipe'], 'у копии нет трубы')
    end
  end)

  it('лоадер в режиме «Полная стопка» не кладёт неполную стопку, а полную кладёт', function()
    if not f.aai() then
      return
    end
    game.forces.player.belt_stack_size_bonus = 3
    local chest, _, belts = f.loader_line(f.loader('superior'), 0)
    chest.insert({ name = 'iron-plate', count = 3 })
    after_ticks(120, function()
      assert(f.sum(f.belt_stacks(belts)) == 0, 'неполная стопка выложена')
      chest.insert({ name = 'iron-plate', count = 1 })
      after_ticks(120, function()
        local stacks = f.belt_stacks(belts)
        assert(#stacks == 1 and stacks[1] == 4, 'на ленте: ' .. serpent.line(stacks))
      end)
    end)
  end)

  it('лоадер в режиме «Сразу» кладёт сколько есть', function()
    if not f.aai() then
      return
    end
    game.forces.player.belt_stack_size_bonus = 3
    local chest, _, belts = f.loader_line(f.loader('superior') .. '-shm-alt', 0)
    chest.insert({ name = 'iron-plate', count = 3 })
    after_ticks(120, function()
      assert(f.sum(f.belt_stacks(belts)) == 3, 'на ленте: ' .. serpent.line(f.belt_stacks(belts)))
    end)
  end)
end)
