local defaults = require('logic.defaults')
local tiers = require('logic.tiers')

local function keys_of(entries)
  local result = {}
  for i, entry in ipairs(entries) do
    result[i] = entry.key
  end
  return result
end

local function resolve(player, overrides)
  return tiers.resolve(tiers.merge(defaults.TIERS, player or {}, overrides or {}), defaults.TURBO_PACKS)
end

describe('скорость', function()
  it('кратные 15 ложатся в шаг движка точно', function()
    for _, speed in ipairs(defaults.SPEED_CHOICES) do
      assert_eq(tiers.items_per_second(tiers.speed_field(speed)), speed)
    end
  end)

  it('110 округляется до ближайшего шага 1,875 предм./с', function()
    assert_eq(tiers.items_per_second(tiers.speed_field(110)), 110.625)
  end)

  it('150 предм./с — поле прототипа 0,3125', function()
    assert_eq(tiers.speed_field(150), 0.3125)
  end)
end)

describe('значения по умолчанию', function()
  it('четыре тира со скоростями 90 / 105 / 135 / 150 и дальностью 15 / 19 / 23 / 27', function()
    local speeds, undergrounds = {}, {}
    for i, tier in ipairs(defaults.TIERS) do
      speeds[i] = tier.speed
      undergrounds[i] = tier.underground
    end
    assert_eq(speeds, { 90, 105, 135, 150 })
    assert_eq(undergrounds, { 15, 19, 23, 27 })
  end)

  it('скорости по умолчанию есть в списке настройки', function()
    local allowed = {}
    for _, speed in ipairs(defaults.SPEED_CHOICES) do
      allowed[speed] = true
    end
    for _, tier in ipairs(defaults.TIERS) do
      assert_true(allowed[tier.speed], tier.key)
    end
  end)

  it('количество колб растёт линейно от турбо: 1000 / 1500 / 2000 / 2500', function()
    local counts = {}
    for i, tier in ipairs(defaults.TIERS) do
      counts[i] = tier.technology.count
    end
    assert_eq(counts, { 1000, 1500, 2000, 2500 })
  end)

  it('рецепт лоадера для expensive — ресурсы ×10', function()
    local recipes = defaults.TIERS[1].recipes
    assert_eq(recipes.loader_expensive.ingredients[1].amount, recipes.loader.ingredients[1].amount * 10)
  end)
end)

describe('имена', function()
  it('прототипы тира несут префикс shm-, лоадер — по правилу AAI', function()
    local n = tiers.names('hyper')
    assert_eq(n.belt, 'shm-hyper-transport-belt')
    assert_eq(n.underground, 'shm-hyper-underground-belt')
    assert_eq(n.splitter, 'shm-hyper-splitter')
    assert_eq(n.loader_tier, 'shm-hyper')
    assert_eq(n.loader, 'aai-shm-hyper-loader')
  end)
end)

describe('слияние', function()
  it('настройка игрока меняет скорость, дальность и включение', function()
    local configs = tiers.merge(defaults.TIERS, { ultra = { speed = 120, underground = 30, enabled = false } }, {})
    assert_eq(configs[2].speed, 120)
    assert_eq(configs[2].underground, 30)
    assert_false(configs[2].enabled)
  end)

  it('значение из API главнее настройки игрока', function()
    local configs = tiers.merge(defaults.TIERS, { hyper = { speed = 165 } }, { hyper = { speed = 120 } })
    assert_eq(configs[3].speed, 120)
  end)

  it('API сливает словари по ключам и заменяет списки целиком', function()
    local configs = tiers.merge(defaults.TIERS, {}, {
      superior = {
        technology = { count = 7 },
        recipes = { belt = { ingredients = { { type = 'item', name = 'x', amount = 1 } } } },
      },
    })
    local superior = configs[1]
    assert_eq(superior.technology.count, 7)
    assert_eq(superior.technology.time, 60)
    assert_eq(#superior.recipes.belt.ingredients, 1)
    assert_eq(superior.recipes.belt.previous, 1)
  end)

  it('слияние не портит значения по умолчанию', function()
    tiers.merge(defaults.TIERS, { superior = { speed = 240 } }, { superior = { technology = { count = 1 } } })
    assert_eq(defaults.TIERS[1].speed, 90)
    assert_eq(defaults.TIERS[1].technology.count, 1000)
  end)
end)

describe('сшивка', function()
  it('все тиры включены — цепочка от турбо по порядку', function()
    local entries = resolve()
    assert_eq(keys_of(entries), { 'superior', 'ultra', 'hyper', 'absolute' })
    assert_eq(entries[1].previous.belt, 'turbo-transport-belt')
    assert_eq(entries[2].previous.belt, 'shm-superior-transport-belt')
    assert_eq(entries[1].next.belt, 'shm-ultra-transport-belt')
    assert_nil(entries[4].next)
  end)

  it('выключенный тир пропускается, следующий ссылается на предыдущий включённый', function()
    local entries = resolve({ ultra = { enabled = false } })
    assert_eq(keys_of(entries), { 'superior', 'hyper', 'absolute' })
    assert_eq(entries[2].previous.belt, 'shm-superior-transport-belt')
    assert_eq(entries[2].previous.technology, 'shm-superior-transport-belt')
    assert_eq(entries[1].next.splitter, 'shm-hyper-splitter')
  end)

  it('выключены первые два — гипер собирается и исследуется от турбо', function()
    local entries = resolve({ superior = { enabled = false }, ultra = { enabled = false } })
    assert_eq(entries[1].key, 'hyper')
    assert_eq(entries[1].previous.belt, 'turbo-transport-belt')
    assert_eq(tiers.prerequisites(entries[1])[1], 'turbo-transport-belt')
  end)

  it('выключены все — пустой список', function()
    local off = {}
    for _, tier in ipairs(defaults.TIERS) do
      off[tier.key] = { enabled = false }
    end
    assert_eq(#resolve(off), 0)
  end)

  it('колбы накопительные и не зависят от выключения', function()
    local entries = resolve({ superior = { enabled = false } })
    local packs = entries[1].packs
    assert_eq(packs[#packs - 1], 'electromagnetic-science-pack')
    assert_eq(packs[#packs], 'agricultural-science-pack')
  end)

  it('абсолютный тир требует прометиевую науку', function()
    local entries = resolve()
    local absolute = entries[4]
    assert_eq(absolute.packs[#absolute.packs], 'promethium-science-pack')
    local found = false
    for _, name in ipairs(tiers.prerequisites(absolute)) do
      if name == 'promethium-science-pack' then
        found = true
      end
    end
    assert_true(found)
  end)

  it('колбы из API заменяют накопленные', function()
    local entries = resolve({}, { superior = { technology = { packs = { 'automation-science-pack' } } } })
    assert_eq(entries[1].packs, { 'automation-science-pack' })
  end)
end)

describe('ингредиенты', function()
  it('предмет предыдущего тира идёт первым в количестве previous', function()
    local spec = defaults.TIERS[4].recipes.belt
    local result = tiers.ingredients(spec, 'shm-hyper-transport-belt')
    assert_eq(result[1], { type = 'item', name = 'shm-hyper-transport-belt', amount = 4 })
    assert_eq(#result, #spec.ingredients + 1)
  end)

  it('previous = 0 — без предыдущего тира', function()
    local result = tiers.ingredients({ previous = 0, ingredients = { { type = 'item', name = 'a', amount = 1 } } }, 'x')
    assert_eq(#result, 1)
    assert_eq(result[1].name, 'a')
  end)
end)

describe('цвет', function()
  it('0–255 переводится в 0–1', function()
    assert_eq(tiers.color01({ 255, 0, 51 }), { r = 1, g = 0, b = 0.2 })
  end)
end)
