-- Лоадеры AAI без отдельных технологий: рецепт лоадера открывается
-- технологией его ленты.
--
-- Лента лоадера находится по рецепту, без имён: ингредиент, который ставит
-- `transport-belt` той же скорости, что лоадер. Если такого ингредиента нет
-- (у AAI с AAI Industry рецепт идёт от предыдущего лоадера), берётся
-- единственная лента той же скорости; неоднозначно — лоадер не трогается.
-- Рецепт жёлтой ленты открыт с начала игры, никакая технология его не
-- открывает, — тогда технология ленты та, что открывает её подземку.
--
-- Чистый модуль: работает с таблицей той же формы, что `data.raw`.

local price = require('logic.price')

local unlocks = {}

local SPEED_EPSILON = 1e-9

local function same_speed(a, b)
  return a ~= nil and b ~= nil and math.abs(a - b) < SPEED_EPSILON
end

--- Предмет ленты той же скорости, что лоадер, среди ингредиентов рецепта.
local function belt_item_in_recipe(raw, recipe, speed)
  local belts = raw['transport-belt'] or {}
  for _, ingredient in ipairs(recipe.ingredients or {}) do
    local item = ingredient.type == 'item' and (raw.item or {})[ingredient.name] or nil
    local belt = item and item.place_result and belts[item.place_result] or nil
    if belt and same_speed(belt.speed, speed) then
      return ingredient.name
    end
  end
  return nil
end

--- Предмет единственной ленты той же скорости; nil — нет или несколько.
local function only_belt_item_with_speed(raw, speed)
  local found = nil
  for name, belt in pairs(raw['transport-belt'] or {}) do
    if same_speed(belt.speed, speed) and not belt.hidden then
      local item = (raw.item or {})[name]
      if item == nil then
        return nil
      end
      if found ~= nil then
        return nil
      end
      found = name
    end
  end
  return found
end

local function unlocks_recipe(tech, recipe_name)
  for _, effect in ipairs(tech.effects or {}) do
    if effect.type == 'unlock-recipe' and effect.recipe == recipe_name then
      return true
    end
  end
  return false
end

--- Имена технологий, открывающих рецепт, по алфавиту.
local function techs_unlocking(raw, recipe_name)
  local names = {}
  for name, tech in pairs(raw.technology or {}) do
    if unlocks_recipe(tech, recipe_name) then
      names[#names + 1] = name
    end
  end
  table.sort(names)
  return names
end

--- Технология, открывающая рецепт, который даёт предмет `item_name`; nil —
--- ни одной не нашлось. Из нескольких — не скрытая и первая по имени.
local function tech_for_item(raw, item_name)
  local recipe_names = {}
  for name, recipe in pairs(raw.recipe or {}) do
    local results = recipe.results or {}
    if #results == 1 and results[1].name == item_name then
      recipe_names[#recipe_names + 1] = name
    end
  end
  table.sort(recipe_names)
  for _, recipe_name in ipairs(recipe_names) do
    for _, tech_name in ipairs(techs_unlocking(raw, recipe_name)) do
      if not raw.technology[tech_name].hidden then
        return tech_name
      end
    end
  end
  return nil
end

local function remove_unlock(tech, recipe_name)
  local kept = {}
  for _, effect in ipairs(tech.effects or {}) do
    if not (effect.type == 'unlock-recipe' and effect.recipe == recipe_name) then
      kept[#kept + 1] = effect
    end
  end
  tech.effects = kept
end

--- Технология ленты: открывающая её рецепт, а если такой нет — рецепт её
--- подземки (`related_underground_belt`).
local function tech_for_belt(raw, belt_item)
  local target = tech_for_item(raw, belt_item)
  if target then
    return target
  end
  local belt = (raw['transport-belt'] or {})[(raw.item[belt_item] or {}).place_result or '']
  local underground = belt and belt.related_underground_belt
  if underground and (raw.item or {})[underground] then
    return tech_for_item(raw, underground)
  end
  return nil
end

--- Переносит открытие рецептов лоадеров AAI в технологии их лент. Возвращает
--- таблицу «спрятанная технология лоадера → технология ленты».
function unlocks.apply(raw)
  local moved = {}
  for _, recipe in ipairs(price.loader_recipes(raw)) do
    local loader_name = price.aai_loader_of_item(raw, recipe.results[1].name)
    local speed = raw['loader-1x1'][loader_name].speed
    local belt_item = belt_item_in_recipe(raw, recipe, speed) or only_belt_item_with_speed(raw, speed)
    local target = belt_item and tech_for_belt(raw, belt_item) or nil
    if target then
      for _, tech_name in ipairs(techs_unlocking(raw, recipe.name)) do
        if tech_name ~= target then
          local tech = raw.technology[tech_name]
          remove_unlock(tech, recipe.name)
          if #tech.effects == 0 then
            tech.hidden = true
            moved[tech_name] = target
          end
        end
      end
      local target_tech = raw.technology[target]
      if not unlocks_recipe(target_tech, recipe.name) then
        target_tech.effects = target_tech.effects or {}
        target_tech.effects[#target_tech.effects + 1] = { type = 'unlock-recipe', recipe = recipe.name }
      end
    end
  end
  unlocks.redirect_prerequisites(raw, moved)
  return moved
end

--- Пререквизиты на спрятанные технологии заменяются технологиями лент.
--- Цепочки (технология лоадера ← другой технологии лоадера) сворачиваются.
function unlocks.redirect_prerequisites(raw, moved)
  local function resolve(name)
    local seen = {}
    while moved[name] and not seen[name] do
      seen[name] = true
      name = moved[name]
    end
    return name
  end
  for tech_name, tech in pairs(raw.technology or {}) do
    if tech.prerequisites and not moved[tech_name] then
      local result, present = {}, {}
      for _, prerequisite in ipairs(tech.prerequisites) do
        local target = resolve(prerequisite)
        if target ~= tech_name and not present[target] then
          present[target] = true
          result[#result + 1] = target
        end
      end
      tech.prerequisites = result
    end
  end
end

return unlocks
