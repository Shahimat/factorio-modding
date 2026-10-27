-- Своя секция мода на хабе: замки и транзит. Чистая логика — из решения
-- решателя в список фильтров и обратно, без обращений к API игры.

local own_section = {}

local ANY_QUALITY = '*'

--- Ключ предмета: имя и качество; `*` — любое качество.
function own_section.key(name, quality)
  return name .. '|' .. (quality or ANY_QUALITY)
end

function own_section.split(key)
  local name, quality = string.match(key, '^(.*)|([^|]*)$')
  if quality == ANY_QUALITY then
    quality = nil
  end
  return name, quality
end

local function sorted_keys(map)
  local keys = {}
  for key in pairs(map) do
    keys[#keys + 1] = key
  end
  table.sort(keys)
  return keys
end

--- Фильтры своей секции по решению: сначала замки, потом транзит, каждый
--- список по ключу, чтобы одинаковое решение давало одинаковую секцию.
--- Замок — `min = 0`, источник `all`, пустой `import_from`; транзит —
--- `min = 0` с платформ текущей орбиты: склад добирает с них до своей цели.
function own_section.filters(result, location)
  local filters = {}
  for _, key in ipairs(sorted_keys(result.locks)) do
    filters[#filters + 1] = { key = key, min = 0, request_from = 'all' }
  end
  if location then
    for _, key in ipairs(sorted_keys(result.transit)) do
      filters[#filters + 1] = {
        key = key,
        min = 0,
        request_from = 'platforms',
        import_from = location,
      }
    end
  end
  return filters
end

local function same_filter(a, b)
  return a.key == b.key and (a.min or 0) == (b.min or 0) and a.request_from == b.request_from
    and a.import_from == b.import_from
end

function own_section.same(current, desired)
  if #current ~= #desired then
    return false
  end
  for index, filter in ipairs(desired) do
    if not same_filter(current[index], filter) then
      return false
    end
  end
  return true
end

return own_section
