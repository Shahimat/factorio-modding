-- Линия снабжения: шапка из предметов и участники с ролями. Чистая часть —
-- какое имя группы и какие фильтры у каждого участника. Правила — ТЗ,
-- раздел 7: одна ванильная группа на сочетание роли и источников, потому что
-- `import_from` и `request_from` у группы общие для всех её участников.

local tags = require('logic.tags')

local lines = {}

lines.SEPARATOR = ' · '
lines.ROLES = { 'receive', 'depot', 'cargo', 'reserve' }
lines.SOURCES = { 'planet', 'platforms', 'all' }

--- Метка роли участника; у получателя метки нет — это обычный запрос.
function lines.tag_of(participant)
  if participant.role == 'receive' then
    return nil
  end
  return tags.from_choice(participant.role, participant.places)
end

function lines.prefix(line_name)
  return line_name .. lines.SEPARATOR
end

function lines.owns(line_name, group)
  local prefix = lines.prefix(line_name)
  return string.sub(group or '', 1, #prefix) == prefix
end

--- Имя группы участника: линия, откуда и с какого источника, метка роли.
--- Площадке источники не нужны — у неё одна группа на линию.
function lines.group_name(line_name, participant)
  if participant.kind == 'pad' then
    return lines.prefix(line_name) .. 'pad'
  end
  local name = lines.prefix(line_name) .. (participant.import_from or 'any') .. '/' .. (participant.request_from or 'planet')
  local text = tags.format(lines.tag_of(participant))
  if text then
    name = name .. ' ' .. text
  end
  return name
end

--- Фильтры группы участника по шапке линии. Пустые и нулевые строки шапки
--- пропускаются.
function lines.filters(line, participant)
  local filters = {}
  for _, item in ipairs(line.items) do
    if item.name and (item.count or 0) > 0 then
      local filter = { name = item.name, quality = item.quality or 'normal', min = item.count }
      if participant.kind ~= 'pad' then
        filter.import_from = participant.import_from
        filter.request_from = participant.request_from or 'planet'
      end
      filters[#filters + 1] = filter
    end
  end
  return filters
end

--- Множитель из текста поля: положительное число, иначе nil.
function lines.multiplier(text)
  local value = tonumber(text)
  if value == nil or value <= 0 then
    return nil
  end
  return value
end

return lines
