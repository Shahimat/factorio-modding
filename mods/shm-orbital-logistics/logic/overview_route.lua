-- Порядок остановок — порядок расписания, а не текущая орбита. Подсветка
-- хранится отдельно: смена положения не перестраивает цепочку элементов.
local route = {}

function route.build(stops, current, location, from, to, departure)
  local model = { stops = {}, loop = #stops > 1 }
  for index, name in ipairs(stops) do model.stops[index] = name end
  if #stops == 0 then
    if location then
      model.stops = { location }
      model.active_stop = 1
    elseif from and to then
      model.stops = { from, to }
      model.active_leg = 1
    end
    return model
  end

  if location then
    -- Индекс отличает повторные посещения одной планеты. При ручной
    -- перестановке или изменённом расписании не подсвечиваем чужое место.
    if stops[current] == location then
      model.active_stop = current
    elseif current and stops[(current - 2) % #stops + 1] == location then
      model.active_stop = (current - 2) % #stops + 1
    else
      for index, name in ipairs(stops) do
        if name == location then model.active_stop = index; break end
      end
    end
  elseif from and to and #stops > 1 then
    if current and stops[current] then
      -- current в пути — остановка назначения, в том числе после перелёта
      -- через промежуточную орбиту. Но ручной пропуск записи не доказывает
      -- вылет с previous(current): нужен реальный источник либо наблюдавшаяся
      -- перед этим остановка. Без такого знания не подсвечиваем выдуманное плечо.
      local previous = (current - 2) % #stops + 1
      if (departure and departure == previous) or (not departure and stops[previous] == from) then
        model.active_leg = previous
      end
    else
      for index, name in ipairs(stops) do
        if name == from and stops[index % #stops + 1] == to then
          if model.active_leg then model.active_leg = nil; break end
          model.active_leg = index
        end
      end
    end
  end
  return model
end

return route
