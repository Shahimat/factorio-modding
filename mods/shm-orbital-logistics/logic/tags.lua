-- Метка назначения в имени ванильной logistic group: `[reserve]`,
-- `[cargo→aquilo]`, `[depot:nauvis]`. Чистая логика без обращений к API игры,
-- правила — ТЗ, раздел 3.3.

local tags = {}

local ARROWS = { '→', '->' }

local function trim(text)
  return (string.gsub(text, '^%s*(.-)%s*$', '%1'))
end

--- Список имён через запятую в множество; пустой список — nil.
local function name_set(text)
  local set = nil
  for raw in string.gmatch(text, '[^,]+') do
    local name = trim(raw)
    if name ~= '' then
      set = set or {}
      set[name] = true
    end
  end
  return set
end

local function parse_cargo(body)
  if body == 'cargo' then
    return { kind = 'cargo' }
  end
  for _, arrow in ipairs(ARROWS) do
    local prefix = 'cargo' .. arrow
    if string.sub(body, 1, #prefix) == prefix then
      local dests = name_set(string.sub(body, #prefix + 1))
      if dests then
        return { kind = 'cargo', dests = dests }
      end
      return nil
    end
  end
  return nil
end

local function parse_depot(body)
  if body == 'depot' then
    return { kind = 'depot', anywhere = true }
  end
  local prefix = 'depot:'
  if string.sub(body, 1, #prefix) ~= prefix then
    return nil
  end
  local rest = trim(string.sub(body, #prefix + 1))
  if rest == '*' then
    return { kind = 'depot', anywhere = true }
  end
  local orbits = name_set(rest)
  if orbits then
    return { kind = 'depot', orbits = orbits }
  end
  return nil
end

--- Назначение по имени группы или nil, если метки нет. Первая узнанная метка
--- побеждает; чужие скобки вроде `[item=iron-plate]` пропускаются.
function tags.parse(group)
  if type(group) ~= 'string' or group == '' then
    return nil
  end
  for inner in string.gmatch(group, '%[([^%]]*)%]') do
    local body = string.lower(trim(inner))
    body = string.gsub(body, '%s+', '')
    local tag = nil
    if body == 'reserve' then
      tag = { kind = 'reserve' }
    elseif string.sub(body, 1, 5) == 'cargo' then
      tag = parse_cargo(body)
    elseif string.sub(body, 1, 5) == 'depot' then
      tag = parse_depot(body)
    end
    if tag then
      return tag
    end
  end
  return nil
end

--- Груз отдаётся на этой орбите: метка без «куда» — ваниль, всегда.
function tags.cargo_open_at(tag, location)
  return tag.dests == nil or (location ~= nil and tag.dests[location] == true)
end

--- Склад работает на этой орбите. В пути (`location == nil`) — нигде.
function tags.depot_active_at(tag, location)
  if location == nil then
    return false
  end
  return tag.anywhere == true or tag.orbits[location] == true
end

local function sorted(set)
  local list = {}
  for name in pairs(set or {}) do
    list[#list + 1] = name
  end
  table.sort(list)
  return list
end

--- Метка обратно в текст: `[reserve]`, `[cargo→a,b]`, `[depot:a]`, `[depot]`.
function tags.format(tag)
  if tag == nil then
    return nil
  end
  if tag.kind == 'reserve' then
    return '[reserve]'
  end
  if tag.kind == 'cargo' then
    if tag.dests == nil then
      return '[cargo]'
    end
    return '[cargo→' .. table.concat(sorted(tag.dests), ',') .. ']'
  end
  if tag.anywhere then
    return '[depot]'
  end
  return '[depot:' .. table.concat(sorted(tag.orbits), ',') .. ']'
end

--- Метка из выбора в панели: назначение и список мест через запятую. Пустой
--- список — груз «по запросу» или склад на любой орбите.
function tags.from_choice(kind, places)
  local set = name_set(string.lower(places or ''))
  if kind == 'reserve' then
    return { kind = 'reserve' }
  elseif kind == 'cargo' then
    return { kind = 'cargo', dests = set }
  elseif kind == 'depot' then
    if set == nil or set['*'] then
      return { kind = 'depot', anywhere = true }
    end
    return { kind = 'depot', orbits = set }
  end
  return nil
end

--- Места метки списком через запятую — для поля панели.
function tags.places(tag)
  if tag == nil then
    return ''
  end
  return table.concat(sorted(tag.dests or tag.orbits), ', ')
end

--- Имя группы без узнанных меток — чужие скобки и текст остаются.
function tags.strip(group)
  local result = string.gsub(group or '', '%s*(%[[^%]]*%])', function(bracket)
    if tags.parse(bracket) then
      return ''
    end
    return nil
  end)
  return trim(result)
end

--- Имя группы с новой меткой вместо старой; nil-метка — только снять.
function tags.retag(group, tag)
  local base = tags.strip(group)
  local text = tags.format(tag)
  if text == nil then
    return base
  end
  if base == '' then
    return text
  end
  return base .. ' ' .. text
end

return tags
