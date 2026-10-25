-- Делитель цены лоадеров AAI в режиме `expensive`.
--
-- Чистый модуль: работает с таблицей той же формы, что `data.raw`.

local price = {}

local AAI_PREFIX = 'aai-'

--- Лоадер AAI — `loader-1x1` с именем на `aai-`: по этому правилу его узнаёт
--- скрипт самого AAI.
function price.is_aai_loader(raw, name)
  local loaders = raw['loader-1x1'] or {}
  return name:sub(1, #AAI_PREFIX) == AAI_PREFIX and loaders[name] ~= nil
end

--- Имя лоадера AAI, который ставит предмет `item_name`; nil — не лоадер AAI.
function price.aai_loader_of_item(raw, item_name)
  local item = (raw.item or {})[item_name]
  if item == nil or item.place_result == nil then
    return nil
  end
  if price.is_aai_loader(raw, item.place_result) then
    return item.place_result
  end
  return nil
end

--- Ингредиенты, поделённые на `divisor` с округлением вверх, минимум 1.
--- Лоадеры AAI среди ингредиентов не делятся.
function price.divide(raw, ingredients, divisor)
  local result = {}
  for i, ingredient in ipairs(ingredients) do
    local copy = {}
    for k, v in pairs(ingredient) do
      copy[k] = v
    end
    local keep = ingredient.type == 'item' and price.aai_loader_of_item(raw, ingredient.name) ~= nil
    if not keep and type(ingredient.amount) == 'number' then
      copy.amount = math.max(1, math.ceil(ingredient.amount / divisor))
    end
    result[i] = copy
  end
  return result
end

--- Рецепты, единственный результат которых — лоадер AAI.
function price.loader_recipes(raw)
  local found = {}
  local names = {}
  for name in pairs(raw.recipe or {}) do
    names[#names + 1] = name
  end
  table.sort(names)
  for _, name in ipairs(names) do
    local recipe = raw.recipe[name]
    local results = recipe.results or {}
    local only = #results == 1 and results[1] or nil
    if only and only.type == 'item' and price.aai_loader_of_item(raw, only.name) then
      found[#found + 1] = recipe
    end
  end
  return found
end

--- Делит рецепты лоадеров AAI на месте и возвращает их список — по нему
--- пересобирается переработка. Делитель 1 и меньше — ничего не меняется.
function price.apply(raw, divisor)
  if divisor <= 1 then
    return {}
  end
  local changed = price.loader_recipes(raw)
  for _, recipe in ipairs(changed) do
    recipe.ingredients = price.divide(raw, recipe.ingredients or {}, divisor)
  end
  return changed
end

return price
