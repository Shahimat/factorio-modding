-- Живая демо-сцена: челноки «летают» по маршрутам — сцена переставляет их на
-- следующую остановку по таймеру, а источники и стоки скриптом заменяют
-- ракеты с планеты и потребление. Процесс непрерывный, ход виден в чате и в
-- содержимом хабов. Платформы — `OLL-`, группы — `OL live`.

local live = {}

local PREFIX = 'OLL-'
local PERIOD = 60
local STOP_TICKS = 40 * 60
local PLATE = 'iron-plate'
local HOLMIUM = 'holmium-plate'

local PLANET_NAMES = { nauvis = 'Наувис', vulcanus = 'Вулкан', fulgora = 'Фульгора', aquilo = 'Аквило', gleba = 'Глеба' }

--- name, planet, items, providing, sections, route — остановки челнока по кругу,
--- source = { item, target, at } — пополнять до target (только на орбите `at`, если задана),
--- sink = { item, amount } — расходовать amount раз в 10 с. Расход меньше
--- подвоза (плиты 400 против 800 за круг в 160 с, гольмий 160 против 400 за
--- 80 с), иначе потребитель съедает всё и склады видно пустыми.
local PLATFORMS = {
  {
    name = 'OLL-1 Склад плит Наувис [depot:nauvis]',
    planet = 'nauvis', items = { [PLATE] = 2000 }, providing = true,
    sections = { { group = 'OL live plates [depot:nauvis]', item = PLATE, min = 2000, from = 'planet', import_from = 'nauvis' } },
    source = { item = PLATE, target = 2000 },
  },
  {
    name = 'OLL-2 Челнок плит Наувис → Вулкан → Аквило',
    planet = 'nauvis', providing = true,
    sections = { { group = 'OL live plates [cargo→aquilo]', item = PLATE, min = 800, from = 'platforms', import_from = 'nauvis' } },
    route = { 'nauvis', 'vulcanus', 'aquilo', 'vulcanus' },
  },
  {
    name = 'OLL-3 Потребитель плит Вулкан — не получает',
    planet = 'vulcanus',
    sections = { { item = PLATE, min = 300, from = 'platforms', import_from = 'vulcanus' } },
  },
  {
    name = 'OLL-4 Склад плит Аквило [depot:aquilo]',
    planet = 'aquilo', providing = true,
    sections = { { group = 'OL live plates [depot:aquilo]', item = PLATE, min = 1000, from = 'planet', import_from = 'aquilo' } },
  },
  {
    name = 'OLL-5 Потребитель плит Аквило',
    planet = 'aquilo',
    sections = { { item = PLATE, min = 300, from = 'platforms', import_from = 'aquilo' } },
    sink = { item = PLATE, amount = 25 },
  },
  {
    name = 'OLL-6 Челнок гольмия Фульгора → Наувис',
    planet = 'fulgora', items = { [HOLMIUM] = 400 }, providing = true,
    sections = { { group = 'OL live holmium [cargo→nauvis]', item = HOLMIUM, min = 400, from = 'planet', import_from = 'fulgora' } },
    route = { 'fulgora', 'nauvis' },
    source = { item = HOLMIUM, target = 400, at = 'fulgora' },
  },
  {
    name = 'OLL-7 Склад гольмия Наувис [depot:nauvis]',
    planet = 'nauvis', providing = true,
    sections = { { group = 'OL live holmium [depot:nauvis]', item = HOLMIUM, min = 500, from = 'planet', import_from = 'nauvis' } },
  },
  {
    name = 'OLL-8 Потребитель гольмия Наувис',
    planet = 'nauvis',
    sections = { { item = HOLMIUM, min = 200, from = 'platforms', import_from = 'nauvis' } },
    sink = { item = HOLMIUM, amount = 20 },
  },
}

local LEGEND = {
  'Orbital Logistics live: платформы OLL-1…OLL-8, раз в 40 с челноки перелетают на следующую остановку.',
  'Плиты: склад OLL-1 над Наувисом пополняется сам (как ракетами) → челнок OLL-2 грузит 800 →',
  '  над Вулканом груз держит (OLL-3 ничего не получает) → над Аквило сдаёт складу OLL-4 → потребитель OLL-5 расходует.',
  'Гольмий: челнок OLL-6 набирает над Фульгорой → над Наувисом сдаёт складу OLL-7 (транзит) → потребитель OLL-8 расходует.',
  '/shm-orbital-demo status — содержимое хабов, /shm-orbital-demo clear — убрать.',
}

local function state()
  storage.shm_live = storage.shm_live or { next_move = 0 }
  return storage.shm_live
end

local function by_name(force)
  local found = {}
  for _, platform in pairs(force.platforms) do
    if platform.valid and string.sub(platform.name, 1, #PREFIX) == PREFIX and platform.scheduled_for_deletion == 0 then
      found[platform.name] = platform
    end
  end
  return found
end

local function pass()
  if remote.interfaces['shm-orbital-logistics'] then
    remote.call('shm-orbital-logistics', 'pass')
  end
end

--- Удалённая платформа исчезает не сразу и до того ещё запрашивает и
--- отдаёт, поэтому перед удалением хаб обнуляется.
local function retire(platform)
  local hub = platform.hub
  if hub and hub.valid then
    hub.providing_to_other_platforms = false
    local sections = hub.get_logistic_sections()
    for index = sections.sections_count, 1, -1 do
      if sections.get_section(index).is_manual then
        sections.remove_section(index)
      end
    end
    hub.get_inventory(defines.inventory.hub_main).clear()
    hub.get_inventory(defines.inventory.hub_trash).clear()
  end
  platform.destroy()
end

function live.clear(force)
  local removed = 0
  for _, platform in pairs(by_name(force)) do
    retire(platform)
    removed = removed + 1
  end
  storage.shm_live = nil
  return removed
end

function live.build(force, tick)
  live.clear(force)
  for _, spec in ipairs(PLATFORMS) do
    local platform = force.create_space_platform({
      name = spec.name,
      planet = spec.planet,
      starter_pack = 'space-platform-starter-pack',
    })
    if platform then
      platform.apply_starter_pack()
      local hub = platform.hub
      hub.request_missing_construction_materials = false
      hub.providing_to_other_platforms = spec.providing == true
      for item, count in pairs(spec.items or {}) do
        hub.insert({ name = item, count = count })
      end
      for _, section_spec in ipairs(spec.sections) do
        local section = hub.get_logistic_sections().add_section(section_spec.group)
        section.set_slot(1, {
          value = { type = 'item', name = section_spec.item, quality = 'normal', comparator = '=' },
          min = section_spec.min,
          request_from = section_spec.from,
          import_from = section_spec.import_from,
        })
      end
    end
  end
  local s = state()
  s.next_move = tick + STOP_TICKS
  s.stop = {}
  pass()
  return LEGEND
end

local function location_of(platform)
  return platform.space_location and platform.space_location.name or nil
end

--- Один шаг сцены, раз в PERIOD тиков: источники, стоки и перелёты.
--- Возвращает строки для чата о перелётах.
function live.step(force, tick)
  local s = storage.shm_live
  if not s then
    return {}
  end
  local found = by_name(force)
  local lines = {}
  for _, spec in ipairs(PLATFORMS) do
    local platform = found[spec.name]
    if platform and platform.hub and platform.hub.valid then
      local hub = platform.hub
      local inventory = hub.get_inventory(defines.inventory.hub_main)
      if spec.source and (spec.source.at == nil or location_of(platform) == spec.source.at) then
        local missing = spec.source.target - inventory.get_item_count(spec.source.item)
        if missing > 0 then
          inventory.insert({ name = spec.source.item, count = missing })
        end
      end
      if spec.sink and tick % (10 * 60) < PERIOD then
        local have = inventory.get_item_count(spec.sink.item)
        if have > 0 then
          inventory.remove({ name = spec.sink.item, count = math.min(have, spec.sink.amount) })
        end
      end
    end
  end
  if tick >= s.next_move then
    s.next_move = tick + STOP_TICKS
    for _, spec in ipairs(PLATFORMS) do
      local platform = found[spec.name]
      if spec.route and platform then
        local index = (s.stop[spec.name] or 1) % #spec.route + 1
        s.stop[spec.name] = index
        local planet = spec.route[index]
        platform.space_location = planet
        lines[#lines + 1] = string.format('%s прилетел: %s, плит %d, гольмия %d', spec.name, PLANET_NAMES[planet] or planet,
          platform.hub.get_inventory(defines.inventory.hub_main).get_item_count(PLATE),
          platform.hub.get_inventory(defines.inventory.hub_main).get_item_count(HOLMIUM))
      end
    end
    pass()
  end
  return lines
end

function live.status(force)
  local found = by_name(force)
  local lines = {}
  for _, spec in ipairs(PLATFORMS) do
    local platform = found[spec.name]
    if platform and platform.hub and platform.hub.valid then
      local inventory = platform.hub.get_inventory(defines.inventory.hub_main)
      local where = location_of(platform)
      lines[#lines + 1] = string.format('%s — %s: плит %d, гольмия %d', spec.name, PLANET_NAMES[where] or where or 'в пути',
        inventory.get_item_count(PLATE), inventory.get_item_count(HOLMIUM))
    end
  end
  return lines
end

--- Демо-платформы без турелей, а на орбитах вроде Аквило их бьют астероиды:
--- хаб неуязвим, астероиды у платформы убираются, фундамент чинится. Касается
--- обеих сцен — и `OL-`, и `OLL-`.
function live.shield(force)
  for _, platform in pairs(force.platforms) do
    local demo = string.sub(platform.name, 1, 3) == 'OL-' or string.sub(platform.name, 1, #PREFIX) == PREFIX
    if platform.valid and demo and platform.scheduled_for_deletion == 0 then
      if platform.hub and platform.hub.valid then
        platform.hub.destructible = false
      end
      local surface = platform.surface
      if surface then
        for _, asteroid in pairs(surface.find_entities_filtered({ type = 'asteroid' })) do
          asteroid.destroy()
        end
      end
      for _, tile in pairs(platform.damaged_tiles) do
        platform.repair_tile(tile.position)
      end
    end
  end
end

live.PERIOD = PERIOD
live.STOP_TICKS = STOP_TICKS

return live
