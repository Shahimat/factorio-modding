-- Тиры после стадии данных: скорости, дальности, рецепты, технологии,
-- улучшения, переработка, перенастройка зондом.

local f = require('tests.ingame.fixture')

describe('тиры', function()
  it('включённые тиры есть, выключенных нет', function()
    for _, key in ipairs(f.KEYS) do
      local expected = f.has(f.enabled_keys(), key)
      for _, name in ipairs({ f.belt(key), f.underground(key), f.splitter(key) }) do
        assert((prototypes.entity[name] ~= nil) == expected, name)
        assert((prototypes.item[name] ~= nil) == expected, 'предмет ' .. name)
        assert((prototypes.recipe[name] ~= nil) == expected, 'рецепт ' .. name)
      end
      assert((prototypes.technology[f.belt(key)] ~= nil) == expected, 'технология ' .. key)
    end
  end)

  it('скорость ленты, подземки и сплиттера и дальность подземки — из настроек', function()
    for _, key in ipairs(f.enabled_keys()) do
      local speed = f.speed(key)
      for _, name in ipairs({ f.belt(key), f.underground(key), f.splitter(key) }) do
        local actual = prototypes.entity[name].belt_speed * 480
        assert(math.abs(actual - speed) < 1e-6, ('%s: %s вместо %s'):format(name, actual, speed))
      end
      local distance = prototypes.entity[f.underground(key)].max_underground_distance
      assert(distance == f.UNDERGROUND[key], ('%s: дальность %s'):format(key, distance))
    end
  end)

  it('рецепты собираются в сборочном автомате и литейке на любой поверхности', function()
    for _, key in ipairs(f.enabled_keys()) do
      for _, name in ipairs({ f.belt(key), f.underground(key), f.splitter(key) }) do
        local recipe = prototypes.recipe[name]
        assert(f.has(recipe.categories, 'metallurgy'), name .. ': нет metallurgy')
        assert(f.has(recipe.categories, 'crafting-with-fluid'), name .. ': нет crafting-with-fluid')
        assert(recipe.surface_conditions == nil, name .. ': есть условия поверхности')
      end
    end
  end)

  it('каждый тир собирается из предыдущего включённого, первый — из турбо', function()
    local previous = 'turbo'
    for _, key in ipairs(f.enabled_keys()) do
      local previous_belt = previous == 'turbo' and 'turbo-transport-belt' or f.belt(previous)
      assert(f.ingredient(f.belt(key), previous_belt), key .. ' не из ' .. previous_belt)
      previous = key
    end
  end)

  it('технология требует предыдущий тир и колбу планеты тира', function()
    local previous = 'turbo-transport-belt'
    for _, key in ipairs(f.enabled_keys()) do
      local tech = prototypes.technology[f.belt(key)]
      assert(tech.prerequisites[previous], key .. ': нет пререквизита ' .. previous)
      previous = f.belt(key)
    end
    local absolute = prototypes.technology[f.belt('absolute')]
    if absolute then
      assert(absolute.prerequisites['promethium-science-pack'], 'абсолютный без технологии прометиевой науки')
      assert(f.has(absolute.research_unit_ingredients, 'promethium-science-pack'), 'абсолютный без прометиевой колбы')
    end
  end)

  it('улучшения идут от турбо по включённым тирам (без K2 — и от самого турбо)', function()
    local chain = f.k2() and {} or { 'turbo' }
    for _, key in ipairs(f.enabled_keys()) do
      chain[#chain + 1] = key
    end
    local function name_of(key, kind)
      if key == 'turbo' then
        return ({ belt = 'turbo-transport-belt', underground = 'turbo-underground-belt', splitter = 'turbo-splitter' })[kind]
      end
      return ({ belt = f.belt, underground = f.underground, splitter = f.splitter })[kind](key)
    end
    for i = 1, #chain - 1 do
      for _, kind in ipairs({ 'belt', 'underground', 'splitter' }) do
        local from = prototypes.entity[name_of(chain[i], kind)]
        local next_upgrade = from.next_upgrade and from.next_upgrade.name
        assert(next_upgrade == name_of(chain[i + 1], kind), ('%s → %s'):format(from.name, tostring(next_upgrade)))
      end
    end
  end)

  it('переработка ленты отдаёт ресурсы её рецепта', function()
    local recycling = f.belt('superior') .. '-recycling'
    assert(prototypes.recipe[recycling], 'нет рецепта переработки')
    assert(f.product(recycling, 'holmium-plate'), 'переработка не отдаёт гольмий')
  end)

  it('клавиша переключения — SHIFT + M', function()
    local input = prototypes.custom_input['shm-advanced-belts-full-stack-toggle']
    assert(input and input.key_sequence == 'SHIFT + M', 'нет клавиши или не та')
  end)
end)

describe('API', function()
  it('зонд перенастроил «Гипер»: рецепт и переработка из его ингредиентов', function()
    if not f.probe() then
      return
    end
    local belt = f.belt('hyper')
    local iron = f.ingredient(belt, 'iron-plate')
    assert(iron and iron.amount == 7, 'рецепт не из API')
    assert(f.ingredient(belt, f.belt('superior')), 'гипер не из превосходного при выключенном ультра')
    assert(f.ingredient(belt, 'lithium-plate') == nil, 'список ингредиентов не заменён целиком')
    assert(f.product(belt .. '-recycling', 'iron-plate'), 'переработка не следует за рецептом')
    local count = prototypes.technology[belt].research_unit_count
    assert(count == 3000, 'количество колб не из API: ' .. count)
  end)

  it('зонд выключил «Абсолютный» через API: тира нет, «Гипер» последний в цепочке', function()
    if not f.probe() then
      return
    end
    assert(prototypes.entity[f.belt('absolute')] == nil, 'абсолютный есть')
    assert(prototypes.entity[f.belt('hyper')].next_upgrade == nil, 'у гипера есть улучшение')
  end)
end)
