-- Контроллер: раз в проход снимает состояние всех хабов, решает решателем и
-- применяет решение ванильными средствами — своей секцией мода и `active`
-- секций груза на этом хабе. Секции игрока по полям фильтров не правит.

local tags = require('logic.tags')
local resolver = require('logic.resolver')
local own_section = require('logic.own_section')

local controller = {}

controller.SETTING = 'shm-orbital-logistics-enabled'

local function enabled()
  return settings.global[controller.SETTING].value == true
end

--- storage.platforms[index] = {
---   own = индекс служебной секции, written = её фильтры, как мод их записал,
---   service = true — служебная секция уже в своей группе (для миграции),
---   released = { [группа] = true } — секции груза, выключенные модом,
--- }
local function state_of(platform)
  storage.platforms = storage.platforms or {}
  local state = storage.platforms[platform.index]
  if not state then
    state = { released = {}, service = true }
    storage.platforms[platform.index] = state
  end
  return state
end

local function name_of(value)
  if value == nil then
    return nil
  end
  if type(value) == 'string' then
    return value
  end
  return value.name
end

--- Фильтры секции одним вызовом: `section.filters` дешевле, чем `get_slot`
--- по каждому слоту.
local function read_filters(section)
  local filters = {}
  for _, slot in pairs(section.filters) do
    local value = slot.value
    if value and value.name and (value.type == nil or value.type == 'item') then
      filters[#filters + 1] = {
        key = own_section.key(value.name, name_of(value.quality)),
        min = slot.min,
        request_from = slot.request_from,
        import_from = name_of(slot.import_from),
      }
    end
  end
  return filters
end

--- Через сколько проходов запись кеша перечитывается, даже если событий не
--- было: страховка на правки, о которых игра не сообщает.
local CACHE_PASSES = 10

--- Кеш фильтров в `storage`, чтобы в мультиплеере он был у всех одинаковым.
--- Чтение фильтров — самая дорогая часть прохода (замер V-10): секции с
--- группой делят фильтры, поэтому кешируются по имени группы, без группы — по
--- хабу и индексу. Сбрасывается событием правки слота и по сроку.
local function cache()
  storage.cache = storage.cache or { pass = 0, groups = {}, hubs = {} }
  return storage.cache
end

local function spread(seed)
  return seed % CACHE_PASSES
end

local function cached_filters(section, hub, index, group)
  local c = cache()
  local entry
  if group ~= '' then
    entry = c.groups[group]
  else
    local per_hub = c.hubs[hub.unit_number]
    entry = per_hub and per_hub[index]
    if entry and entry.count ~= section.filters_count then
      entry = nil
    end
  end
  if entry and entry.expires > c.pass then
    return entry.filters
  end
  local filters = read_filters(section)
  entry = {
    filters = filters,
    count = section.filters_count,
    expires = c.pass + CACHE_PASSES + spread(group ~= '' and #group or hub.unit_number + index),
  }
  if group ~= '' then
    c.groups[group] = entry
  else
    c.hubs[hub.unit_number] = c.hubs[hub.unit_number] or {}
    c.hubs[hub.unit_number][index] = entry
  end
  return filters
end

--- Правка слота: сбросить кеш этой секции, а у секции с группой — всей группы.
function controller.on_slot_changed(event)
  local section = event.section
  if not (section and section.valid) then
    return
  end
  local c = cache()
  local entity = event.entity
  local per_hub = entity and entity.valid and entity.unit_number and c.hubs[entity.unit_number]
  if per_hub then
    per_hub[section.index] = nil
  end
  if section.group ~= '' then
    c.groups[section.group] = nil
  end
end

local function count_into(map, entries)
  for _, entry in pairs(entries or {}) do
    local quality = name_of(entry.quality) or 'normal'
    local exact = own_section.key(entry.name, quality)
    local any = own_section.key(entry.name, nil)
    map[exact] = (map[exact] or 0) + entry.count
    map[any] = (map[any] or 0) + entry.count
  end
  return map
end

--- Служебная секция мода — в своей группе с уникальным на платформу именем:
--- в окне хаба она подписана, а не выглядит безымянной секцией с нулями, и
--- не становится общей с другими хабами. Имя — данные карты, а не текст
--- интерфейса, поэтому английское: в мультиплеере у игроков разные языки.
controller.SERVICE_PREFIX = '⚙ Orbital Logistics — auto #'

function controller.service_name(platform)
  return controller.SERVICE_PREFIX .. platform.index
end

function controller.is_service(group)
  local prefix = controller.SERVICE_PREFIX
  return group ~= nil and string.sub(group, 1, #prefix) == prefix
end

--- Своя секция — по имени служебной группы этой платформы.
local function find_own(sections, platform)
  local name = controller.service_name(platform)
  for index = 1, sections.sections_count do
    local section = sections.get_section(index)
    if section.is_manual and section.group == name then
      return section
    end
  end
  return nil
end

--- Убирает с хаба чужие служебные группы (назначенные игроком вручную) и
--- лишние копии своей: служебная группа принадлежит одной платформе.
local function drop_foreign(sections, platform)
  local mine = controller.service_name(platform)
  local seen = false
  for index = sections.sections_count, 1, -1 do
    local section = sections.get_section(index)
    if section.is_manual and controller.is_service(section.group) then
      if section.group ~= mine or seen then
        sections.remove_section(index)
      else
        seen = true
      end
    end
  end
end

local function delete_service_group(force, name)
  local group = force.get_logistic_group(name)
  if group and #group.members == 0 then
    force.delete_logistic_group(name)
  end
end

--- Разбор метки — чистая функция имени группы, поэтому запоминается: имён
--- групп немного, а разбирать их приходилось бы на каждом проходе.
local parsed = {}

local function tag_of(group)
  local tag = parsed[group]
  if tag == nil then
    tag = tags.parse(group) or false
    parsed[group] = tag
  end
  return tag or nil
end

--- Первая фаза снимка: только то, что дёшево, — орбита и группы секций.
local function survey(platform)
  local hub = platform.hub
  local sections = hub.get_logistic_sections()
  drop_foreign(sections, platform)
  local meta = {}
  local tagged = false
  local depots = {}
  for index = 1, sections.sections_count do
    local section = sections.get_section(index)
    if section.is_manual and not controller.is_service(section.group) then
      local group = section.group
      local tag = tag_of(group)
      meta[#meta + 1] = { index = index, group = group, tag = tag, section = section }
      if tag then
        tagged = true
        if tag.kind == 'depot' then
          depots[#depots + 1] = tag
        end
      end
    end
  end
  storage.platforms = storage.platforms or {}
  return {
    platform = platform,
    hub = hub,
    sections_object = sections,
    meta = meta,
    tagged = tagged,
    depots = depots,
    known = storage.platforms[platform.index] ~= nil,
    location = platform.space_location and platform.space_location.name or nil,
  }
end

--- Вторая фаза: фильтры, содержимое и «в пути» — только для хабов, которым
--- они нужны. Фильтры секций без метки читаются лишь на орбитах со складом:
--- там по ним ищется ванильный груз для транзита.
local function fill(snap, with_untagged)
  local state = state_of(snap.platform)
  local own = find_own(snap.sections_object, snap.platform)
  snap.state = state
  snap.own = own
  snap.sections = {}
  for _, entry in ipairs(snap.meta) do
    if not (own and own.index == entry.index) then
      local section = entry.section
      snap.sections[#snap.sections + 1] = {
        index = entry.index,
        group = entry.group,
        tag = entry.tag,
        -- Выключенная модом секция груза для решателя по-прежнему действует.
        active = section.active or (entry.group ~= '' and state.released[entry.group] == true),
        multiplier = section.multiplier,
        filters = (entry.tag or with_untagged) and cached_filters(section, snap.hub, entry.index, entry.group) or {},
      }
    end
  end
  snap.contents = count_into({}, snap.hub.get_inventory(defines.inventory.hub_main).get_contents())
  snap.incoming = {}
  if #snap.depots > 0 then
    local point = snap.hub.get_logistic_point(defines.logistic_member_index.space_platform_hub_requester)
    if point then
      count_into(snap.incoming, point.targeted_items_deliver)
    end
  end
end

--- Своя секция переписана — её запись в кеше устарела. Без этого мод на
--- следующем проходе не узнавал свою опустевшую секцию и заводил новую.
local function forget(hub, index)
  local per_hub = cache().hubs[hub.unit_number]
  if per_hub then
    per_hub[index] = nil
  end
end

local function write_own(snap, desired)
  local hub = snap.hub
  local sections = hub.get_logistic_sections()
  local state = snap.state
  local own = snap.own
  local name = controller.service_name(snap.platform)
  if #desired == 0 then
    -- Держать нечего — служебная группа уходит и с хаба, и из списка групп.
    if own then
      sections.remove_section(own.index)
      delete_service_group(hub.force, name)
    end
    state.own = nil
    state.written = nil
    return
  end
  if own and not own.active then
    own.active = true
  end
  if own and own_section.same(cached_filters(own, hub, own.index, own.group), desired) then
    return
  end
  if not own then
    own = sections.add_section(name)
    if not own then
      return
    end
  end
  state.own = own.index
  for slot_index = own.filters_count, 1, -1 do
    own.clear_slot(slot_index)
  end
  for slot_index, filter in ipairs(desired) do
    local item, quality = own_section.split(filter.key)
    own.set_slot(slot_index, {
      value = { type = 'item', name = item, quality = quality, comparator = quality and '=' or nil },
      min = filter.min,
      request_from = filter.request_from,
      import_from = filter.import_from,
    })
  end
  state.written = read_filters(own)
  cache().groups[name] = nil
end

--- Выключенные модом секции груза помнятся по имени группы, а не по номеру:
--- игрок может удалить или переставить секцию выше, и номер уедет. По номеру
--- мод тогда не находил свою выключенную секцию и не включал её обратно.
local function write_release(snap, release)
  local sections = snap.hub.get_logistic_sections()
  local released = snap.state.released
  local wanted = {}
  for index in pairs(release) do
    local section = sections.get_section(index)
    if section and section.group ~= '' then
      wanted[section.group] = true
    end
  end
  for group in pairs(released) do
    if not wanted[group] then
      for index = 1, sections.sections_count do
        local section = sections.get_section(index)
        if section.is_manual and section.group == group and not section.active then
          section.active = true
        end
      end
      released[group] = nil
    end
  end
  for group in pairs(wanted) do
    if not released[group] then
      released[group] = true
      for index = 1, sections.sections_count do
        local section = sections.get_section(index)
        if section.is_manual and section.group == group then
          section.active = false
        end
      end
    end
  end
end

--- Миграции сохранений прежних версий:
--- - выключенные секции помнились по номеру (`released[номер] = группа`) —
---   переводятся на имя группы;
--- - служебная секция была без группы и узнавалась по содержимому — такая
---   снимается, на следующем проходе мод заведёт её в служебной группе.
function controller.migrate()
  local by_index = {}
  for _, force in pairs(game.forces) do
    for _, platform in pairs(force.platforms) do
      by_index[platform.index] = platform
    end
  end
  for index, state in pairs(storage.platforms or {}) do
    local platform = by_index[index]
    if state.own and state.written and not state.service and platform and platform.valid and platform.hub and platform.hub.valid then
      local sections = platform.hub.get_logistic_sections()
      local section = sections.get_section(state.own)
      if section and section.is_manual and section.group == '' and own_section.same(read_filters(section), state.written) then
        sections.remove_section(state.own)
      end
      state.own = nil
      state.written = nil
    end
    state.service = true
  end
  for _, state in pairs(storage.platforms or {}) do
    local converted = {}
    for key, value in pairs(state.released or {}) do
      if type(key) == 'number' then
        converted[value] = true
      else
        converted[key] = value
      end
    end
    state.released = converted
  end
end

local function platforms()
  local list = {}
  for _, force in pairs(game.forces) do
    for _, platform in pairs(force.platforms) do
      if platform.valid and platform.hub and platform.hub.valid and platform.scheduled_for_deletion == 0 then
        list[#list + 1] = platform
      end
    end
  end
  return list
end

--- Порций прохода: раз в `SLICE_TICKS` обрабатывается одна, полный круг —
--- раз в секунду. Замер V-10: полный проход по 40 платформам с 4×40
--- фильтрами стоит ~4 мс, порция — шестую часть.
controller.SLICES = 6
controller.SLICE_TICKS = 10

local function where_of(platform, location)
  return platform.force.name .. '/' .. location
end

--- Последнее известное по хабу, нужное соседям по орбите:
--- storage.orbit[индекс платформы] = { where, offered = { [key] = true }, depot = bool }.
local function orbit_state()
  storage.orbit = storage.orbit or {}
  return storage.orbit
end

local function depot_here(snap)
  if not snap.location then
    return false
  end
  for _, tag in ipairs(snap.depots) do
    if tags.depot_active_at(tag, snap.location) then
      return true
    end
  end
  return false
end

--- Обрабатывает переданные платформы. Соседей по орбите, не попавших в
--- список, видит по их последнему известному состоянию.
local function process(list)
  if not enabled() then
    return
  end
  local c = cache()
  c.pass = c.pass + 1
  local orbit = orbit_state()

  local surveyed = {}
  for _, platform in ipairs(list) do
    local snap = survey(platform)
    surveyed[#surveyed + 1] = snap
    local known = orbit[platform.index]
    local here = snap.location and where_of(platform, snap.location) or nil
    if known and known.where ~= here then
      known.offered = {}
    end
    orbit[platform.index] = orbit[platform.index] or { offered = {} }
    orbit[platform.index].where = here
    orbit[platform.index].depot = depot_here(snap)
  end

  local depot_orbits = {}
  for _, entry in pairs(orbit) do
    if entry.where and entry.depot then
      depot_orbits[entry.where] = true
    end
  end

  local snaps = {}
  for _, snap in ipairs(surveyed) do
    local here = orbit[snap.platform.index].where
    local at_depot = here ~= nil and depot_orbits[here] == true
    if snap.tagged or snap.known or at_depot then
      fill(snap, at_depot)
      snap.offered = resolver.cargo_offered(snap)
      snaps[#snaps + 1] = snap
    else
      snap.offered = {}
    end
    orbit[snap.platform.index].offered = snap.offered
  end

  for _, snap in ipairs(snaps) do
    local here = orbit[snap.platform.index].where
    local cargo_here = {}
    if here then
      for index, entry in pairs(orbit) do
        if index ~= snap.platform.index and entry.where == here then
          for key in pairs(entry.offered) do
            cargo_here[key] = true
          end
        end
      end
    end
    local result = resolver.resolve(snap, cargo_here)
    write_release(snap, result.release)
    write_own(snap, own_section.filters(result, snap.location))
    -- След мода не нужен хабу, где мод ничего не держит: иначе он читался бы
    -- целиком на каждом проходе.
    if snap.state.own == nil and next(snap.state.released) == nil then
      storage.platforms[snap.platform.index] = nil
    end
  end
end

--- Полный проход по всем хабам всех сил: для тестов, `remote` и смены
--- настройки.
function controller.pass()
  local list = platforms()
  local alive = {}
  for _, platform in ipairs(list) do
    alive[platform.index] = true
  end
  for index in pairs(orbit_state()) do
    if not alive[index] then
      storage.orbit[index] = nil
    end
  end
  process(list)
end

--- Очередная порция: платформы с индексом, дающим нужный остаток.
function controller.slice(event)
  local slice = math.floor(event.tick / controller.SLICE_TICKS) % controller.SLICES
  local list = {}
  for _, platform in ipairs(platforms()) do
    if platform.index % controller.SLICES == slice then
      list[#list + 1] = platform
    end
  end
  if slice == 0 then
    local alive = {}
    for _, platform in ipairs(platforms()) do
      alive[platform.index] = true
    end
    for index in pairs(orbit_state()) do
      if not alive[index] then
        storage.orbit[index] = nil
      end
    end
  end
  if #list > 0 then
    process(list)
  end
end

--- Смена состояния одной платформы — прилёт, отлёт: обработать только её.
function controller.on_platform_changed(event)
  local platform = event.platform
  if platform and platform.valid and platform.hub and platform.hub.valid and platform.scheduled_for_deletion == 0 then
    process({ platform })
  end
end

--- Снимает всё, что мод поставил на хабы: свои секции и выключения секций
--- груза. Вызывается выключением настройки — путь перед удалением мода.
function controller.release_all()
  for _, platform in ipairs(platforms()) do
    local state = state_of(platform)
    local sections = platform.hub.get_logistic_sections()
    write_release({ hub = platform.hub, state = state }, {})
    for index = sections.sections_count, 1, -1 do
      local section = sections.get_section(index)
      if section.is_manual and controller.is_service(section.group) then
        sections.remove_section(index)
      end
    end
  end
  for _, force in pairs(game.forces) do
    for _, group in pairs(force.get_logistic_groups()) do
      if controller.is_service(group) then
        force.delete_logistic_group(group)
      end
    end
  end
  storage.platforms = {}
  storage.cache = nil
  storage.orbit = nil
end

return controller
