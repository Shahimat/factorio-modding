-- Конфигурация тиров: слияние значений по умолчанию, настроек игрока и
-- переопределений из API, имена прототипов, сшивка выключенных тиров.
--
-- Чистый модуль: к `data`, `settings` и `game` не обращается, поэтому
-- покрыт Lua-тестами.

local tiers = {}

--- Шаг скорости движка: 1/256 тайла за тик.
local SPEED_STEPS = 256
--- Предметов в секунду на 1 тайл за тик: 8 предметов на тайл × 60 тиков.
local ITEMS_PER_SPEED = 480

--- Поле прототипа `speed` для скорости в предм./с, округлённое до шага движка.
function tiers.speed_field(items_per_second)
  return math.floor(items_per_second * SPEED_STEPS / ITEMS_PER_SPEED + 0.5) / SPEED_STEPS
end

--- Скорость в предм./с для поля прототипа `speed`.
function tiers.items_per_second(speed_field)
  return speed_field * ITEMS_PER_SPEED
end

--- Ванильный тир, от которого начинается цепочка.
tiers.TURBO = {
  belt = 'turbo-transport-belt',
  underground = 'turbo-underground-belt',
  splitter = 'turbo-splitter',
  technology = 'turbo-transport-belt',
  loader = 'aai-turbo-loader',
  loader_technology = 'aai-turbo-loader',
}

--- Имена прототипов тира. Лоадер AAI создаётся с именем `shm-<тир>` и по
--- правилу AAI получает имя `aai-shm-<тир>-loader`.
function tiers.names(key)
  local loader = 'aai-shm-' .. key .. '-loader'
  return {
    belt = 'shm-' .. key .. '-transport-belt',
    underground = 'shm-' .. key .. '-underground-belt',
    splitter = 'shm-' .. key .. '-splitter',
    technology = 'shm-' .. key .. '-transport-belt',
    loader_tier = 'shm-' .. key,
    loader = loader,
    loader_technology = loader,
  }
end

local function deepcopy(value)
  if type(value) ~= 'table' then
    return value
  end
  local copy = {}
  for k, v in pairs(value) do
    copy[k] = deepcopy(v)
  end
  return copy
end
tiers.deepcopy = deepcopy

--- Списки (массивы) заменяются целиком, словари сливаются по ключам.
local function is_list(value)
  return type(value) == 'table' and (#value > 0 or next(value) == nil)
end

local function merge_into(target, patch)
  for k, v in pairs(patch) do
    if type(v) == 'table' and not is_list(v) and type(target[k]) == 'table' and not is_list(target[k]) then
      merge_into(target[k], v)
    else
      target[k] = deepcopy(v)
    end
  end
  return target
end
tiers.merge_into = merge_into

--- Итоговая конфигурация тиров по порядку.
--- `defaults` — список тиров (`logic/defaults.lua`), `player[key]` —
--- `{ enabled, speed, underground }` из настроек, `overrides[key]` — таблица
--- из API. Значение из API главнее настройки игрока.
function tiers.merge(defaults, player, overrides)
  local result = {}
  for i, tier in ipairs(defaults) do
    local config = deepcopy(tier)
    config.enabled = true
    local from_player = player[tier.key] or {}
    for _, field in ipairs({ 'enabled', 'speed', 'underground' }) do
      if from_player[field] ~= nil then
        config[field] = from_player[field]
      end
    end
    merge_into(config, overrides[tier.key] or {})
    result[i] = config
  end
  return result
end

local function append(list, values)
  for _, value in ipairs(values) do
    local seen = false
    for _, existing in ipairs(list) do
      if existing == value then
        seen = true
      end
    end
    if not seen then
      list[#list + 1] = value
    end
  end
  return list
end

--- Включённые тиры с соседями по цепочке. У каждого: `names`, `previous`
--- (имена ближайшего включённого тира ниже или `tiers.TURBO`), `next`
--- (имена следующего включённого или nil) и `packs` — колбы турбо плюс колбы
--- всех тиров до текущего включительно, выключенных тоже.
function tiers.resolve(configs, turbo_packs)
  local enabled = {}
  local packs = deepcopy(turbo_packs)
  for _, config in ipairs(configs) do
    if config.pack then
      append(packs, { config.pack })
    end
    if config.enabled then
      local entry = deepcopy(config)
      entry.names = tiers.names(config.key)
      entry.packs = deepcopy(config.technology and config.technology.packs or packs)
      enabled[#enabled + 1] = entry
    end
  end
  for i, entry in ipairs(enabled) do
    entry.previous = i > 1 and enabled[i - 1].names or tiers.TURBO
    entry.next = enabled[i + 1] and enabled[i + 1].names or nil
  end
  return enabled
end

--- Ингредиенты рецепта: предмет предыдущего тира (если `previous` > 0), затем
--- ресурсы тира.
function tiers.ingredients(recipe, previous_item)
  local result = {}
  if (recipe.previous or 0) > 0 then
    result[1] = { type = 'item', name = previous_item, amount = recipe.previous }
  end
  for _, ingredient in ipairs(recipe.ingredients or {}) do
    result[#result + 1] = deepcopy(ingredient)
  end
  return result
end

--- Пререквизиты технологии тира: технология предыдущего тира и свои.
function tiers.prerequisites(entry)
  return append({ entry.previous.technology }, entry.technology.prerequisites or {})
end

--- Цвет 0–255 в формат 0–1, который принимают `tint` и `color`.
function tiers.color01(color)
  return { r = (color[1] or color.r) / 255, g = (color[2] or color.g) / 255, b = (color[3] or color.b) / 255 }
end

return tiers
