-- Решатель: по секциям хаба, его содержимому и текущей орбите решает, какие
-- предметы закрыть замком, что дозапросить транзитом на склад и какие секции
-- груза выключить на точке назначения. Чистая логика без обращений к API
-- игры: на входе снимок, на выходе желаемое состояние. Правила — ТЗ,
-- разделы 3–5, факты ванили — entity `engine-space-platforms`.

local tags = require('logic.tags')

local resolver = {}

--- Сколько секция запрашивает предмета с учётом множителя.
local function amount(filter, multiplier)
  return math.floor((filter.min or 0) * (multiplier or 1) + 0.5)
end

local function add(map, key, value)
  map[key] = (map[key] or 0) + value
end

--- Собственный запрос секции запрещает отдачу, если хоть один фильтр идёт с
--- источником, включающим платформы.
local function blocks_giving(section)
  for _, filter in ipairs(section.filters) do
    if filter.request_from == 'platforms' or filter.request_from == 'all' then
      return true
    end
  end
  return false
end

--- Предметы, которые хаб отдаёт как груз на этой орбите: ими другие хабы
--- орбиты судят, есть ли кому сдать транзит и кому отдавать первым.
--- Секция без метки с `import_from` другой планеты и источником `planet` —
--- ванильный груз, он отдаётся так же.
function resolver.cargo_offered(hub)
  local offered = {}
  for _, section in ipairs(hub.sections) do
    if section.active then
      local tag = section.tag
      for _, filter in ipairs(section.filters) do
        local open
        if tag == nil then
          open = filter.import_from ~= nil and filter.import_from ~= hub.location
            and (filter.request_from == nil or filter.request_from == 'planet')
        elseif tag.kind == 'cargo' then
          open = tag.dests ~= nil and tags.cargo_open_at(tag, hub.location)
        else
          open = false
        end
        if open and (hub.contents[filter.key] or 0) > 0 then
          offered[filter.key] = true
        end
      end
    end
  end
  return offered
end

--- hub = {
---   location = имя места или nil в пути,
---   sections = { { index, tag, active, multiplier, filters = { { key, min, request_from, import_from } } } },
---   contents = { [key] = n }, incoming = { [key] = n },
--- }
--- cargo_here = { [key] = true } — груз для этой орбиты на других хабах.
--- Возвращает { locks = { [key] = true }, transit = { [key] = true }, release = { [index] = true } };
--- `release` — индексы секций (`section.index`, иначе позиция в списке).
function resolver.resolve(hub, cargo_here)
  cargo_here = cargo_here or {}
  local location = hub.location
  local protected = {}
  local giving = {}
  local depot_target = {}
  local release = {}

  for index, section in ipairs(hub.sections) do
    local tag = section.tag
    if section.active and tag then
      if tag.kind == 'reserve' then
        for _, filter in ipairs(section.filters) do
          add(protected, filter.key, amount(filter, section.multiplier))
        end
      elseif tag.kind == 'cargo' and tag.dests then
        if tags.cargo_open_at(tag, location) then
          for _, filter in ipairs(section.filters) do
            giving[filter.key] = true
          end
          if blocks_giving(section) then
            release[section.index or index] = true
          end
        else
          for _, filter in ipairs(section.filters) do
            add(protected, filter.key, amount(filter, section.multiplier))
          end
        end
      elseif tag.kind == 'depot' then
        local active = tags.depot_active_at(tag, location)
        for _, filter in ipairs(section.filters) do
          local count = amount(filter, section.multiplier)
          if active then
            add(depot_target, filter.key, count)
          else
            add(protected, filter.key, count)
          end
        end
      end
    end
  end

  -- Склад на своей орбите отдаёт, но после привезённого груза: пока на
  -- орбите есть груз с этим предметом, склад его держит.
  for key, target in pairs(depot_target) do
    if cargo_here[key] and not giving[key] then
      add(protected, key, target)
    else
      giving[key] = true
    end
  end

  local locks = {}
  for key, guarded in pairs(protected) do
    if guarded > 0 then
      if not giving[key] or (hub.contents[key] or 0) <= guarded then
        locks[key] = true
      end
    end
  end

  -- Транзит не несёт количества: ваниль складывает запросы на предмет и, если
  -- хоть один фильтр разрешает платформы, добирает с них весь дефицит
  -- предмета. Фильтр `min = 0` с платформ доводит склад ровно до его цели, а
  -- запрос на недостающее сверху переполнял бы склад на эту же величину.
  local transit = {}
  for key, target in pairs(depot_target) do
    local missing = target - (hub.contents[key] or 0) - (hub.incoming[key] or 0)
    if missing > 0 and cargo_here[key] then
      transit[key] = true
    end
  end

  -- Транзит — запрос с платформ, он сам запрещает отдачу, а второй фильтр на
  -- тот же предмет в одной секции ваниль не принимает.
  for key in pairs(transit) do
    locks[key] = nil
  end

  return { locks = locks, transit = transit, release = release }
end

return resolver
