-- Публичный API `ShmAdvancedBelts`: другие моды перенастраивают тиры в своём
-- `data.lua`. Здесь только приём и проверка переопределений; применяет их
-- `logic/tiers.lua` при сборке тиров в `data-updates.lua`.
--
-- Чистый модуль: таблица API создаётся функцией и к `data` не обращается.

local api = {}

--- Поля, которые можно переопределить у тира.
local ALLOWED = {
  enabled = 'boolean',
  speed = 'number',
  color = 'table',
  recipes = 'table',
  technology = 'table',
  loader_technology = 'table',
}

local RECIPE_PARTS = { belt = true, underground = true, splitter = true, loader = true, loader_expensive = true }

local function fail(message)
  error('ShmAdvancedBelts: ' .. message, 3)
end

--- Создаёт таблицу API над списком ключей тиров.
--- @param keys string[]
function api.new(keys)
  local known = {}
  for _, key in ipairs(keys) do
    known[key] = true
  end

  local overrides = {}
  local sealed = false
  local instance = {}

  --- Переопределяет поля тира. Повторный вызов дополняет прежний: словари
  --- сливаются по ключам, списки заменяются целиком.
  --- @param key string ключ тира: superior, ultra, hyper, absolute
  --- @param patch table
  function instance.configure(key, patch)
    if sealed then
      fail('тиры уже собраны — вызывайте API в data.lua своего мода')
    end
    if not known[key] then
      fail('неизвестный тир «' .. tostring(key) .. '»')
    end
    if type(patch) ~= 'table' then
      fail('ожидается таблица полей тира')
    end
    for field, value in pairs(patch) do
      local expected = ALLOWED[field]
      if expected == nil then
        fail('неизвестное поле «' .. tostring(field) .. '» у тира ' .. key)
      end
      if type(value) ~= expected then
        fail('поле «' .. field .. '» у тира ' .. key .. ' должно быть ' .. expected)
      end
    end
    for part in pairs(patch.recipes or {}) do
      if not RECIPE_PARTS[part] then
        fail('неизвестный рецепт «' .. tostring(part) .. '» у тира ' .. key)
      end
    end
    local target = overrides[key] or {}
    overrides[key] = target
    for field, value in pairs(patch) do
      if type(value) == 'table' and type(target[field]) == 'table' and field ~= 'color' then
        for k, v in pairs(value) do
          target[field][k] = v
        end
      else
        target[field] = value
      end
    end
  end

  --- Выключает или включает тир.
  function instance.set_enabled(key, enabled)
    instance.configure(key, { enabled = enabled })
  end

  --- Внутреннее: переопределения для сборки; после вызова API закрыт.
  function instance._take()
    sealed = true
    return overrides
  end

  return instance
end

return api
