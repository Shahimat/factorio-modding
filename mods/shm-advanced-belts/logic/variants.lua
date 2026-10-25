-- Стак на ленте и ожидание полной стопки для всех лоадеров.
--
-- Ожидание полной стопки (`wait_for_full_stack`) задаётся только в
-- прототипе, поэтому режим конкретного лоадера — выбор одного из двух
-- прототипов: исходного (режим по умолчанию из настройки) и скрытой копии
-- `<имя>-shm-alt` с противоположным режимом. Копия начинается с того же
-- префикса, что исходный: скрипт AAI узнаёт свои лоадеры по `aai-`.
--
-- Чистый модуль: работает с таблицей той же формы, что `data.raw`.

local variants = {}

variants.LOADER_TYPES = { 'loader', 'loader-1x1' }
variants.ALT_SUFFIX = '-shm-alt'
--- Суффикс скрытой трубы лоадера AAI в режиме `lubricated`.
variants.PIPE_SUFFIX = '-pipe'

function variants.alt_name(base)
  return base .. variants.ALT_SUFFIX
end

--- Имя исходного прототипа для копии; для исходного — само имя.
function variants.base_name(name)
  if name:sub(-#variants.ALT_SUFFIX) == variants.ALT_SUFFIX then
    return name:sub(1, -#variants.ALT_SUFFIX - 1)
  end
  return name
end

function variants.is_alt(name)
  return name ~= variants.base_name(name)
end

--- Ждёт ли прототип `name` полную стопку, если исходные ждут `default_waiting`.
function variants.is_waiting(name, default_waiting)
  if variants.is_alt(name) then
    return not default_waiting
  end
  return default_waiting
end

--- Имя прототипа нужного режима в семье `name`.
function variants.with_mode(name, waiting, default_waiting)
  local base = variants.base_name(name)
  if waiting == default_waiting then
    return base
  end
  return variants.alt_name(base)
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

--- Предмет, которым ставится прототип: `placeable_by` или результат разборки.
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

--- Стак на ленте всем лоадерам. Скрытые прототипы тоже: стак ничего не
--- ломает, а ванильные лоадеры, открытые другим модом, его получат.
function variants.apply_stacking(raw, max_stack)
  for _, loader_type in ipairs(variants.LOADER_TYPES) do
    for _, loader in pairs(raw[loader_type] or {}) do
      loader.max_belt_stack_size = max_stack
      loader.adjustable_belt_stack_size = true
    end
  end
end

--- Получает ли лоадер копию-переключатель: виден игроку и умеет стопки.
function variants.is_switchable_prototype(prototype)
  return not prototype.hidden and (prototype.max_belt_stack_size or 1) > 1
end

--- Копия лоадера с противоположным режимом.
function variants.make_alt(base, waiting)
  local copy = deepcopy(base)
  copy.name = variants.alt_name(base.name)
  copy.wait_for_full_stack = waiting
  copy.placeable_by = placing_item(base)
  copy.localised_name = deepcopy(base.localised_name) or { 'entity-name.' .. base.name }
  copy.localised_description = deepcopy(base.localised_description) or { 'entity-description.' .. base.name }
  copy.hidden = true
  copy.hidden_in_factoriopedia = true
  copy.factoriopedia_alternative = base.name
  copy.next_upgrade = nil
  return copy
end

--- Исходным лоадерам — режим по умолчанию, каждому подходящему — копия с
--- противоположным, а копии лоадера AAI с трубой — копия трубы. Возвращает
--- список новых прототипов для `data:extend`.
function variants.apply(raw, default_waiting)
  local created = {}
  local tanks = raw['storage-tank'] or {}
  for _, loader_type in ipairs(variants.LOADER_TYPES) do
    local names = {}
    for name in pairs(raw[loader_type] or {}) do
      names[#names + 1] = name
    end
    table.sort(names)
    for _, name in ipairs(names) do
      local base = raw[loader_type][name]
      if variants.is_switchable_prototype(base) and not variants.is_alt(name) then
        base.wait_for_full_stack = default_waiting
        created[#created + 1] = variants.make_alt(base, not default_waiting)
        local pipe = tanks[name .. variants.PIPE_SUFFIX]
        if pipe ~= nil then
          local pipe_copy = deepcopy(pipe)
          pipe_copy.name = variants.alt_name(name) .. variants.PIPE_SUFFIX
          created[#created + 1] = pipe_copy
        end
      end
    end
  end
  return created
end

return variants
