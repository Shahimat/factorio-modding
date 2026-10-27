-- Наблюдения за ванильными передачами 2.1 по матрице V-01…V-09 из ТЗ
-- `specs/27102026_spec_orbital_logistics.md`, раздел 9. Сценарий почти везде
-- один: поставщик A с предметом, получатель B на той же орбите запрашивает
-- предмет с платформ, и смотрим, приедет ли он и за сколько тиков.

local f = require('tests.fixture')

local WANT = 50

--- B запрашивает WANT с платформ над Нависом, ждём доставку.
local function expect_transfer(id, a_hub, label, after)
  local _, b_hub = f.platform('b')
  f.request(b_hub, WANT, { from = 'platforms', import_from = f.PLANET })
  local before = f.count(a_hub)
  local lowest = before
  f.watch(f.WAIT, function()
    lowest = math.min(lowest, f.count(a_hub))
    return f.count(b_hub) >= WANT
  end, function(elapsed, reached)
    f.observe(id, string.format('%s: B получил %d из %d за %d тиков, у A было %d, минимум %d, стало %d, в пути к B %d',
      label, f.count(b_hub), WANT, elapsed, before, lowest, f.count(a_hub), f.incoming(b_hub)))
    if after then
      after(reached, b_hub)
    end
  end)
end

local function supplier(label, contents, providing)
  local _, hub = f.platform(label)
  if contents > 0 then
    hub.insert({ name = f.ITEM, count = contents })
  end
  hub.providing_to_other_platforms = providing ~= false
  return hub
end

describe('ванильные передачи 2.1', function()
  before_all(f.prepare_force)
  before_each(f.clear)
  after_each(f.clear)

  it('V-00 опора: A без запросов с флагом раздачи отдаёт B', function()
    local a = supplier('a', 500)
    expect_transfer('V-00', a, 'без запросов, флаг вкл', function(reached)
      assert(reached, 'опорная передача не состоялась — оснастка не годится для наблюдений')
    end)
  end)

  it('V-00b опора: A без запросов с выключенным флагом', function()
    local a = supplier('a', 500, false)
    expect_transfer('V-00b', a, 'без запросов, флаг выкл')
  end)

  for _, variant in ipairs({
    { id = 'V-01a', label = 'один запрос, источник planet', opts = { from = 'planet', import_from = 'nauvis' } },
    { id = 'V-01b', label = 'один запрос, источник platforms', opts = { from = 'platforms', import_from = 'nauvis' } },
    { id = 'V-01c', label = 'один запрос, источник all', opts = { from = 'all', import_from = 'nauvis' } },
    { id = 'V-01d', label = 'один запрос, import_from другой планеты', opts = { from = 'planet', import_from = 'vulcanus' } },
    { id = 'V-01e', label = 'один запрос, пустой import_from', opts = { from = 'all' } },
  }) do
    it(variant.id .. ' ' .. variant.label .. ', запрос равен содержимому', function()
      local a = supplier('a', 500)
      f.request(a, 500, variant.opts)
      expect_transfer(variant.id, a, variant.label .. ', запрошено 500, есть 500')
    end)
  end

  it('V-02a два запроса planet + planet', function()
    local a = supplier('a', 500)
    f.request(a, 100, { from = 'planet', import_from = 'nauvis' })
    f.request(a, 100, { from = 'planet', import_from = 'nauvis' })
    expect_transfer('V-02a', a, 'два запроса planet по 100, есть 500')
  end)

  it('V-02b два запроса planet + platforms', function()
    local a = supplier('a', 500)
    f.request(a, 100, { from = 'planet', import_from = 'nauvis' })
    f.request(a, 100, { from = 'platforms', import_from = 'nauvis' })
    expect_transfer('V-02b', a, 'запросы planet 100 + platforms 100, есть 500')
  end)

  it('V-02c два запроса: груз из другой планеты + свой', function()
    local a = supplier('a', 500)
    f.request(a, 100, { from = 'planet', import_from = 'vulcanus' })
    f.request(a, 100, { from = 'all' })
    expect_transfer('V-02c', a, 'груз из vulcanus 100 + пустой import_from 100, есть 500')
  end)

  it('V-03a излишек сверх min', function()
    local a = supplier('a', 500)
    f.request(a, 100, { from = 'planet', import_from = 'nauvis' })
    expect_transfer('V-03a', a, 'запрос min 100, есть 500')
  end)

  it('V-03b излишек сверх max', function()
    local a = supplier('a', 500)
    f.request(a, 100, { max = 100, from = 'planet', import_from = 'nauvis' })
    expect_transfer('V-03b', a, 'запрос min=max=100, есть 500', function()
      f.observe('V-03b', string.format('в мусорных слотах A %d', f.trash(a)))
    end)
  end)

  for _, variant in ipairs({
    { id = 'V-04a', providing = true, request = nil, label = 'флаг вкл, без запросов' },
    { id = 'V-04b', providing = false, request = nil, label = 'флаг выкл, без запросов' },
    { id = 'V-04c', providing = false, request = { from = 'planet', import_from = 'vulcanus' }, label = 'флаг выкл, груз из vulcanus' },
    { id = 'V-04d', providing = true, request = { from = 'planet', import_from = 'nauvis' }, label = 'флаг вкл, запрос с nauvis' },
  }) do
    it(variant.id .. ' сброс на планету: ' .. variant.label, function()
      local a = supplier('a', 500, variant.providing)
      if variant.request then
        f.request(a, 100, variant.request)
      end
      local pad = f.pad()
      f.request(pad, WANT)
      f.watch(f.WAIT, function()
        return f.count(pad) >= WANT
      end, function(elapsed)
        f.observe(variant.id, string.format('%s: площадка получила %d из %d за %d тиков, у A стало %d, в пути к площадке %d',
          variant.label, f.count(pad), WANT, elapsed, f.count(a), f.incoming(pad)))
      end)
    end)
  end

  it('V-05 реакция на смену request_from у получателя', function()
    local a = supplier('a', 500)
    local _, b = f.platform('b')
    local section = f.request(b, WANT, { from = 'planet', import_from = f.PLANET })
    after_ticks(600, function()
      local held = f.count(b)
      section.set_slot(1, {
        value = { type = 'item', name = f.ITEM, quality = 'normal', comparator = '=' },
        min = WANT,
        request_from = 'platforms',
        import_from = f.PLANET,
      })
      f.watch(f.WAIT, function()
        return f.count(b) >= WANT or f.incoming(b) > 0
      end, function(elapsed)
        f.observe('V-05', string.format('до смены за 600 тиков B получил %d; после смены planet → platforms: первый груз в пути или на месте через %d тиков (в пути %d, на месте %d)',
          held, elapsed, f.incoming(b), f.count(b)))
      end)
    end)
    assert(a.valid)
  end)

  it('V-06a блокировка груза: import_from переставлен на текущую орбиту', function()
    local a = supplier('a', 500)
    f.request(a, 500, { from = 'planet', import_from = f.PLANET })
    expect_transfer('V-06a', a, 'груз набран, import_from = текущая орбита nauvis, запрошено 500 = есть 500')
  end)

  it('V-06b блокировка груза: секция груза выключена', function()
    local a = supplier('a', 500)
    local section = f.request(a, 500, { from = 'planet', import_from = f.OTHER_PLANET })
    section.active = false
    expect_transfer('V-06b', a, 'секция груза из vulcanus выключена, есть 500')
  end)

  it('V-06c блокировка груза: флаг раздачи выключен', function()
    local a = supplier('a', 500, false)
    f.request(a, 500, { from = 'planet', import_from = f.OTHER_PLANET })
    expect_transfer('V-06c', a, 'груз из vulcanus, флаг выкл, есть 500')
  end)

  -- Наблюдения V-01b и V-04d подсказывают замок: запрос с источником `all`
  -- от текущей орбиты не отдаётся ни платформам, ни своей планете. Проверяем
  -- обе стороны сразу, при наборе, равном запросу.
  for _, variant in ipairs({
    { id = 'V-06d', from = 'all' },
    { id = 'V-06e', from = 'platforms' },
  }) do
    it(variant.id .. ' блокировка груза: import_from текущей орбиты, источник ' .. variant.from, function()
      local a = supplier('a', 500)
      f.request(a, 500, { from = variant.from, import_from = f.PLANET })
      local pad = f.pad()
      f.request(pad, WANT)
      expect_transfer(variant.id, a, 'import_from nauvis, источник ' .. variant.from .. ', запрошено 500 = есть 500, площадка тоже просит', function()
        f.observe(variant.id, string.format('площадка получила %d, в пути к площадке %d', f.count(pad), f.incoming(pad)))
      end)
    end)
  end

  -- Замок контроллера: своя секция без группы с фильтром min = 0. Блокирует
  -- ли такой фильтр отдачу, не трогая пользовательские секции.
  for _, variant in ipairs({
    { id = 'V-11a', cargo = nil, label = 'без других запросов' },
    { id = 'V-11b', cargo = { from = 'planet', import_from = 'vulcanus' }, label = 'рядом груз из vulcanus 500' },
    { id = 'V-11c', cargo = { from = 'planet', import_from = 'nauvis' }, label = 'рядом запрос planet с nauvis 500' },
  }) do
    it(variant.id .. ' замок min = 0, источник all, import_from текущей орбиты: ' .. variant.label, function()
      local a = supplier('a', 500)
      if variant.cargo then
        f.request(a, 500, variant.cargo)
      end
      f.request(a, 0, { from = 'all', import_from = f.PLANET })
      local pad = f.pad()
      f.request(pad, WANT)
      local pad_before = f.count(pad)
      expect_transfer(variant.id, a, 'замок min 0, ' .. variant.label .. ', площадка тоже просит', function()
        f.observe(variant.id, string.format('площадка получила %d', f.count(pad) - pad_before))
      end)
    end)
  end

  -- Замок без привязки к орбите: если он держит, на прилёте нет гонки между
  -- ванилью и контроллером.
  for _, variant in ipairs({
    { id = 'V-11d', import_from = nil, label = 'пустой import_from' },
    { id = 'V-11e', import_from = 'vulcanus', label = 'import_from другой орбиты' },
  }) do
    it(variant.id .. ' замок min = 0, источник all, ' .. variant.label .. ', рядом груз из vulcanus', function()
      local a = supplier('a', 500)
      f.request(a, 500, { from = 'planet', import_from = f.OTHER_PLANET })
      f.request(a, 0, { from = 'all', import_from = variant.import_from })
      local pad = f.pad()
      f.request(pad, WANT)
      local pad_before = f.count(pad)
      expect_transfer(variant.id, a, 'замок min 0, ' .. variant.label .. ', площадка тоже просит', function()
        f.observe(variant.id, string.format('площадка получила %d', f.count(pad) - pad_before))
      end)
    end)
  end

  for _, variant in ipairs({
    { id = 'V-14a', group = 'shm-probe-depot', label = 'запрос planet в секции с группой' },
    { id = 'V-14b', group = nil, label = 'тот же запрос без группы' },
  }) do
    it(variant.id .. ' ' .. variant.label, function()
      local a = supplier('a', 500)
      local section = f.request(a, 500, { group = variant.group, from = 'planet', import_from = f.PLANET })
      local slot = section.get_slot(1)
      expect_transfer(variant.id, a, variant.label .. ' (читается request_from ' .. tostring(slot.request_from) .. ')')
    end)
  end

  -- Как ваниль раскладывает дефицит, когда у предмета есть фильтр с планеты
  -- и фильтр с платформ: склад D просит 1000 с планеты (ракет нет), держит
  -- 700, и ему добавлен запрос с платформ. Сколько он наберёт с платформ.
  for _, variant in ipairs({
    { id = 'V-15a', planet = 1000, platforms = 300, label = 'planet 1000 + platforms 300' },
    { id = 'V-15b', planet = 1000, platforms = 100, label = 'planet 1000 + platforms 100' },
    { id = 'V-15c', planet = 1000, platforms = 0, label = 'planet 1000 + platforms 0 (замок)' },
    { id = 'V-15d', planet = 0, platforms = 1000, label = 'только platforms 1000' },
    { id = 'V-15e', planet = 1000, platforms = 1300, label = 'planet 1000 + platforms 1300' },
    { id = 'V-15f', planet = 1000, platforms = 0, lock = true, label = 'planet 1000 + замок min 0 all без import_from' },
    { id = 'V-15g', planet = 1000, planet_from = 'vulcanus', platforms = 0, lock = true,
      label = 'груз из vulcanus 1000 + замок min 0 all без import_from' },
  }) do
    it(variant.id .. ' дефицит склада при двух источниках: ' .. variant.label, function()
      supplier('a', 3000)
      local _, d = f.platform('d')
      d.insert({ name = f.ITEM, count = 700 })
      if variant.planet > 0 then
        f.request(d, variant.planet, { from = 'planet', import_from = variant.planet_from or f.PLANET })
      end
      if variant.lock then
        f.request(d, 0, { from = 'all' })
      else
        f.request(d, variant.platforms, { from = 'platforms', import_from = f.PLANET })
      end
      local highest = 700
      f.watch(f.WAIT, function()
        highest = math.max(highest, f.count(d))
        return false
      end, function()
        f.observe(variant.id, string.format('%s, было 700: стало %d, максимум %d, в пути %d',
          variant.label, f.count(d), highest, f.incoming(d)))
      end)
    end)
  end

  it('V-12 запросы одного предмета из двух секций складываются', function()
    local a = supplier('a', 500)
    local _, b = f.platform('b')
    f.request(b, 60, { from = 'platforms', import_from = f.PLANET })
    f.request(b, 40, { from = 'platforms', import_from = f.PLANET })
    f.watch(f.WAIT, function()
      return f.count(b) >= 100
    end, function(elapsed)
      after_ticks(300, function()
        f.observe('V-12', string.format('секции 60 + 40: B получил %d за %d тиков (+300 на дозревание)', f.count(b), elapsed))
      end)
    end)
    assert(a.valid)
  end)

  it('V-13 active у секции с группой — свой у каждой сущности', function()
    local group = 'shm-probe-active'
    local _, a = f.platform('a')
    local _, b = f.platform('b')
    local section_a = f.request(a, 100, { group = group, from = 'planet', import_from = f.PLANET })
    local section_b = b.get_logistic_sections().add_section(group)
    section_a.active = false
    f.observe('V-13', string.format('после active = false на A: A %s, B %s', tostring(section_a.active), tostring(section_b.active)))
  end)

  it('V-07 request_from в фильтре ванильной группы расходится по участникам', function()
    local group = 'shm-probe-group'
    local _, a = f.platform('a')
    local _, b = f.platform('b')
    local section_a = f.request(a, 100, { group = group, from = 'planet', import_from = f.PLANET })
    local section_b = b.get_logistic_sections().add_section(group)
    section_b.multiplier = 5
    section_a.set_slot(1, {
      value = { type = 'item', name = f.ITEM, quality = 'normal', comparator = '=' },
      min = 200,
      request_from = 'platforms',
      import_from = f.PLANET,
    })
    local slot = section_b.get_slot(1)
    f.observe('V-07', string.format('в группе на B после правки на A: предмет %s, min %s, request_from %s, import_from %s, множитель A %s, B %s',
      tostring(slot.value and slot.value.name), tostring(slot.min), tostring(slot.request_from),
      tostring(slot.import_from and (slot.import_from.name or slot.import_from)),
      tostring(section_a.multiplier), tostring(section_b.multiplier)))
  end)

  it('V-08 cargo pod скриптом с хаба на хаб', function()
    local a = supplier('a', 500, false)
    local _, b = f.platform('b')
    local ok, pod = pcall(function()
      return a.create_cargo_pod()
    end)
    if not ok or not pod then
      f.observe('V-08', 'create_cargo_pod на хабе не создал pod: ' .. tostring(pod))
      return
    end
    pod.get_inventory(defines.inventory.cargo_unit).insert({ name = f.ITEM, count = WANT })
    f.inventory(a).remove({ name = f.ITEM, count = WANT })
    local set_ok, err = pcall(function()
      pod.cargo_pod_destination = { type = defines.cargo_destination.station, station = b }
    end)
    if not set_ok then
      f.observe('V-08', 'назначение pod на хаб другой платформы не принято: ' .. tostring(err))
      return
    end
    local incoming_now = f.incoming(b)
    f.watch(f.WAIT, function()
      return f.count(b) >= WANT
    end, function(elapsed)
      f.observe('V-08', string.format('pod с хаба A на хаб B: в пути сразу после запуска %d, B получил %d за %d тиков',
        incoming_now, f.count(b), elapsed))
    end)
  end)

  it('V-09 источник у запросов, выставленных сетью', function()
    local platform, hub = f.platform('a')
    local surface = platform.surface
    local tiles = {}
    for x = 6, 9 do
      for y = -2, 2 do
        tiles[#tiles + 1] = { name = 'space-platform-foundation', position = { x, y } }
      end
    end
    surface.set_tiles(tiles)
    local combinator = surface.create_entity({ name = 'constant-combinator', position = { 7.5, 0.5 }, force = 'player' })
    assert(combinator, 'комбинатор не создан')
    local behavior = combinator.get_or_create_control_behavior() --[[@as LuaConstantCombinatorControlBehavior]]
    behavior.get_section(1).set_slot(1, {
      value = { type = 'item', name = f.ITEM, quality = 'normal', comparator = '=' },
      min = 300,
    })
    local red = defines.wire_connector_id.circuit_red
    local connected = combinator.get_wire_connector(red, true).connect_to(hub.get_wire_connector(red, true))
    local hub_behavior = hub.get_or_create_control_behavior() --[[@as LuaSpacePlatformHubControlBehavior]]
    pcall(function()
      hub_behavior.read_contents = false
    end)
    local set_ok = pcall(function()
      hub_behavior.set_requests = true
    end)
    after_ticks(10, function()
      local seen = {}
      local sections = hub.get_logistic_sections()
      for index = 1, sections.sections_count do
        local section = sections.get_section(index)
        for slot_index = 1, section.filters_count do
          local slot = section.get_slot(slot_index)
          if slot.value and slot.value.name == f.ITEM then
            seen[#seen + 1] = string.format('секция %d тип %s: min %s, request_from %s, import_from %s',
              index, tostring(section.type), tostring(slot.min), tostring(slot.request_from),
              tostring(slot.import_from and (slot.import_from.name or slot.import_from)))
          end
        end
      end
      f.observe('V-09', string.format('провод %s, set_requests %s; %s', tostring(connected), tostring(set_ok),
        #seen > 0 and table.concat(seen, '; ') or 'запрос сети не виден в секциях хаба'))
    end)
  end)
end)
