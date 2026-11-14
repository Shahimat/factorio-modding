-- Расширение существующей dev-only команды: настоящая планета → ракета →
-- орбитальный склад → челнок → склад/посадочная площадка → infinity sink.
-- Предметы груза не добавляются в хабы/площадки и не удаляются из них скриптом.
local spec = require('tests.demo.network_spec')
local cells = require('tests.demo.planet_cell')
local controller = require('runtime.controller')
local network = {}

local function book(force)
  return storage.shm_demo_network and storage.shm_demo_network[force.index]
end

local function count(entity, item)
  local index = entity.type == 'cargo-landing-pad' and defines.inventory.cargo_landing_pad_main or defines.inventory.hub_main
  return entity.get_inventory(index).get_item_count(item)
end

local function hub_of(p)
  return p and p.valid and p.scheduled_for_deletion == 0 and p.hub and p.hub.valid and p.hub or nil
end

local function request(state, entity, name, filters)
  assert(entity.force.get_logistic_group(name) == nil, 'Имя демо-группы занято: ' .. name)
  state.groups[#state.groups + 1] = name
  local section = assert(entity.get_logistic_sections().add_section(name))
  for index, filter in ipairs(filters) do
    section.set_slot(index, {
      value = { type = 'item', name = filter.item, quality = 'normal', comparator = '=' },
      min = filter.count, request_from = filter.from, import_from = filter.planet,
      minimum_delivery_count = 20,
    })
    assert(section.get_slot(index).value, 'Запрос не применился: ' .. filter.item)
  end
  return section
end

local function platform(force, state, name, planet)
  local p = assert(force.create_space_platform({ name = state.prefix .. name, planet = planet, starter_pack = 'space-platform-starter-pack' }))
  state.platforms[#state.platforms + 1] = p
  p.apply_starter_pack()
  p.hub.request_missing_construction_materials = false
  p.hub.providing_to_other_platforms = true
  p.hub.destructible = false
  -- Собственный запас виден в GUI, но не используется как груз сети.
  p.hub.insert({ name = 'repair-pack', count = spec.RESERVE })
  request(state, p.hub, state.prefix .. 'reserve #' .. p.index .. ' [reserve]', {
    { item = 'repair-pack', count = spec.RESERVE, from = 'planet', planet = planet },
  })
  return p
end

local function equip_shuttle(p)
  local floor = {}
  for x = -6, 5 do
    for y = -5, 11 do floor[#floor + 1] = { name = 'space-platform-foundation', position = { x, y } } end
  end
  p.surface.set_tiles(floor)
  local thruster = assert(p.surface.create_entity({ name = 'thruster', position = { 0, 9.5 }, force = p.force }))
  thruster.destructible = false
  for _, fluid in ipairs({ { x = -2.5, name = 'thruster-fuel' }, { x = 2.5, name = 'thruster-oxidizer' } }) do
    local pipe = assert(p.surface.create_entity({ name = 'infinity-pipe', position = { fluid.x, 7.5 }, force = p.force }))
    pipe.destructible = false
    pipe.set_infinity_pipe_filter({ name = fluid.name, percentage = 1, mode = 'at-least' })
  end
end

function network.clear(force)
  local state = book(force)
  if not state then return 0 end
  storage.shm_demo_network[force.index] = nil
  for _, rocket in pairs(state.rockets) do
    if rocket.valid then
      local pod = rocket.attached_cargo_pod
      if pod and pod.valid then pod.destroy() end
      rocket.destroy()
    end
  end
  for _, pod in pairs(state.pods) do
    if pod.entity.valid then pod.entity.destroy() end
  end
  for _, cell in pairs(state.cells) do cells.clear(cell) end
  local removed = 0
  for _, p in ipairs(state.platforms) do
    if p.valid and p.scheduled_for_deletion == 0 then
      local hub = p.hub
      if hub and hub.valid then
        hub.providing_to_other_platforms = false
        local sections = hub.get_logistic_sections()
        for index = sections.sections_count, 1, -1 do
          if sections.get_section(index).is_manual then sections.remove_section(index) end
        end
        hub.get_inventory(defines.inventory.hub_main).clear()
        hub.get_inventory(defines.inventory.hub_trash).clear()
      end
      p.destroy()
      removed = removed + 1
    end
  end
  for _, name in ipairs(state.groups) do
    local group = force.get_logistic_group(name)
    if group then
      local foreign = false
      for _, member in pairs(group.members) do
        if member.valid then foreign = true; break end
      end
      if not foreign then force.delete_logistic_group(name) end
    end
  end
  controller.pass()
  return removed
end

function network.build(force, tick)
  if book(force) then return { 'Демо-сеть уже построена; status — состояние, network-clear — удалить только эту сеть.' } end
  assert(script.active_mods['space-age'], 'Демо-сеть требует Space Age')
  -- Проверяем все планеты до любых изменений существующих площадок/сцен.
  for _, planet in ipairs(spec.planets) do
    local p = assert(game.planets[planet.name], 'Нет планеты ' .. planet.name)
    if p.surface then
      assert(p.surface.count_entities_filtered({ type = 'cargo-landing-pad', force = force }) == 0,
        'На ' .. planet.name .. ' уже есть грузовая площадка; используйте отдельную тестовую карту')
    end
  end
  storage.shm_demo_network = storage.shm_demo_network or {}
  storage.shm_demo_network_serial = (storage.shm_demo_network_serial or 0) + 1
  local state = { prefix = 'OLN-' .. storage.shm_demo_network_serial .. ' ', created = tick,
    platforms = {}, depots = {}, shuttles = {}, cells = {}, groups = {}, pods = {}, rockets = {}, started = {} }
  storage.shm_demo_network[force.index] = state
  local ok, err = pcall(function()
    -- Без исследований всей силы: только необходимые разрешения демонстрации.
    force.character_logistic_requests = true
    if force.cargo_landing_pad_limit == 0 then force.cargo_landing_pad_limit = 1 end
    for _, planet in ipairs(spec.planets) do
      force.unlock_space_location(planet.name)
      local entry = { planet = planet.name, item = planet.item, launches = 0, launch_orders = 0, exported = 0, received = 0, delivered = {} }
      state.cells[planet.name] = entry
      cells.build(force, planet, entry)
      local depot = platform(force, state, 'Depot ' .. planet.name, planet.name)
      state.depots[planet.name] = depot
      request(state, depot.hub, state.prefix .. planet.name .. ' export [depot:' .. planet.name .. ']', {
        { item = planet.item, count = spec.DEPOT_STOCK, from = 'planet', planet = planet.name },
      })
      local imports, pad_filters = {}, {}
      for _, other in ipairs(spec.imports(planet.name)) do
        imports[#imports + 1] = { item = other.item, count = spec.IMPORT_STOCK, from = 'platforms', planet = planet.name }
        pad_filters[#pad_filters + 1] = { item = other.item, count = spec.PAD_STOCK }
      end
      request(state, depot.hub, state.prefix .. planet.name .. ' imports [depot:' .. planet.name .. ']', imports)
      request(state, entry.pad, state.prefix .. planet.name .. ' landing pad', pad_filters)
    end
    for _, route in ipairs(spec.routes) do
      local p = platform(force, state, 'Shuttle ' .. route[1] .. ' ↔ ' .. route[2], route[1])
      state.shuttles[#state.shuttles + 1] = p
      equip_shuttle(p)
      for index = 1, 2 do
        local source, target = route[index], route[3 - index]
        request(state, p.hub, state.prefix .. source .. ' → ' .. target .. ' [cargo→' .. target .. ']', {
          { item = spec.planet(source).item, count = spec.SHUTTLE_STOCK, from = 'platforms', planet = source },
        })
      end
      p.schedule = { current = 2, records = {
        { station = route[1], wait_conditions = { { type = 'time', ticks = spec.STOP_TICKS } } },
        { station = route[2], wait_conditions = { { type = 'time', ticks = spec.STOP_TICKS } } },
      } }
      -- Первый выход только после настоящей загрузки со склада: стартовые
      -- ракеты и роботы не обязаны успеть за фиксированный таймер стоянки.
      p.paused = true
    end
    controller.pass()
  end)
  if not ok then
    network.clear(force)
    error(err)
  end
  return {
    'Orbital Logistics network: 5 планет, 5 складов и 5 двусторонних челноков OLN-.',
    'Настоящие ракеты снабжают склады; площадки запрашивают импорт, манипуляторы выгружают его в бесконечные поглотители.',
    'Челноки идут по штатному расписанию; тяга учебно ускорена скриптом, запаса топлива/турелей не требуется.',
    'Демо открыло пять планет и включило логистические запросы. Используйте только тестовую копию карты.',
    '/shm-orbital-demo status — адреса площадок и счётчики доставок; network-clear — убрать созданную сеть.',
  }
end

function network.step(force)
  local state = book(force)
  if not state then return end
  for _, p in ipairs(state.platforms) do
    if p.valid and p.scheduled_for_deletion == 0 then
      if p.hub and p.hub.valid then p.hub.destructible = false end
      for _, asteroid in pairs(p.surface.find_entities_filtered({ type = 'asteroid' })) do asteroid.destroy() end
      for _, tile in pairs(p.damaged_tiles) do p.repair_tile(tile.position) end
    end
  end
  for _, p in ipairs(state.shuttles) do
    if hub_of(p) then
      if not state.started[p.index] then
        local location = p.space_location
        if location and count(p.hub, spec.planet(location.name).item) >= spec.SHUTTLE_STOCK then
          state.started[p.index] = true
          p.paused = false
        end
      elseif not p.paused and not p.space_location then
        p.speed = 100
      end
    end
  end
  for id, pod in pairs(state.pods) do
    if not pod.entity.valid then state.pods[id] = nil end
  end
  for id, rocket in pairs(state.rockets) do
    if not rocket.valid then state.rockets[id] = nil end
  end
end

function network.on_launch(event)
  local silo = event.rocket_silo
  local state = silo.valid and book(silo.force)
  if not state then return end
  for _, cell in pairs(state.cells) do
    if cell.silo == silo then
      cell.launch_orders = cell.launch_orders + 1
      -- У rocket-silo-rocket в 2.1.24 нет unit_number, в отличие от cargo pod.
      state.rockets[silo.unit_number .. '/' .. event.tick] = event.rocket
      break
    end
  end
end

function network.on_departure(event)
  local pod = event.cargo_pod
  local state = pod.valid and book(pod.force)
  if not state or state.pods[pod.unit_number] then return end
  local origin = pod.cargo_pod_origin
  local destination = pod.cargo_pod_destination.station
  if not (origin and origin.valid and destination and destination.valid) then return end
  local kind, planet
  for name, cell in pairs(state.cells) do
    if origin == cell.silo then kind, planet = 'rocket', name end
    if destination == cell.pad then kind, planet = 'pad', name end
  end
  local owned_origin = false
  for _, p in ipairs(state.platforms) do
    if hub_of(p) == origin then owned_origin = true; break end
  end
  if kind == 'pad' and not owned_origin then return end
  if not kind and not owned_origin then return end
  if kind == 'rocket' then
    if destination ~= hub_of(state.depots[planet]) or not event.launched_by_rocket then return end
    state.cells[planet].launches = state.cells[planet].launches + 1
  end
  state.pods[pod.unit_number] = { entity = pod, kind = kind or 'transfer', planet = planet,
    destination = destination, items = pod.get_inventory(defines.inventory.cargo_unit).get_contents() }
end

function network.on_delivery(event)
  local pod = event.cargo_pod
  local state = pod.valid and book(pod.force)
  local sent = state and state.pods[pod.unit_number]
  if not sent then return end
  state.pods[pod.unit_number] = nil
  if not sent.planet or not sent.destination.valid then return end
  local cell = state.cells[sent.planet]
  for _, item in pairs(sent.items) do
    if sent.kind == 'rocket' and item.name == cell.item then
      cell.exported = cell.exported + item.count
    elseif sent.kind == 'pad' then
      cell.received = cell.received + item.count
      cell.delivered[item.name] = (cell.delivered[item.name] or 0) + item.count
    end
  end
end

function network.state(force) return book(force) end

function network.on_forces_merging(event)
  -- Индекс исходной силы сейчас ещё действителен. Не оставляем сцену без
  -- владельца после слияния и не передаём её бесконечные источники новой базе.
  network.clear(event.source)
end

function network.diagnostics(force)
  local state = book(force)
  local result = {}
  if not state then return result end
  local function enum(values, value)
    for key, number in pairs(values) do if number == value then return key end end
    return value
  end
  for name, cell in pairs(state.cells) do
    local logistics = cell.roboport.logistic_network
    result[name] = { status = enum(defines.entity_status, cell.silo.status), silo_status = enum(defines.rocket_silo_status, cell.silo.rocket_silo_status), frozen = cell.silo.frozen, energy = cell.silo.energy,
      parts = cell.silo.rocket_parts, crafted = cell.silo.products_finished,
      contents = cell.silo.get_inventory(defines.inventory.crafter_input).get_contents(),
      robots = logistics and logistics.all_logistic_robots or 0,
      provider = cell.provider.get_inventory(defines.inventory.chest).get_contents(),
      provider_network = cell.provider.logistic_network ~= nil, provider_frozen = cell.provider.frozen, roboport_energy = cell.roboport.energy,
      pad = cell.pad.get_inventory(defines.inventory.cargo_landing_pad_main).get_contents(),
      depot = state.depots[name].hub.get_inventory(defines.inventory.hub_main).get_contents() }
    result[name].inserters = {}
    for _, entity in ipairs(cell.entities) do
      if entity.type == 'inserter' then
        result[name].inserters[#result[name].inserters + 1] = { status = enum(defines.entity_status, entity.status), pickup = entity.pickup_position, drop = entity.drop_position,
          frozen = entity.frozen, energy = entity.energy }
      end
    end
    local rocket = cell.silo.rocket
    local pod = rocket and rocket.attached_cargo_pod
    result[name].rocket_cargo = pod and pod.get_inventory(defines.inventory.cargo_unit).get_contents()
    result[name].pads = {}
    for _, pad in pairs(cell.surface.find_entities_filtered({ type = 'cargo-landing-pad' })) do
      result[name].pads[#result[name].pads + 1] = { force = pad.force.name, position = pad.position,
        items = pad.get_inventory(defines.inventory.cargo_landing_pad_main).get_contents() }
    end
  end
  result.ships = {}
  for _, p in ipairs(state.shuttles) do
    result.ships[#result.ships + 1] = { name = p.name, state = enum(defines.space_platform_state, p.state), paused = p.paused, speed = p.speed, schedule = p.schedule,
      cargo = p.hub.get_inventory(defines.inventory.hub_main).get_contents(), sections = {} }
    for _, section in pairs(p.hub.get_logistic_sections().sections) do
      result.ships[#result.ships].sections[#result.ships[#result.ships].sections + 1] = { group = section.group, active = section.active }
    end
  end
  result.inflight = {}
  for _, sent in pairs(state.pods) do
    result.inflight[#result.inflight + 1] = { kind = sent.kind, planet = sent.planet, target = sent.destination.type,
      items = sent.items }
  end
  return result
end

function network.status(force)
  local state = book(force)
  if not state then return {} end
  local result = {}
  for _, planet in ipairs(spec.planets) do
    local cell = state.cells[planet.name]
    local depot = hub_of(state.depots[planet.name])
    result[#result + 1] = string.format('%s — площадка %d, %d; ракет %d, отправлено %d, принято %d; склад %d %s',
      planet.name, cell.position.x + 16, cell.position.y, cell.launches, cell.exported, cell.received,
      depot and count(depot, planet.item) or 0, planet.item)
  end
  for _, p in ipairs(state.shuttles) do
    if p.valid then
      result[#result + 1] = p.name .. ' — ' .. (p.space_location and p.space_location.name or 'в пути')
    end
  end
  return result
end

return network
