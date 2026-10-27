-- Оснастка тестов в игре: платформы на орбитах, запросы хаба, ожидание
-- передачи. Перенесена из прототипа `poc/shm-orbital-logistics-probe/`.

local fixture = {}

fixture.ITEM = 'iron-plate'
fixture.PLANET = 'nauvis'
fixture.OTHER_PLANET = 'vulcanus'

--- Тиков на одно наблюдение: передача, которой нет за минуту игры, считается
--- несостоявшейся.
fixture.WAIT = 60 * 60

local created = {}
local pads = {}
local serial = 0

local function force()
  return game.forces['player']
end

function fixture.prepare_force()
  force().research_all_technologies()
end

--- Платформа с хабом на орбите `planet` (по умолчанию Навис). Флаг раздачи
--- и автозапрос материалов стройки выключены, чтобы чужие запросы не мешали.
function fixture.platform(label, planet)
  serial = serial + 1
  local platform = force().create_space_platform({
    name = 'shm-test-' .. label .. '-' .. serial,
    planet = planet or fixture.PLANET,
    starter_pack = 'space-platform-starter-pack',
  })
  assert(platform, 'платформа не создана')
  platform.apply_starter_pack()
  local hub = platform.hub
  assert(hub and hub.valid, 'нет хаба')
  hub.request_missing_construction_materials = false
  hub.providing_to_other_platforms = false
  created[#created + 1] = platform
  return platform, hub
end

--- Секция с одним фильтром запроса на предмет.
--- opts: item, max, from (`planet` / `platforms` / `all`), import_from, group.
function fixture.request(entity, min, opts)
  opts = opts or {}
  local section = entity.get_logistic_sections().add_section(opts.group)
  assert(section, 'секция не добавлена')
  section.set_slot(1, {
    value = { type = 'item', name = opts.item or fixture.ITEM, quality = 'normal', comparator = '=' },
    min = min,
    max = opts.max,
    request_from = opts.from,
    import_from = opts.import_from,
  })
  return section
end

function fixture.inventory(entity)
  if entity.type == 'cargo-landing-pad' then
    return entity.get_inventory(defines.inventory.cargo_landing_pad_main)
  end
  return entity.get_inventory(defines.inventory.hub_main)
end

function fixture.count(entity, item)
  return fixture.inventory(entity).get_item_count(item or fixture.ITEM)
end

function fixture.trash(hub, item)
  return hub.get_inventory(defines.inventory.hub_trash).get_item_count(item or fixture.ITEM)
end

--- Сколько предмета летит в сущность: ванильный счётчик «в пути».
function fixture.incoming(entity, item)
  local index = entity.type == 'cargo-landing-pad'
      and defines.logistic_member_index.cargo_landing_pad_requester
    or defines.logistic_member_index.space_platform_hub_requester
  local point = entity.get_logistic_point(index)
  if not point then
    return 0
  end
  local total = 0
  for _, entry in pairs(point.targeted_items_deliver or {}) do
    if entry.name == (item or fixture.ITEM) then
      total = total + entry.count
    end
  end
  return total
end

--- Грузовая площадка на Нависе. Площадка одна на поверхность, поэтому
--- создаётся один раз и чистится между наблюдениями.
function fixture.pad()
  local surface = game.surfaces[fixture.PLANET]
  local pad = pads[1]
  if pad and pad.valid then
    return pad
  end
  for _, existing in pairs(surface.find_entities_filtered({ type = 'cargo-landing-pad' })) do
    pads[1] = existing
    return existing
  end
  surface.request_to_generate_chunks({ 0, 0 }, 2)
  surface.force_generate_chunk_requests()
  pad = surface.create_entity({ name = 'cargo-landing-pad', position = { 0, 0 }, force = force() })
  assert(pad, 'площадка не создана')
  pads[1] = pad
  return pad
end

local function clear_sections(entity)
  local sections = entity.get_logistic_sections()
  for index = sections.sections_count, 1, -1 do
    local section = sections.get_section(index)
    if section.is_manual then
      sections.remove_section(index)
    end
  end
end

--- Убирает всё созданное наблюдением: чужая платформа с предметами в
--- следующем наблюдении стала бы лишним поставщиком.
function fixture.clear()
  for _, platform in ipairs(created) do
    if platform.valid and platform.hub and platform.hub.valid then
      platform.hub.providing_to_other_platforms = false
      clear_sections(platform.hub)
      fixture.inventory(platform.hub).clear()
      -- Излишек сверх max уходит в мусорные слоты, а платформа, ждущая
      -- удаления, досбросила бы его на площадку следующего наблюдения.
      platform.hub.get_inventory(defines.inventory.hub_trash).clear()
      platform.destroy()
    end
  end
  created = {}
  for _, pad in pairs(pads) do
    if pad.valid then
      clear_sections(pad)
      fixture.inventory(pad).clear()
    end
  end
end

--- Ждёт, пока `done_when()` не станет истинным, или `ticks` тиков. Затем
--- вызывает `finish(elapsed, reached)`.
function fixture.watch(ticks, done_when, finish)
  local elapsed = 0
  on_tick(function()
    elapsed = elapsed + 1
    local reached = done_when()
    if reached or elapsed >= ticks then
      finish(elapsed, reached)
      return false
    end
  end)
end

--- Наименьшее содержимое хаба за время ожидания: отдал ли он что-нибудь.
function fixture.track(entity, item)
  local tracker = { lowest = fixture.count(entity, item) }
  function tracker.step()
    tracker.lowest = math.min(tracker.lowest, fixture.count(entity, item))
  end
  return tracker
end

return fixture
