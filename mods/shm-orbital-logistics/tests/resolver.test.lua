local resolver = require('logic.resolver')
local tags = require('logic.tags')

local PLATE = 'iron-plate|normal'

local function section(group, min, extra)
  extra = extra or {}
  return {
    index = extra.index,
    tag = tags.parse(group),
    active = extra.active ~= false,
    multiplier = extra.multiplier or 1,
    filters = {
      { key = extra.key or PLATE, min = min, request_from = extra.from or 'planet', import_from = extra.import_from },
    },
  }
end

local function hub(location, sections, contents, incoming)
  return { location = location, sections = sections, contents = contents or {}, incoming = incoming or {} }
end

describe('решатель', function()
  it('без меток ничего не делает — ваниль', function()
    local result = resolver.resolve(hub('nauvis', { section('Plates', 500) }, { [PLATE] = 500 }))
    assert_eq(result, { locks = {}, transit = {}, release = {} })
  end)

  it('свой запас закрыт замком всегда', function()
    local result = resolver.resolve(hub('nauvis', { section('Fuel [reserve]', 200) }, { [PLATE] = 500 }))
    assert_eq(result.locks, { [PLATE] = true })
  end)

  it('свой запас с нулевым количеством не закрывается', function()
    local result = resolver.resolve(hub('nauvis', { section('[reserve]', 0) }, { [PLATE] = 5 }))
    assert_eq(result.locks, {})
  end)

  it('выключенная игроком секция не учитывается', function()
    local result = resolver.resolve(hub('nauvis', { section('[reserve]', 200, { active = false }) }, { [PLATE] = 5 }))
    assert_eq(result.locks, {})
  end)

  it('груз закрыт вне назначения и в пути, открыт на назначении', function()
    local sections = { section('[cargo→aquilo]', 2000, { import_from = 'nauvis' }) }
    assert_eq(resolver.resolve(hub('nauvis', sections, { [PLATE] = 2000 })).locks, { [PLATE] = true })
    assert_eq(resolver.resolve(hub(nil, sections, { [PLATE] = 2000 })).locks, { [PLATE] = true })
    assert_eq(resolver.resolve(hub('aquilo', sections, { [PLATE] = 2000 })).locks, {})
  end)

  it('груз [cargo] без «куда» — ваниль, не закрывается', function()
    local result = resolver.resolve(hub('nauvis', { section('[cargo]', 2000) }, { [PLATE] = 2000 }))
    assert_eq(result.locks, {})
  end)

  it('груз с источником all на назначении выключается, с planet — нет', function()
    local collect = section('[cargo→fulgora]', 50000, { from = 'all', index = 3 })
    assert_eq(resolver.resolve(hub('fulgora', { collect }, { [PLATE] = 900 })).release, { [3] = true })
    assert_eq(resolver.resolve(hub('nauvis', { collect }, { [PLATE] = 900 })).release, {})
    local plain = section('[cargo→fulgora]', 500, { index = 2 })
    assert_eq(resolver.resolve(hub('fulgora', { plain }, { [PLATE] = 500 })).release, {})
  end)

  it('склад открыт на своей орбите, закрыт на чужой', function()
    local sections = { section('[depot:nauvis]', 2000, { multiplier = 5 }) }
    assert_eq(resolver.resolve(hub('nauvis', sections, { [PLATE] = 10000 })).locks, {})
    assert_eq(resolver.resolve(hub('vulcanus', sections, { [PLATE] = 10000 })).locks, { [PLATE] = true })
  end)

  it('запас и склад одного предмета: открыт, пока содержимого больше запаса', function()
    local sections = { section('[reserve]', 200), section('[depot:nauvis]', 300) }
    assert_eq(resolver.resolve(hub('nauvis', sections, { [PLATE] = 500 })).locks, {})
    assert_eq(resolver.resolve(hub('nauvis', sections, { [PLATE] = 200 })).locks, { [PLATE] = true })
    assert_eq(resolver.resolve(hub('nauvis', sections, { [PLATE] = 150 })).locks, { [PLATE] = true })
  end)

  it('множитель секции учитывается в защищённой части', function()
    local sections = { section('[reserve]', 100, { multiplier = 3 }), section('[depot]', 100) }
    assert_eq(resolver.resolve(hub('nauvis', sections, { [PLATE] = 300 })).locks, { [PLATE] = true })
    assert_eq(resolver.resolve(hub('nauvis', sections, { [PLATE] = 301 })).locks, {})
  end)

  it('склад держит предмет, пока на орбите есть груз с ним', function()
    local sections = { section('[depot:nauvis]', 100) }
    local result = resolver.resolve(hub('nauvis', sections, { [PLATE] = 100 }), { [PLATE] = true })
    assert_eq(result.locks, { [PLATE] = true })
  end)

  it('транзит на склад — пока недостаёт с учётом «в пути» и на орбите есть груз', function()
    local sections = { section('[depot:nauvis]', 100, { multiplier = 2 }) }
    local contents = { [PLATE] = 50 }
    local incoming = { [PLATE] = 30 }
    assert_eq(resolver.resolve(hub('nauvis', sections, contents, incoming), { [PLATE] = true }).transit,
      { [PLATE] = true })
    assert_eq(resolver.resolve(hub('nauvis', sections, { [PLATE] = 150 }, { [PLATE] = 50 }), { [PLATE] = true }).transit, {})
    assert_eq(resolver.resolve(hub('nauvis', sections, contents, incoming)).transit, {})
    assert_eq(resolver.resolve(hub('nauvis', sections, { [PLATE] = 200 }), { [PLATE] = true }).transit, {})
  end)

  it('на транзитный предмет замок не ставится: запрос с платформ и так держит', function()
    local result = resolver.resolve(hub('nauvis', { section('[depot:nauvis]', 100) }, {}), { [PLATE] = true })
    assert_eq(result.transit, { [PLATE] = true })
    assert_eq(result.locks, {})
  end)
end)

describe('груз, который хаб отдаёт на орбите', function()
  it('груз с назначением — на назначении и при наличии', function()
    local sections = { section('[cargo→nauvis]', 100) }
    assert_eq(resolver.cargo_offered(hub('nauvis', sections, { [PLATE] = 5 })), { [PLATE] = true })
    assert_eq(resolver.cargo_offered(hub('nauvis', sections, {})), {})
    assert_eq(resolver.cargo_offered(hub('vulcanus', sections, { [PLATE] = 5 })), {})
  end)

  it('ванильный груз без метки — с import_from другой планеты и источником planet', function()
    local vanilla = { section('Holmium', 100, { import_from = 'fulgora' }) }
    assert_eq(resolver.cargo_offered(hub('nauvis', vanilla, { [PLATE] = 5 })), { [PLATE] = true })
    local own = { section('Plates', 100, { import_from = 'nauvis' }) }
    assert_eq(resolver.cargo_offered(hub('nauvis', own, { [PLATE] = 5 })), {})
    local all = { section('Plates', 100, { import_from = 'fulgora', from = 'all' }) }
    assert_eq(resolver.cargo_offered(hub('nauvis', all, { [PLATE] = 5 })), {})
  end)
end)
