-- Линии снабжения в игре: хранение, участники и синхронизация ванильных групп.
-- Линия — мастер-запись; по ней мод держит группу на каждое сочетание роли и
-- источников, подключает её секцией к участникам с их множителем и пишет в
-- неё фильтры шапки. Одна запись в секцию группы расходится по всем её
-- участникам — это ванильная механика групп.

local logic = require('logic.lines')

local lines = {}

--- storage.lines[индекс силы] = { next_id, by_id = { [id] = линия } }
--- линия = { id, name, items = { { name, quality, count } },
---   participants = { { entity, kind = 'hub' | 'pad', role, places, import_from, request_from, multiplier } } }
local function book(force)
  storage.lines = storage.lines or {}
  local entry = storage.lines[force.index]
  if not entry then
    entry = { next_id = 1, by_id = {} }
    storage.lines[force.index] = entry
  end
  return entry
end

function lines.list(force)
  local list = {}
  for _, line in pairs(book(force).by_id) do
    list[#list + 1] = line
  end
  table.sort(list, function(a, b)
    return a.id < b.id
  end)
  return list
end

function lines.get(force, id)
  return book(force).by_id[id]
end

local function name_taken(force, name, except)
  for _, line in pairs(book(force).by_id) do
    if line.name == name and line ~= except then
      return true
    end
  end
  return false
end

local function valid_name(name)
  return name ~= nil and name ~= '' and not string.find(name, logic.SEPARATOR, 1, true)
end

function lines.create(force, name)
  name = name and string.gsub(name, '^%s*(.-)%s*$', '%1') or ''
  if not valid_name(name) then
    return nil, 'bad-name'
  end
  if name_taken(force, name) then
    return nil, 'name-taken'
  end
  local entry = book(force)
  local line = { id = entry.next_id, name = name, items = {}, participants = {} }
  entry.by_id[line.id] = line
  entry.next_id = entry.next_id + 1
  return line
end

local function sections_of(entity)
  return entity and entity.valid and entity.get_logistic_sections() or nil
end

--- Снимает с сущности все секции этой линии, кроме `keep`.
local function strip(entity, line_name, keep)
  local sections = sections_of(entity)
  if not sections then
    return
  end
  for index = sections.sections_count, 1, -1 do
    local section = sections.get_section(index)
    if section.is_manual and logic.owns(line_name, section.group) and section.group ~= keep then
      sections.remove_section(index)
    end
  end
end

local function delete_groups(force, line_name, keep)
  for _, group in pairs(force.get_logistic_groups()) do
    if logic.owns(line_name, group) and not (keep and keep[group]) then
      force.delete_logistic_group(group)
    end
  end
end

function lines.delete(force, line)
  for _, participant in ipairs(line.participants) do
    strip(participant.entity, line.name)
  end
  delete_groups(force, line.name)
  book(force).by_id[line.id] = nil
end

function lines.rename(force, line, name)
  name = name and string.gsub(name, '^%s*(.-)%s*$', '%1') or ''
  if not valid_name(name) then
    return false, 'bad-name'
  end
  if name_taken(force, name, line) then
    return false, 'name-taken'
  end
  for _, participant in ipairs(line.participants) do
    strip(participant.entity, line.name)
  end
  delete_groups(force, line.name)
  line.name = name
  lines.sync(force, line)
  return true
end

--- Участник по умолчанию: хаб — получатель с платформ своей орбиты, площадка —
--- получатель на планете. Роль и источники меняются в окне линий.
function lines.attach(force, line, entity)
  for _, participant in ipairs(line.participants) do
    if participant.entity == entity then
      return participant
    end
  end
  local participant
  if entity.type == 'cargo-landing-pad' then
    participant = { entity = entity, kind = 'pad', role = 'receive', places = '', multiplier = 1 }
  else
    local platform = entity.surface.platform
    local location = platform and platform.space_location and platform.space_location.name or nil
    participant = {
      entity = entity,
      kind = 'hub',
      role = 'receive',
      places = '',
      import_from = location,
      request_from = 'platforms',
      multiplier = 1,
    }
  end
  line.participants[#line.participants + 1] = participant
  lines.sync(force, line)
  return participant
end

function lines.detach(force, line, index)
  local participant = line.participants[index]
  if not participant then
    return
  end
  strip(participant.entity, line.name)
  table.remove(line.participants, index)
  lines.sync(force, line)
end

local function write_filters(section, filters)
  for slot = section.filters_count, 1, -1 do
    section.clear_slot(slot)
  end
  for slot, filter in ipairs(filters) do
    section.set_slot(slot, {
      value = { type = 'item', name = filter.name, quality = filter.quality, comparator = '=' },
      min = filter.min,
      import_from = filter.import_from,
      request_from = filter.request_from,
    })
  end
end

--- Приводит ванильные группы и секции участников к линии: у каждого участника
--- ровно одна секция линии с нужной группой и множителем, в каждой группе —
--- фильтры шапки, лишние группы линии удалены. Пропавшие сущности выбывают.
function lines.sync(force, line)
  local alive = {}
  for _, participant in ipairs(line.participants) do
    if participant.entity and participant.entity.valid then
      alive[#alive + 1] = participant
    end
  end
  line.participants = alive

  local written = {}
  for _, participant in ipairs(line.participants) do
    local name = logic.group_name(line.name, participant)
    strip(participant.entity, line.name, name)
    local sections = sections_of(participant.entity)
    local section = nil
    for index = 1, sections.sections_count do
      local candidate = sections.get_section(index)
      if candidate.is_manual and candidate.group == name then
        section = candidate
        break
      end
    end
    if not section then
      section = sections.add_section(name)
    end
    if section then
      section.multiplier = participant.multiplier or 1
      if not written[name] then
        write_filters(section, logic.filters(line, participant))
        written[name] = true
      end
    end
  end
  delete_groups(force, line.name, written)
end

--- Линии, где участвует сущность, — для панели у её окна.
function lines.of_entity(force, entity)
  local found = {}
  for _, line in ipairs(lines.list(force)) do
    for index, participant in ipairs(line.participants) do
      if participant.entity == entity then
        found[#found + 1] = { line = line, index = index }
      end
    end
  end
  return found
end

return lines
