-- Слияние одной категории топлива с другой по всему `data.raw`.
--
-- Чистый модуль: работает с любой таблицей той же формы, что `data.raw`, и
-- к глобальным `data` / `mods` не обращается — поэтому покрыт Lua-тестами.
-- Прототипы ищутся по устройству, а не по именам: предмет с
-- `fuel_categories` и любое поле прототипа, являющееся burner-источником
-- энергии. Так чужой транспорт и чужие топки подхватываются сами.

local fuel_merge = {}

--- Возвращает новый список категорий, где `from` заменена на `to` на том же
--- месте, без дублей; либо nil, если `from` в списке нет и правка не нужна.
function fuel_merge.replace(categories, from, to)
  local found = false
  for _, category in ipairs(categories) do
    if category == from then
      found = true
      break
    end
  end
  if not found then
    return nil
  end

  local result = {}
  local seen = {}
  for _, category in ipairs(categories) do
    local next_category = category == from and to or category
    if not seen[next_category] then
      seen[next_category] = true
      table.insert(result, next_category)
    end
  end
  return result
end

local function is_burner_source(value)
  return type(value) == 'table' and value.type == 'burner' and type(value.fuel_categories) == 'table'
end

--- Правит списки категорий топлива у всех прототипов `raw` на месте.
--- Возвращает число изменённых списков: у предметов и у топок отдельно.
function fuel_merge.merge(raw, from, to)
  local changed = { items = 0, burners = 0 }

  for _, prototypes in pairs(raw) do
    for _, prototype in pairs(prototypes) do
      if type(prototype) == 'table' then
        if type(prototype.fuel_categories) == 'table' then
          local categories = fuel_merge.replace(prototype.fuel_categories, from, to)
          if categories then
            prototype.fuel_categories = categories
            changed.items = changed.items + 1
          end
        end

        for _, value in pairs(prototype) do
          if is_burner_source(value) then
            local categories = fuel_merge.replace(value.fuel_categories, from, to)
            if categories then
              value.fuel_categories = categories
              changed.burners = changed.burners + 1
            end
          end
        end
      end
    end
  end

  return changed
end

return fuel_merge
