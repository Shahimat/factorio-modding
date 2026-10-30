-- Сценарии ядра K-02…K-20 из ТЗ `specs/27102026_spec_orbital_logistics.md`,
-- раздел 10: метки в группах, замки, склад, транзит, выдача собранного,
-- выключение мода. Почти везде схема одна: поставщик A на орбите, получатель
-- B запрашивает с платформ, и смотрим, кто что отдал.

local f = require('tests.ingame.fixture')
local controller = require('runtime.controller')
local scene = require('tests.demo.scene')
local live = require('tests.demo.live')
local demo = require('tests.demo.commands')

local WANT = 50
local HOLMIUM = 'holmium-plate'

local function supplier(label, contents, opts)
  opts = opts or {}
  local _, hub = f.platform(label, opts.planet)
  if contents > 0 then
    hub.insert({ name = opts.item or f.ITEM, count = contents })
  end
  hub.providing_to_other_platforms = opts.providing ~= false
  return hub
end

local function requester(label, count, opts)
  opts = opts or {}
  local _, hub = f.platform(label, opts.planet)
  f.request(hub, count, { item = opts.item, from = 'platforms', import_from = opts.planet or f.PLANET })
  return hub
end

local function wants_pad(count)
  local pad = f.pad()
  f.request(pad, count)
  return pad, f.count(pad)
end

--- Ждёт, пока `done_when()` не станет истинным или не выйдет время, следя
--- за минимумом у `watched`, и передаёт его в `finish`.
local function wait(watched, done_when, finish)
  local trackers = {}
  for _, hub in ipairs(watched) do
    trackers[#trackers + 1] = f.track(hub)
  end
  f.watch(f.WAIT, function()
    for _, tracker in ipairs(trackers) do
      tracker.step()
    end
    return done_when()
  end, function(elapsed, reached)
    local lows = {}
    for index, tracker in ipairs(trackers) do
      lows[index] = tracker.lowest
    end
    finish(lows, reached, elapsed)
  end)
end

--- Фильтры служебной группы мода на хабе и сама секция; nil — группы нет.
local function own_filters(hub)
  local sections = hub.get_logistic_sections()
  for index = 1, sections.sections_count do
    local section = sections.get_section(index)
    if section.is_manual and controller.is_service(section.group) then
      local filters = {}
      for slot = 1, section.filters_count do
        local s = section.get_slot(slot)
        if s.value then
          filters[#filters + 1] = { name = s.value.name, min = s.min or 0, request_from = s.request_from }
        end
      end
      return filters, section
    end
  end
  return nil
end

describe('ядро', function()
  before_all(f.prepare_force)
  before_each(f.clear)
  after_each(f.clear)

  it('K-19 без меток мод ничего не ставит на хаб', function()
    local a = supplier('a', 500)
    f.request(a, 100, { from = 'planet', import_from = f.PLANET })
    f.request(a, 100, { from = 'all' })
    local before = a.get_logistic_sections().sections_count
    controller.pass()
    assert(a.get_logistic_sections().sections_count == before, 'секций стало больше')
    assert(own_filters(a) == nil, 'появилась своя секция')
  end)

  it('K-02 склад на своей орбите отдаёт платформе', function()
    local a = supplier('a', 500)
    f.request(a, 500, { group = 'Plates [depot:nauvis]', from = 'planet', import_from = f.PLANET })
    local b = requester('b', WANT)
    controller.pass()
    wait({ a }, function()
      return f.count(b) >= WANT
    end, function(_, reached)
      assert(reached, 'склад не отдал: у B ' .. f.count(b))
    end)
  end)

  it('K-07 свой запас не отдаётся ни платформе, ни планете', function()
    local a = supplier('a', 500)
    f.request(a, 500, { group = 'Fuel [reserve]', from = 'planet', import_from = f.PLANET })
    local b = requester('b', WANT)
    wants_pad(WANT)
    controller.pass()
    wait({ a }, function()
      return false
    end, function(lows)
      assert(lows[1] == 500, 'запас отдан: минимум у A ' .. lows[1])
      assert(f.count(b) == 0, 'B получил ' .. f.count(b))
    end)
  end)

  it('K-03 груз до Аквило держится на Нависе и отдаётся на Аквило', function()
    local a = supplier('a', 500)
    f.request(a, 500, { group = 'Plates [cargo→aquilo]', from = 'planet', import_from = f.PLANET })
    local b = requester('b', WANT)
    wants_pad(WANT)
    controller.pass()
    wait({ a }, function()
      return false
    end, function(lows)
      assert(lows[1] == 500, 'груз отдан на Нависе: минимум у A ' .. lows[1])
      assert(f.count(b) == 0, 'B на Нависе получил ' .. f.count(b))
      a.surface.platform.space_location = 'aquilo'
      local c = requester('c', WANT, { planet = 'aquilo' })
      controller.pass()
      wait({}, function()
        return f.count(c) >= WANT
      end, function(_, reached)
        assert(reached, 'на Аквило груз не отдан: у C ' .. f.count(c))
      end)
    end)
  end)

  it('K-04 груз со списком планет: первая забирает всё', function()
    local a = supplier('a', 500)
    f.request(a, 500, { group = 'Plates [cargo→nauvis,aquilo]', from = 'planet', import_from = f.OTHER_PLANET })
    local b = requester('b', 500)
    controller.pass()
    wait({}, function()
      return f.count(b) >= 500
    end, function(_, reached)
      assert(reached, 'B получил ' .. f.count(b) .. ' из 500')
    end)
  end)

  it('K-05 груз [cargo] сбрасывается по запросу по-ванильному', function()
    local a = supplier('a', 500)
    f.request(a, 500, { group = 'Plates [cargo]', from = 'planet', import_from = f.OTHER_PLANET })
    local pad, before = wants_pad(WANT)
    controller.pass()
    wait({ a }, function()
      return f.count(pad) - before >= WANT
    end, function(lows, reached)
      assert(reached and lows[1] < 500, 'не сброшен: площадка ' .. (f.count(pad) - before) .. ', минимум у A ' .. lows[1])
    end)
  end)

  it('K-06 транзит: груз для Нависа уходит на склад, потом склад отдаёт', function()
    local shuttle = supplier('s', 200, { item = HOLMIUM })
    f.request(shuttle, 200, { item = HOLMIUM, group = 'Holmium [cargo→nauvis]', from = 'planet', import_from = 'fulgora' })
    local _, depot = f.platform('d')
    depot.providing_to_other_platforms = true
    f.request(depot, 100, { item = HOLMIUM, group = 'Holmium [depot:nauvis]', from = 'planet', import_from = f.PLANET })
    controller.pass()
    local filters = own_filters(depot)
    assert(filters and filters[1].request_from == 'platforms' and filters[1].min == 0,
      'нет транзита на склад: ' .. serpent.line(filters))
    wait({}, function()
      return f.count(depot, HOLMIUM) >= 100
    end, function(_, reached)
      assert(reached, 'склад получил ' .. f.count(depot, HOLMIUM) .. ' из 100')
      local settled = f.count(depot, HOLMIUM) + f.incoming(depot, HOLMIUM)
      assert(settled <= 100, 'склад переполнен транзитом: ' .. settled .. ' при цели 100')
      controller.pass()
      local after = own_filters(depot)
      assert(after == nil or after[1].request_from ~= 'platforms', 'транзит не снят: ' .. serpent.line(after))
      local c = requester('c', WANT, { item = HOLMIUM })
      wait({}, function()
        return f.count(c, HOLMIUM) >= WANT
      end, function(_, got)
        assert(got, 'C получил ' .. f.count(c, HOLMIUM))
      end)
    end)
  end)

  it('K-08 запас и склад одного предмета: запас не уходит', function()
    local a = supplier('a', 500)
    f.request(a, 200, { group = 'Plates [reserve]', from = 'planet', import_from = f.PLANET })
    f.request(a, 300, { group = 'Plates [depot:nauvis]', from = 'planet', import_from = f.PLANET })
    local b = requester('b', 300)
    controller.pass()
    wait({ a }, function()
      return f.count(b) >= 300
    end, function(lows, reached)
      assert(reached, 'склад не отдал свою часть: у B ' .. f.count(b))
      local b2 = requester('b2', 100)
      controller.pass()
      wait({ a }, function()
        return false
      end, function(lows2)
        assert(lows[1] >= 200 and lows2[1] >= 200, 'запас задет: минимумы у A ' .. lows[1] .. ', ' .. lows2[1])
        assert(f.count(b2) == 0, 'B2 получил из запаса ' .. f.count(b2))
      end)
    end)
  end)

  it('K-09 склад [depot] работает на любой орбите', function()
    local a = supplier('a', 500, { planet = f.OTHER_PLANET })
    f.request(a, 500, { group = 'Plates [depot]', from = 'planet', import_from = f.OTHER_PLANET })
    local b = requester('b', WANT, { planet = f.OTHER_PLANET })
    controller.pass()
    wait({}, function()
      return f.count(b) >= WANT
    end, function(_, reached)
      assert(reached, 'склад на Вулкане не отдал: у B ' .. f.count(b))
    end)
  end)

  it('K-10 склад вне своих орбит держит, как запас', function()
    local a = supplier('a', 500, { planet = f.OTHER_PLANET })
    f.request(a, 500, { group = 'Plates [depot:nauvis]', from = 'planet', import_from = f.OTHER_PLANET })
    requester('b', WANT, { planet = f.OTHER_PLANET })
    controller.pass()
    wait({ a }, function()
      return false
    end, function(lows)
      assert(lows[1] == 500, 'склад отдал вне своей орбиты: минимум у A ' .. lows[1])
    end)
  end)

  it('K-11 два склада одной орбиты не перекачивают предмет', function()
    local a = supplier('a', 500)
    f.request(a, 500, { group = 'Plates [depot:nauvis]', from = 'planet', import_from = f.PLANET })
    local _, b = f.platform('b')
    f.request(b, 500, { group = 'Plates [depot:nauvis]', from = 'planet', import_from = f.PLANET })
    controller.pass()
    wait({ a }, function()
      return false
    end, function(lows)
      assert(lows[1] == 500 and f.count(b) == 0, 'склады перекачали: минимум у A ' .. lows[1] .. ', у B ' .. f.count(b))
    end)
  end)

  it('K-12 привезённый груз отдаётся раньше склада', function()
    local shuttle = supplier('s', 500)
    f.request(shuttle, 500, { group = 'Plates [cargo→nauvis]', from = 'planet', import_from = f.OTHER_PLANET })
    local depot = supplier('d', 500)
    f.request(depot, 500, { group = 'Plates [depot:nauvis]', from = 'planet', import_from = f.PLANET })
    local b = requester('b', WANT)
    controller.pass()
    wait({ depot }, function()
      return f.count(b) >= WANT
    end, function(lows, reached)
      assert(reached, 'B получил ' .. f.count(b))
      assert(lows[1] == 500, 'отдал склад, а не груз: минимум у склада ' .. lows[1])
    end)
  end)

  it('K-13 сбор «из всех локаций» не сбрасывается по пути и выдаётся на назначении', function()
    local a = supplier('a', 0)
    local section = f.request(a, 50000, { group = 'Scrap [cargo→fulgora]', from = 'all' })
    local c = supplier('c', 300)
    wants_pad(WANT)
    controller.pass()
    wait({}, function()
      return f.count(a) >= 300
    end, function(_, reached)
      assert(reached, 'сбор не набрал: у A ' .. f.count(a))
      assert(c.valid)
      local held = f.count(a)
      wait({ a }, function()
        return false
      end, function(lows)
        assert(lows[1] == held, 'сбор сброшен по пути: минимум у A ' .. lows[1] .. ' из ' .. held)
        a.surface.platform.space_location = 'fulgora'
        controller.pass()
        assert(section.active == false, 'секция сбора не выключена на назначении')
        local d = requester('d', WANT, { planet = 'fulgora' })
        wait({}, function()
          return f.count(d) >= WANT
        end, function(_, got)
          assert(got, 'на Фульгоре сбор не выдан: у D ' .. f.count(d))
          a.surface.platform.space_location = f.PLANET
          controller.pass()
          assert(section.active == true, 'секция сбора не включена после ухода')
        end)
      end)
    end)
  end)

  it('K-14 излишек склада сверх max уходит по-ванильному', function()
    local a = supplier('a', 500)
    f.request(a, 100, { max = 100, group = 'Plates [depot:nauvis]', from = 'planet', import_from = f.PLANET })
    controller.pass()
    wait({}, function()
      return f.count(a) <= 100
    end, function(_, reached)
      assert(reached, 'излишек остался: у A ' .. f.count(a))
    end)
  end)

  it('K-20 флаг раздачи выключен: склад не отдаёт платформам, запас по-прежнему под замком', function()
    local a = supplier('a', 500, { providing = false })
    f.request(a, 300, { group = 'Plates [depot:nauvis]', from = 'planet', import_from = f.PLANET })
    local b = requester('b', WANT)
    local _, fuel = f.platform('fuel')
    fuel.insert({ name = f.ITEM, count = 100 })
    f.request(fuel, 100, { group = 'Fuel [reserve]', from = 'planet', import_from = f.PLANET })
    local pad, before = wants_pad(WANT)
    controller.pass()
    wait({ a, fuel }, function()
      return false
    end, function(lows)
      assert(lows[1] == 500 and f.count(b) == 0, 'склад с выключенным флагом отдал: у B ' .. f.count(b))
      assert(lows[2] == 100, 'запас сброшен на планету: минимум ' .. lows[2] .. ', площадка ' .. (f.count(pad) - before))
    end)
  end)

  it('выключение мода снимает свои секции и включает секции груза', function()
    local a = supplier('a', 100, { planet = 'fulgora' })
    f.request(a, 100, { group = 'Fuel [reserve]', from = 'planet', import_from = 'fulgora' })
    local collect = f.request(a, 5000, { group = 'Scrap [cargo→fulgora]', from = 'all' })
    controller.pass()
    assert(own_filters(a) ~= nil, 'замок не поставлен')
    assert(collect.active == false, 'сбор не выключен на назначении')
    settings.global[controller.SETTING] = { value = false }
    after_ticks(2, function()
      local sections_left = own_filters(a)
      local collect_active = collect.active
      -- Включаем обратно до проверок, чтобы упавшая проверка не оставила мод
      -- выключенным для следующих тестов; контроллер сразу снова выключит
      -- секцию сбора — платформа на назначении, — поэтому значения сняты раньше.
      settings.global[controller.SETTING] = { value = true }
      assert(sections_left == nil, 'своя секция осталась')
      assert(collect_active == true, 'секция сбора не включена')
    end)
  end)
end)

describe('демо-сцена', function()
  before_all(f.prepare_force)

  it('строится и через полминуты игры даёт ожидаемый итог по всем платформам', function()
    local force = game.forces['player']
    scene.build(force)
    remote.call('shm-orbital-logistics', 'pass')
    after_ticks(30 * 60, function()
      local failed = {}
      for _, result in ipairs(scene.check(force)) do
        if not result.ok then
          failed[#failed + 1] = result.name
        end
      end
      scene.clear(force)
      assert(#failed == 0, 'не как ожидается: ' .. table.concat(failed, '; '))
    end)
  end)
end)

describe('живая демо-сцена', function()
  before_all(f.prepare_force)

  it('за три круга плиты доходят до склада и потребителя Аквило, но не до Вулкана, а гольмий — до склада Нависа', function()
    local force = game.forces['player']
    live.build(force, game.tick)
    local elapsed = 0
    local total = 4 * live.STOP_TICKS + 10 * 60
    local aquilo_got, vulcanus_got, holmium_got, depot_got, depot_peak = 0, 0, 0, 0, 0
    local moves = {}
    on_tick(function()
      elapsed = elapsed + 1
      -- Сцена считает время по `game.tick`, как в dev-моде; тик теста
      -- считается от начала теста и с ним не совпадает.
      if game.tick % live.PERIOD == 0 then
        live.shield(force)
        for _, line in ipairs(live.step(force, game.tick)) do
          moves[#moves + 1] = line
        end
      end
      for _, platform in pairs(force.platforms) do
        if platform.valid and platform.hub and platform.hub.valid then
          local inventory = platform.hub.get_inventory(defines.inventory.hub_main)
          if string.find(platform.name, 'OLL-5', 1, true) then
            aquilo_got = math.max(aquilo_got, inventory.get_item_count(f.ITEM))
          elseif string.find(platform.name, 'OLL-4', 1, true) then
            depot_got = math.max(depot_got, inventory.get_item_count(f.ITEM))
            depot_peak = math.max(depot_peak, inventory.get_item_count(f.ITEM) + f.incoming(platform.hub))
          elseif string.find(platform.name, 'OLL-3', 1, true) then
            vulcanus_got = math.max(vulcanus_got, inventory.get_item_count(f.ITEM))
          elseif string.find(platform.name, 'OLL-7', 1, true) then
            holmium_got = math.max(holmium_got, inventory.get_item_count('holmium-plate'))
          end
        end
      end
      if elapsed >= total then
        live.clear(force)
        assert(aquilo_got > 0, 'потребитель над Аквило ничего не получил; перелёты: ' .. table.concat(moves, ' | '))
        assert(depot_got > 0, 'склад над Аквило ничего не получил по транзиту')
        assert(depot_peak <= 1000, 'склад над Аквило переполнен транзитом: ' .. depot_peak .. ' при цели 1000')
        assert(vulcanus_got == 0, 'потребитель над Вулканом получил ' .. vulcanus_got)
        assert(holmium_got > 0, 'склад гольмия над Нависом ничего не получил')
        return false
      end
    end)
  end)
end)

describe('перелёт без явного прохода', function()
  before_all(f.prepare_force)
  before_each(f.clear)
  after_each(f.clear)

  it('секция сбора, выключенная на назначении, включается обратно сама после отлёта', function()
    local platform, a = f.platform('a', 'fulgora')
    local section = f.request(a, 5000, { group = 'Test collect [cargo→fulgora]', from = 'all' })
    after_ticks(90, function()
      assert(section.active == false, 'на назначении секция не выключена')
      platform.space_location = 'vulcanus'
      after_ticks(90, function()
        assert(section.active == true, 'после отлёта секция не включена — состояние ' .. tostring(platform.state))
        game.forces.player.delete_logistic_group('Test collect [cargo→fulgora]')
      end)
    end)
  end)
end)

describe('живая сцена: группа груза после Аквило', function()
  before_all(f.prepare_force)

  it('у челнока OLL-2 над Вулканом после Аквило группа груза включена, лишних групп мода нет', function()
    local force = game.forces['player']
    live.build(force, game.tick)
    local elapsed = 0
    local seen_aquilo = false
    local problems = {}
    on_tick(function()
      elapsed = elapsed + 1
      if game.tick % live.PERIOD == 0 then
        live.step(force, game.tick)
      end
      for _, platform in pairs(force.platforms) do
        if platform.valid and string.find(platform.name, 'OLL-2', 1, true) and platform.hub and platform.hub.valid then
          local where = platform.space_location and platform.space_location.name
          if where == 'aquilo' then
            seen_aquilo = true
          elseif where == 'vulcanus' and seen_aquilo and elapsed % 120 == 0 then
            local sections = platform.hub.get_logistic_sections()
            local plain = 0
            for index = 1, sections.sections_count do
              local section = sections.get_section(index)
              if string.find(section.group, 'cargo', 1, true) and not section.active then
                problems[#problems + 1] = 'тик ' .. elapsed .. ': группа груза выключена'
              end
              if section.group == '' then
                plain = plain + 1
              end
            end
            if plain > 2 then
              problems[#problems + 1] = 'тик ' .. elapsed .. ': групп без имени ' .. plain
            end
          end
        end
      end
      if elapsed >= 4 * live.STOP_TICKS then
        live.clear(force)
        assert(seen_aquilo, 'челнок не долетел до Аквило')
        assert(#problems == 0, table.concat(problems, '; '))
        return false
      end
    end)
  end)
end)

describe('своя секция при выключенной секции груза', function()
  before_all(f.prepare_force)
  before_each(f.clear)
  after_each(f.clear)

  it('опустевшая своя секция узнаётся, а не заводится заново', function()
    local platform, a = f.platform('a', 'fulgora')
    f.request(a, 100, { group = 'Test fuel [reserve]', from = 'planet', import_from = 'fulgora' })
    local reserve_index = a.get_logistic_sections().sections_count
    f.request(a, 5000, { group = 'Test scrap [cargo→fulgora]', from = 'all' })
    controller.pass()
    -- Запас убран — замков не нужно, но секция сбора выключена: своя секция
    -- опустеет и останется.
    a.get_logistic_sections().remove_section(reserve_index)
    for _ = 1, 3 do
      controller.pass()
    end
    platform.space_location = 'vulcanus'
    a.get_logistic_sections().add_section('Test fuel [reserve]')
    for _ = 1, 3 do
      controller.pass()
    end
    local plain = 0
    local sections = a.get_logistic_sections()
    for index = 1, sections.sections_count do
      if sections.get_section(index).group == '' then
        plain = plain + 1
      end
    end
    game.forces.player.delete_logistic_group('Test fuel [reserve]')
    game.forces.player.delete_logistic_group('Test scrap [cargo→fulgora]')
    assert(plain <= 2, 'групп без имени ' .. plain .. ': мод завёл лишнюю')
  end)
end)

describe('выключенная секция груза после правки игрока', function()
  before_all(f.prepare_force)
  before_each(f.clear)
  after_each(f.clear)

  it('включается после отлёта, даже если игрок удалил секцию выше неё', function()
    local platform, a = f.platform('a', 'fulgora')
    f.request(a, 10, { item = 'copper-plate', from = 'planet', import_from = 'fulgora' })
    local section = f.request(a, 5000, { group = 'Test shift [cargo→fulgora]', from = 'all' })
    controller.pass()
    assert(section.active == false, 'на назначении не выключена')
    a.get_logistic_sections().remove_section(2)
    platform.space_location = 'vulcanus'
    controller.pass()
    local found
    local sections = a.get_logistic_sections()
    for index = 1, sections.sections_count do
      if sections.get_section(index).group == 'Test shift [cargo→fulgora]' then
        found = sections.get_section(index)
      end
    end
    game.forces.player.delete_logistic_group('Test shift [cargo→fulgora]')
    assert(found and found.active, 'секция груза осталась выключенной после сдвига номеров')
  end)
end)

describe('служебная группа', function()
  before_all(f.prepare_force)
  before_each(f.clear)
  after_each(f.clear)

  it('подписана своим именем, не делится с другими хабами и уходит из списка групп, когда держать нечего', function()
    local force = game.forces.player
    local platform, a = f.platform('a')
    local reserve = f.request(a, 100, { group = 'Test fuel [reserve]', from = 'planet', import_from = f.PLANET })
    controller.pass()
    local _, own = own_filters(a)
    assert(own and own.group == controller.service_name(platform), 'нет служебной группы с именем платформы')
    local _, b = f.platform('b')
    b.get_logistic_sections().add_section(own.group)
    controller.pass()
    assert(own_filters(b) == nil, 'служебная группа чужой платформы осталась на хабе B')
    reserve.group = 'Test fuel'
    controller.pass()
    assert(own_filters(a) == nil, 'служебная группа осталась без замков')
    assert(force.get_logistic_group(controller.service_name(platform)) == nil, 'служебная группа осталась в списке групп')
    force.delete_logistic_group('Test fuel [reserve]')
    force.delete_logistic_group('Test fuel')
  end)

  it('старая безымянная служебная секция снимается миграцией', function()
    local platform, a = f.platform('a')
    local legacy = a.get_logistic_sections().add_section()
    legacy.set_slot(1, { value = { type = 'item', name = f.ITEM, quality = 'normal', comparator = '=' }, min = 0, request_from = 'all' })
    storage.platforms[platform.index] = {
      own = legacy.index,
      written = { { key = f.ITEM .. '|normal', min = 0, request_from = 'all' } },
      released = {},
    }
    local before = a.get_logistic_sections().sections_count
    controller.migrate()
    assert(a.get_logistic_sections().sections_count == before - 1, 'старая служебная секция не снята')
  end)
end)

describe('демо-команда отладочной сборки', function()
  before_all(f.prepare_force)

  it('строит сцену, сверяет, показывает живую сцену и убирает всё', function()
    local force = game.forces['player']
    demo.handle({ parameter = nil, tick = game.tick })
    after_ticks(30 * 60, function()
      demo.handle({ parameter = 'check', tick = game.tick })
      for _, result in ipairs(scene.check(force)) do
        assert(result.ok, 'не как ожидается: ' .. result.name)
      end
      demo.handle({ parameter = 'live', tick = game.tick })
      demo.handle({ parameter = 'status', tick = game.tick })
      demo.on_tick({ tick = game.tick })
      demo.handle({ parameter = 'clear', tick = game.tick })
      for _, platform in pairs(force.platforms) do
        assert(not (platform.valid and platform.scheduled_for_deletion == 0 and string.sub(platform.name, 1, 2) == 'OL'),
          'демо-платформа осталась: ' .. platform.name)
      end
    end)
  end)
end)

describe('советы и подсказки', function()
  it('иконка маршрута Наувис — Вулкан для страницы мода существует', function()
    assert(helpers.is_valid_sprite_path('space-connection/nauvis-vulcanus'), 'нет иконки маршрута в этой сборке игры')
  end)
end)
