-- Семья превосходных манипуляторов K2 и их варианты без ожидания полной
-- руки.
--
-- Ожидание полной руки задаётся только в прототипе, поэтому режим
-- конкретного манипулятора — это выбор одного из двух прототипов: исходный
-- K2 (ждёт полную руку, режим по умолчанию) и скрытая копия `-instant`
-- (выкладывает сразу, как K2 без мода).
--
-- Чистый модуль: работает с любой таблицей той же формы, что `data.raw`, и
-- к глобальным `data` / `game` / `prototypes` не обращается — поэтому покрыт
-- Lua-тестами.

local variants = {}

variants.FAMILY = { 'kr-superior-inserter', 'kr-superior-long-inserter' }

local INSTANT_PREFIX = 'shm-'
local INSTANT_SUFFIX = '-instant'

local base_by_name = {}
for _, base in ipairs(variants.FAMILY) do
  base_by_name[base] = base
  base_by_name[INSTANT_PREFIX .. base .. INSTANT_SUFFIX] = base
end

--- Имя варианта «Сразу» для исходного прототипа семьи.
function variants.instant_name(base)
  return INSTANT_PREFIX .. base .. INSTANT_SUFFIX
end

--- Имя исходного прототипа семьи для любого из двух вариантов; nil, если
--- имя не из семьи.
function variants.base_name(name)
  return base_by_name[name]
end

function variants.is_family(name)
  return base_by_name[name] ~= nil
end

--- Ждёт ли вариант полную руку. Для имени не из семьи — nil.
function variants.is_waiting(name)
  local base = base_by_name[name]
  if base == nil then
    return nil
  end
  return name == base
end

--- Имя прототипа противоположного режима; nil для имени не из семьи.
function variants.toggled(name)
  local base = base_by_name[name]
  if base == nil then
    return nil
  end
  if name == base then
    return variants.instant_name(base)
  end
  return base
end

--- Имя прототипа нужного режима в семье `name`; nil для имени не из семьи.
function variants.with_mode(name, waiting)
  local base = base_by_name[name]
  if base == nil then
    return nil
  end
  return waiting and base or variants.instant_name(base)
end

--- Все имена обоих вариантов, в порядке семьи.
function variants.all_names()
  local names = {}
  for _, base in ipairs(variants.FAMILY) do
    names[#names + 1] = base
    names[#names + 1] = variants.instant_name(base)
  end
  return names
end

local function deepcopy(value)
  if type(value) ~= 'table' then
    return value
  end
  local copy = {}
  for k, v in pairs(value) do
    copy[deepcopy(k)] = deepcopy(v)
  end
  return copy
end

local function set_waiting(prototype, waiting)
  prototype.wait_for_full_hand = waiting
  prototype.grab_less_to_match_belt_stack = waiting
  prototype.enter_drop_mode_if_held_stack_spoiled = waiting
end

--- Предмет, которым ставится прототип: `placeable_by` или результат
--- разборки. nil, если ни того, ни другого нет.
local function placing_item(prototype)
  if prototype.placeable_by ~= nil then
    return deepcopy(prototype.placeable_by)
  end
  local minable = prototype.minable
  if minable == nil then
    return nil
  end
  if minable.result ~= nil then
    return { item = minable.result, count = 1 }
  end
  local first = minable.results and minable.results[1]
  if first ~= nil and first.name ~= nil then
    return { item = first.name, count = 1 }
  end
  return nil
end

--- Копия исходного прототипа без ожидания полной руки.
function variants.make_instant(base)
  local copy = deepcopy(base)
  copy.name = variants.instant_name(base.name)
  set_waiting(copy, false)
  copy.placeable_by = placing_item(base)
  copy.localised_name = deepcopy(base.localised_name) or { 'entity-name.' .. base.name }
  copy.localised_description = deepcopy(base.localised_description)
    or { 'entity-description.' .. base.name }
  copy.hidden = true
  copy.hidden_in_factoriopedia = true
  copy.factoriopedia_alternative = base.name
  copy.next_upgrade = nil
  return copy
end

--- Включает исходным прототипам семьи ожидание полной руки и возвращает
--- список копий `-instant` для `data:extend`. Прототип, которого нет в
--- `raw.inserter`, пропускается.
function variants.apply(raw)
  local inserters = raw.inserter or {}
  local created = {}
  for _, name in ipairs(variants.FAMILY) do
    local base = inserters[name]
    if base ~= nil then
      set_waiting(base, true)
      created[#created + 1] = variants.make_instant(base)
    end
  end
  return created
end

return variants
