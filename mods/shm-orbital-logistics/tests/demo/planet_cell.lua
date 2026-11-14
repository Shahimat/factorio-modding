-- Настоящая планетарная логистика для dev-only демо. Принадлежность — по
-- сохранённым ссылкам, не по имени или координатам чужих сущностей.
local cell = {}

local NATURAL = { tree = true, ['simple-entity'] = true, resource = true, cliff = true, fish = true }

local function is_natural(entity)
  return entity.force.name == 'neutral' and NATURAL[entity.type]
    and not entity.prototype.has_flag('player-creation')
end

local function empty_site(surface)
  -- Отдельная сеть: не только пятно стройки, но и соседние робопорты не
  -- должны смешать бесконечные источники с логистикой существующей базы.
  for attempt = 0, 15 do
    local x, y = 512 + (attempt % 4) * 256, 512 + math.floor(attempt / 4) * 256
    surface.request_to_generate_chunks({ x, y }, 2)
    surface.force_generate_chunk_requests()
    local safe = true
    for _, entity in pairs(surface.find_entities_filtered({ area = { { x - 80, y - 80 }, { x + 80, y + 80 } } })) do
      if not is_natural(entity) then safe = false; break end
    end
    if safe then return { x = x, y = y } end
  end
  error('Не найден свободный участок для демо на ' .. surface.name .. '; существующие объекты не изменены')
end

local function ground(surface, origin, aquatic)
  local area = { { origin.x - 12, origin.y - 10 }, { origin.x + 23, origin.y + 20 } }
  for _, entity in pairs(surface.find_entities_filtered({ area = area })) do
    assert(is_natural(entity), 'Демо не удаляет существующие постройки')
    entity.destroy()
  end
  local base, concrete = {}, {}
  for x = origin.x - 12, origin.x + 22 do
    for y = origin.y - 10, origin.y + 19 do
      base[#base + 1] = { name = aquatic and 'ice-platform' or 'foundation', position = { x, y } }
      concrete[#concrete + 1] = { name = 'refined-concrete', position = { x, y } }
    end
  end
  -- Лёд Аквило требует покрытия: один ice-platform сохраняет meltable mask.
  surface.set_tiles(base, true, 'abort_on_collision', false, false)
  surface.set_tiles(concrete, true, 'abort_on_collision', false, false)
  return area
end

function cell.build(force, planet, entry)
  local location = assert(game.planets[planet.name])
  local surface = location.surface or location.create_surface()
  local origin = empty_site(surface)
  entry.surface, entry.position, entry.entities = surface, origin, {}
  local area = ground(surface, origin, planet.name == 'aquilo')

  local function create(name, x, y, direction)
    local options = { name = name, position = { origin.x + x, origin.y + y }, force = force, direction = direction }
    assert(surface.can_place_entity(options), 'Нет места для ' .. name .. ' на ' .. planet.name .. ' (' .. x .. ', ' .. y .. ')')
    local entity = assert(surface.create_entity(options))
    entry.entities[#entry.entities + 1] = entity
    entity.destructible = false
    entity.minable_flag = false
    return entity
  end

  local power = create('electric-energy-interface', 12, 14)
  power.electric_interface_mode = defines.electric_interface_mode.primary_output
  power.power_usage = 0
  create('substation', -8, 0)
  create('substation', 8, 0)
  create('substation', 8, 14)
  -- Без исследований скорости/ёмкости роботов особенно на Аквило важны
  -- короткие пути к зарядке, а не глобальные бонусы чужой силы.
  local roboport = create('roboport', 7, 4)
  roboport.get_inventory(defines.inventory.roboport_robot).insert({ name = 'logistic-robot', count = 100 })
  entry.roboport = roboport
  entry.roboports = { roboport }
  if planet.name == 'aquilo' then
    -- На холоде базовые роботы часто заряжаются. Добавляем физические
    -- зарядные места, не открывая исследования и не меняя бонусы силы.
    entry.roboports[#entry.roboports + 1] = create('roboport', 7, 9)
    entry.roboports[#entry.roboports + 1] = create('roboport', 1, 14)
  end

  local provider = create('infinity-chest', 5.5, 0.5)
  provider.override_logistic_mode = defines.logistic_mode.passive_provider
  provider.set_infinity_container_filter(1, { name = planet.item, count = 5000, mode = 'at-least' })
  entry.provider = provider

  local silo = create('rocket-silo', 0.5, 0.5)
  silo.use_transitional_requests = true
  silo.get_module_inventory().insert({ name = 'speed-module-3', count = 4 })
  -- Только первая ракета готова сразу. Все последующие строятся из реальных
  -- компонентов, которые приносят манипуляторы из бесконечных сундуков.
  silo.rocket_parts = silo.prototype.rocket_parts_required
  entry.silo = silo
  for index, item in ipairs({ 'processing-unit', 'low-density-structure', 'rocket-fuel' }) do
    local x = -1.5 + (index - 1) * 2
    local source = create('infinity-chest', x, -5.5)
    source.set_infinity_container_filter(1, { name = item, count = 200, mode = 'at-least' })
    create('bulk-inserter', x, -4.5, defines.direction.north)
  end

  local pad = create('cargo-landing-pad', 16, 0)
  entry.pad = pad
  entry.unloader = create('bulk-inserter', 16.5, 4.5, defines.direction.north)
  local sink = create('infinity-chest', 16.5, 5.5)
  sink.override_logistic_mode = defines.logistic_mode.none
  sink.remove_unfiltered_items = true
  entry.sink = sink

  if planet.name == 'fulgora' then create('lightning-collector', -8, 14) end
  if planet.name == 'aquilo' then
    local heater = create('heat-interface', -6.5, -7.5)
    heater.set_heat_setting({ temperature = 500, mode = 'at-least' })
    local occupied = {}
    local function heat(x, y)
      local key = x .. '/' .. y
      if not occupied[key] then
        local pipe = create('heat-pipe', x, y)
        pipe.temperature = 500
        occupied[key] = true
      end
    end
    for y = -6.5, 11.5 do heat(-6.5, y) end
    for x = -6.5, 3.5 do heat(x, -6.5) end
    for _, x in ipairs({ -2.5, -0.5, 1.5, 3.5 }) do heat(x, -5.5); heat(x, -4.5) end
    for x = -6.5, 4.5 do heat(x, 5.5) end
    for x = -6.5, 17.5 do heat(x, 11.5) end
    for y = 4.5, 11.5 do heat(17.5, y) end
    for y = 2.5, 11.5 do heat(9.5, y) end
    entry.heater = heater
  end

  force.chart(surface, area)
  entry.tag = force.add_chart_tag(surface, { position = pad.position, icon = { type = 'item', name = planet.item }, text = 'OL network — ' .. planet.name })
  return entry
end

function cell.clear(entry)
  if entry.tag and entry.tag.valid then entry.tag.destroy() end
  if entry.silo and entry.silo.valid then entry.silo.use_transitional_requests = false end
  -- Выпущенные роботы — тоже часть демо, но не роботы соседней базы.
  local seen = {}
  for _, port in ipairs(entry.roboports or {}) do
    local network = port.valid and port.logistic_network
    if network and not seen[network.network_id] then
      seen[network.network_id] = true
      local isolated = true
      for _, logistic_cell in pairs(network.cells) do
        local owned = false
        for _, own_port in ipairs(entry.roboports) do
          if logistic_cell.owner == own_port then owned = true; break end
        end
        if not owned then isolated = false; break end
      end
      -- Если игрок позже соединил сети, чужих роботов нельзя отличить от
      -- наших: оставляем их в живых, а не удаляем всю общую сеть.
      if isolated then
        for _, robot in pairs(network.logistic_robots) do
          if robot.valid then robot.destroy() end
        end
      end
    end
  end
  for _, entity in ipairs(entry.entities or {}) do
    if entity.valid then entity.destroy() end
  end
end

return cell
