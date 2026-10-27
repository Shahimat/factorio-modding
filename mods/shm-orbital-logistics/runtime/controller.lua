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
---   own = индекс своей секции, written = её фильтры, как мод их записал,
---   released = { [индекс] = группа } — секции груза, выключенные модом,
--- }
local function state_of(platform)
  storage.platforms = storage.platforms or {}
  local state = storage.platforms[platform.index]
  if not state then
    state = { released = {} }
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

local function read_filters(section)
  local filters = {}
  for slot_index = 1, section.filters_count do
    local slot = section.get_slot(slot_index)
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

--- Своя секция: та, где лежит ровно записанное модом в прошлый раз, — по
--- сохранённому индексу, а если игрок сдвинул секции, поиском. По виду
--- фильтров её не угадываем: запрос игрока с платформ выглядит как транзит.
local function find_own(sections, state)
  local written = state.written
  if written == nil then
    return nil
  end
  local function fits(section)
    return section and section.is_manual and section.group == '' and own_section.same(read_filters(section), written)
  end
  if state.own then
    local section = sections.get_section(state.own)
    if fits(section) then
      return section
    end
  end
  state.own = nil
  if #written == 0 then
    state.written = nil
    return nil
  end
  for index = 1, sections.sections_count do
    local section = sections.get_section(index)
    if fits(section) then
      state.own = index
      return section
    end
  end
  state.written = nil
  return nil
end

local function snapshot(platform)
  local hub = platform.hub
  local state = state_of(platform)
  local sections = hub.get_logistic_sections()
  local own = find_own(sections, state)
  local snap = {
    platform = platform,
    hub = hub,
    state = state,
    own = own,
    location = platform.space_location and platform.space_location.name or nil,
    sections = {},
    contents = count_into({}, hub.get_inventory(defines.inventory.hub_main).get_contents()),
    incoming = {},
  }
  local point = hub.get_logistic_point(defines.logistic_member_index.space_platform_hub_requester)
  if point then
    count_into(snap.incoming, point.targeted_items_deliver)
  end
  for index = 1, sections.sections_count do
    local section = sections.get_section(index)
    if section.is_manual and not (own and own.index == index) then
      snap.sections[#snap.sections + 1] = {
        index = index,
        group = section.group,
        tag = tags.parse(section.group),
        -- Выключенная модом секция груза для решателя по-прежнему действует.
        active = section.active or state.released[index] == section.group,
        multiplier = section.multiplier,
        filters = read_filters(section),
      }
    end
  end
  return snap
end

local function write_own(snap, desired)
  local hub = snap.hub
  local sections = hub.get_logistic_sections()
  local state = snap.state
  local own = snap.own
  if #desired == 0 then
    if own and next(state.released) == nil then
      sections.remove_section(own.index)
      state.own = nil
      state.written = nil
    elseif own then
      for slot_index = own.filters_count, 1, -1 do
        own.clear_slot(slot_index)
      end
      state.written = {}
    end
    return
  end
  if own and not own.active then
    own.active = true
  end
  if own and own_section.same(read_filters(own), desired) then
    return
  end
  if not own then
    own = sections.add_section()
    if not own then
      return
    end
    state.own = own.index
  end
  for slot_index = own.filters_count, 1, -1 do
    own.clear_slot(slot_index)
  end
  for slot_index, filter in ipairs(desired) do
    local name, quality = own_section.split(filter.key)
    own.set_slot(slot_index, {
      value = { type = 'item', name = name, quality = quality, comparator = quality and '=' or nil },
      min = filter.min,
      request_from = filter.request_from,
      import_from = filter.import_from,
    })
  end
  state.written = read_filters(own)
end

local function write_release(snap, release)
  local sections = snap.hub.get_logistic_sections()
  local released = snap.state.released
  for index, group in pairs(released) do
    if not release[index] then
      local section = sections.get_section(index)
      if section and section.group == group then
        section.active = true
      end
      released[index] = nil
    end
  end
  for index in pairs(release) do
    local section = sections.get_section(index)
    if section and released[index] == nil then
      released[index] = section.group
      section.active = false
    end
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

--- Один проход по всем хабам всех сил.
function controller.pass()
  if not enabled() then
    return
  end
  local snaps = {}
  local offered = {}
  for _, platform in ipairs(platforms()) do
    local snap = snapshot(platform)
    snap.offered = resolver.cargo_offered(snap)
    snaps[#snaps + 1] = snap
    if snap.location then
      local where = platform.force.name .. '/' .. snap.location
      offered[where] = offered[where] or {}
      for key in pairs(snap.offered) do
        offered[where][key] = (offered[where][key] or 0) + 1
      end
    end
  end
  for _, snap in ipairs(snaps) do
    local cargo_here = {}
    if snap.location then
      for key, count in pairs(offered[snap.platform.force.name .. '/' .. snap.location] or {}) do
        if count - (snap.offered[key] and 1 or 0) > 0 then
          cargo_here[key] = true
        end
      end
    end
    local result = resolver.resolve(snap, cargo_here)
    write_release(snap, result.release)
    write_own(snap, own_section.filters(result, snap.location))
  end
end

--- Снимает всё, что мод поставил на хабы: свои секции и выключения секций
--- груза. Вызывается выключением настройки — путь перед удалением мода.
function controller.release_all()
  for _, platform in ipairs(platforms()) do
    local state = state_of(platform)
    local sections = platform.hub.get_logistic_sections()
    write_release({ hub = platform.hub, state = state }, {})
    local own = find_own(sections, state)
    if own then
      sections.remove_section(own.index)
    end
  end
  storage.platforms = {}
end

return controller
