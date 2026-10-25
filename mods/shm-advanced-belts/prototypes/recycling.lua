-- Рецепты переработки для прототипов мода. В 2.1 их порождает базовый мод
-- `recycler` в своём `data-updates`, то есть раньше стадий этого мода:
-- созданное позже и изменённое позже он не видит, и переработку надо
-- собирать самим.

local lib = require('__recycler__.recycling')

local recycling = {}

local function remove_unlock(recipe_name)
  local tech = data.raw.technology.recycling
  if not (tech and tech.effects) then
    return
  end
  local kept = {}
  for _, effect in ipairs(tech.effects) do
    if not (effect.type == 'unlock-recipe' and effect.recipe == recipe_name) then
      kept[#kept + 1] = effect
    end
  end
  tech.effects = kept
end

--- (Пере)собирает переработку рецептов по их именам. Старый рецепт
--- переработки и его открытие удаляются: генератор `recycler` добавил бы
--- второе открытие рядом с первым.
function recycling.generate(recipe_names)
  for _, name in ipairs(recipe_names) do
    local recipe = data.raw.recipe[name]
    if recipe then
      local result = recipe.results and recipe.results[1]
      if result and result.name then
        local recycling_name = result.name .. '-recycling'
        data.raw.recipe[recycling_name] = nil
        remove_unlock(recycling_name)
      end
      lib.generate_recycling_recipe(recipe)
    end
  end
end

return recycling
