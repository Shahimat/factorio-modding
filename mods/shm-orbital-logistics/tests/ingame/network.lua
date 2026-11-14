-- Полный dev-only пример: первичный груз рождается только в бесконечных
-- провайдерах на планетах. Доставки наблюдаются через реальные события pod.
local demo = require('tests.demo.network')
local spec = require('tests.demo.network_spec')
local force

local function item_count(entity, item)
  local inventory = entity.type == 'cargo-landing-pad' and defines.inventory.cargo_landing_pad_main or defines.inventory.hub_main
  return entity.get_inventory(inventory).get_item_count(item)
end

describe('планетарная демо-сеть', function()
  before_all(function()
    force = game.forces['shm-demo-network-test'] or game.create_force('shm-demo-network-test')
  end)
  after_each(function() demo.clear(force) end)

  it('пять планет отправляют настоящие ракеты и принимают груз; повторный запуск не дублирует сцену', function()
    async(8 * 60 * 60)
    local function researched()
      local total = 0
      for _, technology in pairs(force.technologies) do if technology.researched then total = total + 1 end end
      return total
    end
    local before_research = researched()
    demo.build(force, game.tick)
    assert(researched() == before_research, 'демо исследовало технологии всей силы')
    local state = assert(demo.state(force))
    assert(#state.platforms == 10 and #state.shuttles == 5, 'не весь флот создан')
    demo.build(force, game.tick)
    assert(demo.state(force) == state and #state.platforms == 10, 'повторное создание продублировало флот')
    for _, cell in pairs(state.cells) do
      cell.unloader.disabled_by_script = true
      assert(cell.silo.use_transitional_requests, 'нет автоматических запросов силоса')
      assert(cell.pad.get_logistic_sections().sections_count > 0, 'площадка без фильтров')
      assert(cell.tag and cell.tag.valid, 'площадка не отмечена на карте')
    end
    for _, p in ipairs(state.platforms) do
      for _, planet in ipairs(spec.planets) do
        assert(item_count(p.hub, planet.item) == 0, 'груз уже вставлен скриптом в хаб')
      end
    end
    local elapsed, flying, visits = 0, false, {}
    on_tick(function()
      elapsed = elapsed + 1
      if game.tick % spec.PERIOD == 0 then demo.step(force) end
      for _, p in ipairs(state.shuttles) do
        if not p.space_location then flying = true end
        visits[p.index] = visits[p.index] or {}
        if p.space_location then visits[p.index][p.space_location.name] = true end
      end
      local complete = true
      for _, planet in ipairs(spec.planets) do
        local cell = state.cells[planet.name]
        local present = 0
        for _, other in ipairs(spec.imports(planet.name)) do present = present + item_count(cell.pad, other.item) end
        if cell.launches < 2 or cell.exported == 0 or cell.received == 0 or present == 0
            or cell.silo.products_finished < 2 then complete = false end
      end
      if complete or elapsed >= 7 * 60 * 60 then
        local status = table.concat(demo.status(force), ' | ')
        assert(complete, 'не весь круг работает: ' .. status .. ' | ' .. helpers.table_to_json(demo.diagnostics(force)))
        log('[OL-NETWORK-PROOF] tick=' .. elapsed .. ' ' .. status)
        local player = game.players[1]
        if player and player.connected then
          for name, cell in pairs(state.cells) do
            game.take_screenshot({ surface = cell.surface, position = { cell.position.x + 5, cell.position.y + 5 },
              resolution = { 1100, 900 }, zoom = 0.65, daytime = 0, show_gui = false, show_entity_info = true,
              force_render = true, path = 'orbital-demo/network-' .. name .. '.png' })
          end
          game.set_wait_for_screenshots_to_finish()
        end
        assert(flying, 'ни один челнок не вошёл в настоящий полёт')
        for _, p in ipairs(state.shuttles) do
          local n = 0
          for _ in pairs(visits[p.index]) do n = n + 1 end
          assert(n >= 2, 'челнок не посетил обе планеты: ' .. p.name)
        end
        -- Настоящий манипулятор должен разгрузить площадку в infinity sink.
        local before, delivered_before = {}, {}
        for name, cell in pairs(state.cells) do
          local total, delivered = 0, 0
          for _, other in ipairs(spec.imports(name)) do
            total = total + item_count(cell.pad, other.item)
            delivered = delivered + (cell.delivered[other.item] or 0)
          end
          before[name], delivered_before[name] = total, delivered
          cell.unloader.disabled_by_script = false
        end
        after_ticks(10 * 60, function()
          for name, cell in pairs(state.cells) do
            local total, delivered = 0, 0
            for _, other in ipairs(spec.imports(name)) do
              total = total + item_count(cell.pad, other.item)
              delivered = delivered + (cell.delivered[other.item] or 0)
            end
            -- Пока манипулятор разгружает, может прийти следующая капсула.
            -- Считаем отток с учётом настоящих доставок, а не чистый остаток.
            assert(total < before[name] + delivered - delivered_before[name], 'площадка не разгружается: ' .. name)
            assert(cell.unloader.pickup_target == cell.pad and cell.unloader.drop_target == cell.sink, 'манипулятор разгружает не в infinity sink')
          end
          local cell = state.cells.nauvis
          local neighbor = assert(cell.surface.create_entity({ name = 'steel-chest', position = { cell.position.x + 21.5, cell.position.y + 18.5 }, force = force }))
          neighbor.insert({ name = 'copper-plate', count = 17 })
          local foreign = assert(force.create_space_platform({ name = state.prefix .. 'User platform', planet = 'nauvis', starter_pack = 'space-platform-starter-pack' }))
          foreign.apply_starter_pack()
          foreign.hub.request_missing_construction_materials = false
          foreign.hub.insert({ name = 'copper-plate', count = 17 })
          local shared = state.groups[1]
          foreign.hub.get_logistic_sections().add_section(shared)
          assert(demo.clear(force) == 10 and demo.state(force) == nil, 'сеть не убрана полностью')
          assert(neighbor.valid and neighbor.get_inventory(defines.inventory.chest).get_item_count('copper-plate') == 17, 'чужая постройка затронута')
          assert(foreign.valid and foreign.scheduled_for_deletion == 0 and item_count(foreign.hub, 'copper-plate') == 17, 'платформа с похожим именем затронута')
          assert(force.get_logistic_group(shared), 'общая с чужим участником группа удалена')
          for _, own in ipairs(state.platforms) do assert(not own.valid or own.scheduled_for_deletion > 0, 'своя платформа осталась') end
          for _, own_cell in pairs(state.cells) do
            for _, own in ipairs(own_cell.entities) do assert(not own.valid, 'своя планетарная сущность осталась') end
            assert(not own_cell.tag or not own_cell.tag.valid, 'метка демо осталась на карте')
          end
          neighbor.destroy()
          foreign.destroy()
          force.delete_logistic_group(shared)
          assert(demo.clear(force) == 0, 'повторная очистка не идемпотентна')
          done()
        end)
        return false
      end
    end)
  end)

  it('существующая площадка блокирует создание до изменения чужого мира', function()
    local surface = game.planets.nauvis.surface
    local pad = assert(surface.create_entity({ name = 'cargo-landing-pad', position = { 528, 512 }, force = force }))
    local section = pad.get_logistic_sections().add_section('User pad')
    section.set_slot(1, { value = { type = 'item', name = 'copper-plate', quality = 'normal' }, min = 17 })
    local ok = pcall(demo.build, force, game.tick)
    assert(not ok and demo.state(force) == nil, 'существующая площадка не остановила создание')
    assert(pad.valid and section.valid and section.get_slot(1).min == 17, 'чужая площадка изменена')
    pad.destroy()
    force.delete_logistic_group('User pad')
  end)

  it('слияние сил убирает исходную демо-сеть, но сохраняет чужие постройки', function()
    local source = game.create_force('shm-demo-merge-source')
    local destination = game.create_force('shm-demo-merge-target')
    demo.build(source, game.tick)
    local state, index = demo.state(source), source.index
    local cell = state.cells.nauvis
    local chest = assert(cell.surface.create_entity({ name = 'steel-chest', position = { cell.position.x + 21.5, cell.position.y + 18.5 }, force = source }))
    chest.insert({ name = 'copper-plate', count = 17 })
    game.merge_forces(source, destination)
    -- merge_forces только планирует слияние в конце тика.
    after_ticks(2, function()
      assert(storage.shm_demo_network[index] == nil and demo.state(destination) == nil, 'сеть стала бесхозной')
      for _, p in ipairs(state.platforms) do assert(not p.valid or p.scheduled_for_deletion > 0, 'демо-платформа пережила слияние') end
      for _, own_cell in pairs(state.cells) do
        for _, entity in ipairs(own_cell.entities) do assert(not entity.valid, 'демо-ячейка пережила слияние') end
      end
      assert(chest.valid and chest.force == destination and chest.get_inventory(defines.inventory.chest).get_item_count('copper-plate') == 17, 'чужая постройка не пережила слияние')
      chest.destroy()
    end)
  end)
end)
