-- Панель у окна хаба и площадки: назначение секций меткой в имени группы,
-- состояние предметов по своей секции мода, детали поведения предметов в
-- группах, предупреждение про флаг раздачи и подключение к линиям снабжения.
-- ТЗ, раздел 8.

local tags = require('logic.tags')
local groups = require('runtime.groups')
local lines = require('runtime.lines')
local own_section = require('logic.own_section')
local resolver = require('logic.resolver')
local controller = require('runtime.controller')
local lines_logic = require('logic.lines')
local picker = require('runtime.places_picker')

local panel = {}

panel.NAME = 'shm_ol_panel'
local PURPOSES = { 'none', 'reserve', 'cargo', 'depot' }
local L = 'shm-orbital-logistics.'

local function purpose_index(tag)
  local kind = tag and tag.kind or 'none'
  for index, purpose in ipairs(PURPOSES) do
    if purpose == kind then
      return index
    end
  end
  return 1
end

local function anchor(entity)
  if entity.type == 'cargo-landing-pad' then
    return defines.relative_gui_type.cargo_landing_pad_gui
  end
  return defines.relative_gui_type.space_platform_hub_gui
end

--- Своя секция мода: какие предметы под замком, какие в транзите.
local function own_state(hub)
  local state = { locks = {}, transit = {} }
  local saved = storage.platforms and hub.surface.platform and storage.platforms[hub.surface.platform.index]
  for _, filter in ipairs(saved and saved.written or {}) do
    if filter.request_from == 'platforms' then
      state.transit[filter.key] = true
    else
      state.locks[filter.key] = true
    end
  end
  return state
end

local function giving_tags(hub)
  local sections = hub.get_logistic_sections()
  for index = 1, sections.sections_count do
    local tag = tags.parse(sections.get_section(index).group)
    if tag and (tag.kind == 'depot' or (tag.kind == 'cargo' and tag.dests)) then
      return true
    end
  end
  return false
end

--- Линия, которой принадлежит группа, — её секцию правит окно линий.
local function line_of(force, group)
  for _, line in ipairs(lines.list(force)) do
    if lines_logic.owns(line.name, group) then
      return line
    end
  end
  return nil
end

--- Предметы помеченных секций со состоянием по своей секции мода. Обновляется
--- раз в секунду, поэтому живёт в своём контейнере.
local STATUS_ICONS = {
  giving = 'utility/status_working',
  held = 'utility/status_yellow',
  -- Цветные точки статуса, как у машин игры: значки «пауза» и «импорт»
  -- тёмные и на тёмном фоне не видны.
  released = 'utility/status_blue',
  transit = 'utility/status_inactive',
  -- Ловушка источника запроса склада: платформам не отдаст или на планету
  -- под хабом не сбросит. Красных точек статуса в игре нет — треугольник «!».
  warn = 'utility/warning_icon',
  -- Выключенная игроком секция — тот же серый значок «не работает», что у
  -- транзита: различает подпись. Пустая группа ничего не обещает — вопрос.
  inactive = 'utility/status_inactive',
  empty = 'utility/questionmark',
}

local function icon(kind)
  local path = STATUS_ICONS[kind]
  if path and helpers.is_valid_sprite_path(path) then
    return '[img=' .. path .. '] '
  end
  return ''
end

local function quality_of(value)
  return value.quality and (type(value.quality) == 'string' and value.quality or value.quality.name) or nil
end

local function name_of(value)
  if value == nil then
    return nil
  end
  if type(value) == 'string' then
    return value
  end
  return value.name
end

local function item_filters(section)
  local list = {}
  for _, slot in pairs(section.filters) do
    local value = slot.value
    if value and value.name and (value.type == nil or value.type == 'item') and prototypes.item[value.name] then
      list[#list + 1] = {
        name = value.name,
        quality = quality_of(value),
        request_from = slot.request_from,
        import_from = name_of(slot.import_from),
      }
    end
  end
  return list
end

--- Места метки иконками с игровыми названиями: «[Аквило], [Глеба]».
local function places_caption(set)
  local caption = { '' }
  local first = true
  local names = {}
  for name in pairs(set or {}) do
    names[#names + 1] = name
  end
  table.sort(names)
  for _, name in ipairs(names) do
    local prototype = prototypes.space_location[name]
    if not first then
      caption[#caption + 1] = ', '
    end
    first = false
    caption[#caption + 1] = prototype and { '', '[img=space-location/' .. name .. '] ', prototype.localised_name } or name
  end
  return caption
end

--- Ссылка на место rich text'ом [planet=…]: игра рисует значок с названием
--- и по клику открывает Факториопедию, convention `localization`. Категории
--- `planet` в LuaPrototypes нет, поэтому планета здесь — любое место из
--- space-location: метки мода — орбиты и назначения, и `[planet=__1__]` в
--- `pad-name` подставляет место так же.
local function place_link(name)
  if prototypes.space_location[name] then
    return { '', '[planet=' .. name .. ']' }
  end
  return { '', name }
end

--- Множество мест ссылками — для фраз в деталях предметов.
local function places_rich(set)
  local caption = { '' }
  local names = {}
  for name in pairs(set or {}) do
    names[#names + 1] = name
  end
  table.sort(names)
  for i, name in ipairs(names) do
    if i > 1 then
      caption[#caption + 1] = ', '
    end
    caption[#caption + 1] = place_link(name)
  end
  return caption
end

--- Состояние группы с меткой на текущей орбите: вид значка и строка. Для
--- склада — третий итог: true, когда строка группы уже сказала «не сможет
--- отдавать платформам» и предметам повторять это не нужно.
local function group_state(tag, location, released, items)
  local count = #items
  if count == 0 then
    -- Группа без фильтров предметов ничего не делает: не «раздаёт».
    return 'empty', { L .. 'now-empty-group' }
  end
  if tag.kind == 'reserve' then
    return 'held', { L .. 'now-reserve', count }
  end
  if tag.kind == 'cargo' then
    if tag.dests == nil then
      return 'giving', { L .. 'now-cargo-any' }
    end
    if released then
      return 'released', { L .. 'now-released' }
    end
    if tags.cargo_open_at(tag, location) then
      return 'giving', { L .. 'now-cargo-here' }
    end
    return 'held', { L .. 'now-cargo-held', places_caption(tag.dests), count }
  end
  if tags.depot_active_at(tag, location) then
    -- У всех предметов источник «Платформы»/«Все» — склад не отдаёт никому,
    -- и «раздаёт» было бы ложью (V-01b/V-02).
    local blocked = count > 0
    for _, item in ipairs(items) do
      local give = tags.source_problems(item, location)
      if not give then
        blocked = false
        break
      end
    end
    if blocked then
      return 'held', { L .. 'now-depot-no-give' }, true
    end
    return 'giving', { L .. 'now-depot-here' }
  end
  if tag.anywhere then
    return 'held', { L .. 'now-depot-flight', count }
  end
  return 'held', { L .. 'now-depot-held', places_caption(tag.orbits), count }
end

--- «Отдача на этой орбите» без GUI: строка на каждую группу с меткой — что
--- мод с ней делает на этой орбите, — и исключения: предметы, которые
--- ведут себя не как их группа. Данные общие для блока и итога свёрнутого
--- блока, чтобы итог не разошёлся с содержимым.
local function now_data(hub)
  local state = own_state(hub)
  local platform = hub.surface.platform
  local location = platform and platform.space_location and platform.space_location.name
  local saved = storage.platforms and platform and storage.platforms[platform.index]
  local released = saved and saved.released or {}
  local rows = {}
  local expected = {}
  local reserved = {}
  local first_item = {}
  local blocked_give = {}
  local blocked_drop = {}
  local row_covered = {}
  local sections = hub.get_logistic_sections()
  for index = 1, sections.sections_count do
    local section = sections.get_section(index)
    local tag = section.is_manual and not controller.is_service(section.group) and tags.parse(section.group)
    if tag then
      local items = item_filters(section)
      -- Ванильная галочка: секция, выключенная игроком (не модом), ничего
      -- не делает — своя строка «выключена», её предметы ничего не обещают.
      -- Вернувший галочку игрок включает секцию: «выключена до отлёта»
      -- пишется только про секцию, выключенную модом и до сих пор снятую.
      local released_by_mod = released[section.group] ~= nil
      local disabled = not section.active and not released_by_mod
      local kind, caption, covered
      if disabled then
        kind, caption = 'inactive', { L .. 'now-inactive' }
      else
        kind, caption, covered = group_state(tag, location, released_by_mod and not section.active, items)
      end
      rows[#rows + 1] = { group = section.group, kind = kind, caption = caption, anchor = items[1] }
      if not disabled then
        local on_duty = tag.kind == 'depot' and tags.depot_active_at(tag, location)
        for _, item in ipairs(items) do
          local key = own_section.key(item.name, item.quality)
          first_item[key] = first_item[key] or item
          if tag.kind == 'reserve' then
            reserved[key] = true
          end
          if covered then
            row_covered[key] = true
          end
          if on_duty then
            local give, drop = tags.source_problems(item, location)
            blocked_give[key] = blocked_give[key] or give
            blocked_drop[key] = blocked_drop[key] or drop
          end
          if expected[key] ~= 'held' then
            expected[key] = (kind == 'held') and 'held' or 'open'
          end
        end
      end
    end
  end
  -- Исключения сводятся по типу состояния: одна строка на тип с сеткой
  -- иконок предметов — стена одинаковых объяснений сжимается до нескольких.
  local exceptions = {}
  local by_type = {}
  for key, item in pairs(first_item) do
    local text = nil
    local kind = nil
    -- Свои состояния мода важнее: транзит и замки объясняют, что мод делает
    -- с предметом; ловушка источника склада — про ванильную отдачу и сброс.
    if state.transit[key] then
      kind, text = 'transit', { L .. 'now-ex-transit' }
    elseif state.locks[key] and expected[key] == 'open' then
      kind = 'held'
      text = reserved[key] and { L .. 'now-ex-reserve-left' } or { L .. 'now-ex-yield' }
    elseif not state.locks[key] and expected[key] == 'held' and reserved[key] then
      kind, text = 'giving', { L .. 'now-ex-over-reserve' }
    else
      local give_marked = blocked_give[key] and not row_covered[key]
      if give_marked and blocked_drop[key] then
        kind, text = 'warn', { L .. 'now-depot-no-both' }
      elseif give_marked then
        kind, text = 'warn', { L .. 'now-depot-no-give' }
      elseif blocked_drop[key] then
        kind, text = 'warn', { L .. 'now-depot-no-drop' }
      end
    end
    if text then
      local type_key = tostring(text[1])
      local bucket = by_type[type_key]
      if not bucket then
        bucket = { kind = kind, text = text, items = {} }
        by_type[type_key] = bucket
        exceptions[#exceptions + 1] = bucket
      end
      bucket.items[#bucket.items + 1] = { key = key, item = item }
    end
  end
  for _, bucket in ipairs(exceptions) do
    table.sort(bucket.items, function(a, b) return a.key < b.key end)
  end
  table.sort(exceptions, function(a, b) return tostring(a.text[1]) < tostring(b.text[1]) end)
  return rows, exceptions
end

--- Полный список предметов исключения rich text'ом — тултип строки типа.
--- У локализованной строки лимит в 20 параметров: список режется на куски
--- по 10 предметов, куски вкладываются друг в друга группами по 10.
local function items_tooltip(entries)
  local leaves = {}
  local leaf = { '' }
  for _, one in ipairs(entries) do
    if #leaf > 1 then
      leaf[#leaf + 1] = ', '
    end
    local item = one.item
    leaf[#leaf + 1] = '[item=' .. item.name .. (item.quality and (',quality=' .. item.quality) or '') .. ']'
    if #leaf > 17 then
      leaves[#leaves + 1] = leaf
      leaf = { '' }
    end
  end
  if #leaf > 1 then
    leaves[#leaves + 1] = leaf
  end
  if #leaves == 0 then
    return { '' }
  end
  local function join(list)
    if #list == 1 then
      return list[1]
    end
    local grouped = {}
    for start = 1, #list, 10 do
      local node = { '' }
      for offset = 0, 9 do
        local part = list[start + offset]
        if part == nil then
          break
        end
        if #node > 1 then
          node[#node + 1] = ', '
        end
        node[#node + 1] = part
      end
      grouped[#grouped + 1] = node
    end
    return join(grouped)
  end
  return { '', join(leaves) }
end

--- Отрисовка «Отдачи» из данных `now_data`. Обновляется раз в секунду,
--- поэтому живёт в своём контейнере.
local function fill_now(flow, hub)
  flow.clear()
  local rows, exceptions = now_data(hub)
  if #rows == 0 then
    flow.add({ type = 'label', caption = { L .. 'now-nothing' } })
    return
  end
  local groups = flow.add({ type = 'table', column_count = 3 })
  for column = 1, 3 do
    groups.style.column_alignments[column] = 'middle-left'
  end
  for _, row in ipairs(rows) do
    groups.add({
      type = 'sprite-button',
      sprite = row.anchor and ('item/' .. row.anchor.name) or 'utility/questionmark',
      style = 'slot_button',
      tooltip = row.group,
    }).style.size = 32
    local name = groups.add({ type = 'label', caption = row.group })
    name.style.maximal_width = 240
    name.style.font = 'default-semibold'
    groups.add({ type = 'label', caption = { '', icon(row.kind), row.caption } })
  end
  if #exceptions > 0 then
    flow.add({ type = 'label', caption = { L .. 'now-exceptions' }, style = 'caption_label' })
    local list = flow.add({ type = 'table', column_count = 2 })
    for column = 1, 2 do
      list.style.column_alignments[column] = 'middle-left'
    end
    local inventory = hub.get_inventory(defines.inventory.hub_main)
    -- Одна строка на тип состояния: сетка иконок до 10 и «+N ещё», полный
    -- список предметов — в тултипе строки.
    for _, entry in ipairs(exceptions) do
      local cell = list.add({ type = 'flow', direction = 'horizontal' })
      local grid = cell.add({ type = 'table', name = 'shm_ol_exception_grid', column_count = 10 })
      local tooltip = items_tooltip(entry.items)
      for i, one in ipairs(entry.items) do
        if i > 10 then
          break
        end
        grid.add({
          type = 'sprite-button',
          sprite = 'item/' .. one.item.name,
          style = 'slot_button',
          number = inventory.get_item_count({ name = one.item.name, quality = one.item.quality }),
          tooltip = '[item=' .. one.item.name .. (one.item.quality and (',quality=' .. one.item.quality) or '') .. ']',
        }).style.size = 32
      end
      if #entry.items > 10 then
        local more = cell.add({ type = 'label', name = 'shm_ol_exception_more', caption = { L .. 'now-more', #entry.items - 10 } })
        more.style.font_color = { 0.7, 0.7, 0.7 }
        more.style.left_padding = 4
        more.tooltip = tooltip
      end
      local status = list.add({ type = 'label', caption = { '', icon(entry.kind), entry.text } })
      status.style.single_line = false
      status.style.maximal_width = 220
      status.tooltip = tooltip
    end
  end
end

--- Ловушки источников у секций склада хаба — для красных предупреждений.
local function depot_source_problems(hub, location)
  local give, drop = false, false
  local sections = hub.get_logistic_sections()
  for index = 1, sections.sections_count do
    local section = sections.get_section(index)
    if section.is_manual and not controller.is_service(section.group) then
      local tag = tags.parse(section.group)
      if tag and tag.kind == 'depot' then
        for _, item in ipairs(item_filters(section)) do
          local item_give, item_drop = tags.source_problems(item, location)
          give = give or item_give
          drop = drop or item_drop
        end
      end
    end
  end
  return give, drop
end

local function warn(flow, name, caption)
  local label = flow.add({ type = 'label', name = name, caption = caption })
  label.style.font_color = { 1, 0.3, 0.3 }
  label.style.single_line = false
  label.style.maximal_width = 500
end

--- Красные предупреждения: выключенная раздача и ловушки источников склада.
--- Перечитывается раз в секунду, поэтому живёт в своём контейнере.
local function fill_warnings(flow, hub)
  flow.clear()
  if not hub.providing_to_other_platforms and giving_tags(hub) then
    warn(flow, 'shm_ol_warning', { L .. 'warning-providing' })
  end
  local platform = hub.surface.platform
  local location = platform and platform.space_location and platform.space_location.name
  local give, drop = depot_source_problems(hub, location)
  if give then
    warn(flow, 'shm_ol_warning_depot_source', { L .. 'warning-depot-source' })
  end
  if drop then
    warn(flow, 'shm_ol_warning_depot_drop', { L .. 'warning-depot-drop' })
  end
end

--- Подключение к линиям снабжения: участники, выбор линии и кнопка окна.
--- Вызывается, только когда линии есть: пустой блок линий — одна кнопка.
local function add_lines(frame, player, entity)
  local member = lines.of_entity(player.force, entity)
  for _, entry in ipairs(member) do
    frame.add({ type = 'label', caption = { L .. 'lines-member', entry.line.name } })
  end
  local flow = frame.add({ type = 'flow', direction = 'horizontal' })
  local items = {}
  for i, line in ipairs(lines.list(player.force)) do
    items[i] = line.name
  end
  flow.add({ type = 'drop-down', name = 'shm_ol_attach_line', items = items, selected_index = 1 })
  flow.add({ type = 'button', name = 'shm_ol_attach', caption = { L .. 'lines-attach' } }).style.minimal_width = 100
  frame.add({ type = 'button', name = 'shm_ol_open_lines', caption = { L .. 'lines-open' } })
end

function panel.destroy(player)
  local existing = player.gui.relative[panel.NAME]
  if existing then
    existing.destroy()
  end
end

--- Отпечаток групп хаба: если игрок добавил, убрал, переименовал группу или
--- мод выключил её, панель перестраивается целиком.
local function signature(entity)
  local parts = {}
  local sections = entity.get_logistic_sections()
  for index = 1, sections.sections_count do
    local section = sections.get_section(index)
    -- Служебная группа меняется с каждым замком — из-за неё панель не
    -- перестраиваем.
    if not controller.is_service(section.group) then
      parts[#parts + 1] = index .. ':' .. section.group .. ':' .. tostring(section.active) .. ':' .. section.filters_count
    end
  end
  return table.concat(parts, '|')
end

panel.POSITION_SETTING = 'shm-orbital-logistics-panel-position'

--- Положение панели — настройка игрока: снизу и сверху блоки идут в ряд,
--- чтобы панель была низкой, слева и справа — столбиком.
local function position_of(player)
  local setting = player.mod_settings[panel.POSITION_SETTING]
  local value = setting and setting.value or 'bottom'
  if defines.relative_gui_position[value] == nil then
    value = 'bottom'
  end
  return value
end

--- Кнопка свернуть/развернуть: значок есть в игре — значком, нет — текстом,
--- как у значков статуса. `to_collapsed` — что сделает клик: сворачивает
--- (значок-треугольник вниз) или разворачивает (треугольник вбок).
local function toggle_button(parent, name, to_collapsed, tags)
  local path = to_collapsed and 'utility/collapse' or 'utility/expand'
  local key = to_collapsed and 'collapse' or 'expand'
  if helpers.is_valid_sprite_path(path) then
    local button = parent.add({
      type = 'sprite-button',
      name = name,
      sprite = path,
      tooltip = { L .. key },
      tags = tags,
    })
    button.style.size = 24
    return button
  end
  return parent.add({
    type = 'button',
    name = name,
    caption = { L .. key },
    tooltip = { L .. key },
    tags = tags,
  })
end

--- «Свёрнуто» — на игрока: состояние переживает сохранение и загрузку само,
--- storage сохраняется.
local function is_collapsed(player_index)
  return (storage.panel_collapsed or {})[player_index] == true
end

--- Свёрнутость блока — рядом с `panel_collapsed`: состояние на игрока,
--- переживает переоткрытие окна, сохранение и загрузку.
local function block_collapsed(player_index, key)
  local state = storage.panel_block_collapsed
  return (state and state[player_index] and state[player_index][key]) == true
end

--- Сколько строк в «Группах» — итог свёрнутого блока по реальному содержимому.
local function section_rows(hub)
  local rows = 0
  local sections = hub.get_logistic_sections()
  for index = 1, sections.sections_count do
    local section = sections.get_section(index)
    if section.is_manual and not controller.is_service(section.group) then
      rows = rows + 1
    end
  end
  return rows
end

--- Потолок высоты панели: доля рабочей области. display_resolution —
--- экранные пиксели, display_scale переводит их в единицы GUI.
local HEIGHT_SHARE = 0.8
panel.HEIGHT_SHARE = HEIGHT_SHARE

local function height_cap(player)
  local resolution = player.display_resolution
  local scale = player.display_scale
  if not resolution or not scale or scale <= 0 then
    return nil
  end
  return math.floor(resolution.height / scale * HEIGHT_SHARE)
end

--- Заголовок блока: треугольник сворачивания и название.
local function block_header(parent, key, title_key)
  local header = parent.add({ type = 'flow', direction = 'horizontal', name = 'shm_ol_header_' .. key })
  toggle_button(header, 'shm_ol_block_toggle', true, { block = key })
  header.add({ type = 'label', caption = { L .. title_key }, style = 'caption_label' })
end

--- Свёрнутый блок: треугольник и строка-итог; клик по строке разворачивает.
local function collapsed_block(parent, key, summary)
  toggle_button(parent, 'shm_ol_block_toggle', false, { block = key })
  parent.add({
    type = 'button',
    name = 'shm_ol_block_summary',
    caption = summary,
    tags = { block = key },
  })
end

--- Прокрутка блока: вертикальная, тянется вместе с рамкой, но не выше
--- потолка; сжимаемая, чтобы потолок рамки доходил до неё.
local function scroll_pane(parent, name, cap)
  local scroll = parent.add({ type = 'scroll-pane', name = name, direction = 'vertical' })
  scroll.style.vertically_stretchable = true
  scroll.style.vertically_squashable = true
  if cap then
    scroll.style.maximal_height = cap
  end
  return scroll
end

--- Поиск по имени на любой глубине: контейнеры «Отдачи», предупреждений и
--- деталей живут в прокрутках своих блоков.
local function find_named(root, name)
  if root.name == name then
    return root
  end
  for _, child in pairs(root.children) do
    local found = find_named(child, name)
    if found then
      return found
    end
  end
  return nil
end

--- Все элементы с именами по префиксу: контейнеры деталей по каждой группе.
local function collect_named(root, prefix, acc)
  acc = acc or {}
  if root.name and string.sub(root.name, 1, #prefix) == prefix then
    acc[#acc + 1] = root
  end
  for _, child in pairs(root.children) do
    collect_named(child, prefix, acc)
  end
  return acc
end

--- Груз на этой орбите на других хабах — как его видит контроллер: последние
--- известные предложения соседей по орбите из storage.orbit.
local function orbit_cargo(platform)
  local location = platform.space_location and platform.space_location.name
  if not location then
    return {}
  end
  local where = platform.force.name .. '/' .. location
  local set = {}
  for index, entry in pairs(storage.orbit or {}) do
    if index ~= platform.index and entry.where == where then
      for key in pairs(entry.offered or {}) do
        set[key] = true
      end
    end
  end
  return set
end

--- Есть ли на этой орбите склад: из последних известных состояний
--- контроллера, как их видит решатель при транзите.
local function depot_orbit(platform)
  local location = platform.space_location and platform.space_location.name
  if not location then
    return false
  end
  local where = platform.force.name .. '/' .. location
  for _, entry in pairs(storage.orbit or {}) do
    if entry.where == where and entry.depot then
      return true
    end
  end
  return false
end

--- Предметы секции из снимка: то же представление, что у «Отдачи».
local function snap_items(section)
  local list = {}
  for _, filter in ipairs(section.filters) do
    local name, quality = own_section.split(filter.key)
    list[#list + 1] = {
      name = name,
      quality = quality,
      request_from = filter.request_from,
      import_from = filter.import_from,
    }
  end
  return list
end

--- Метки сравниваются каноническим текстом: множества мест без порядка.
local function same_tag(a, b)
  if (a == nil) ~= (b == nil) then
    return false
  end
  return a == nil or tags.format(a) == tags.format(b)
end

--- Фраза поведения предмета в секции: короткая механическая формулировка из
--- его фильтра, метки секции и текущей орбиты. Названия мест — ссылками.
local function item_phrase(tag, location, filter, multiplier)
  local n = resolver.amount(filter, multiplier)
  if tag == nil then
    local source = filter.request_from or 'planet'
    if filter.import_from and source == 'planet' then
      return { L .. 'details-cargo-vanilla', places_rich({ [filter.import_from] = true }) }
    end
    return { L .. 'details-none' }
  end
  if tag.kind == 'reserve' then
    return { L .. 'details-reserve', n }
  end
  if tag.kind == 'cargo' then
    local from = filter.import_from and places_rich({ [filter.import_from] = true }) or { L .. 'details-everywhere' }
    if tag.dests == nil then
      if filter.import_from then
        return { L .. 'details-cargo-vanilla', from }
      end
      return { L .. 'details-cargo-anywhere' }
    end
    if tags.cargo_open_at(tag, location) then
      return { L .. 'details-cargo-dest', from, places_rich(tag.dests) }
    end
    return { L .. 'details-cargo-held', from }
  end
  if tag.kind == 'depot' then
    if location ~= nil and tags.depot_active_at(tag, location) then
      return { L .. 'details-depot-here', n }
    end
    if location == nil then
      return { L .. 'details-depot-flight' }
    end
    return { L .. 'details-depot-away', n, places_rich(tag.orbits) }
  end
  return { L .. 'details-none' }
end

--- Числа строки предмета: цели секций по предмету. Только для показа —
--- замки и транзит по-прежнему решает resolver.resolve на снимке.
local function item_totals(snap)
  local totals = {}
  for _, sec in ipairs(snap.sections) do
    local tag = sec.tag
    if sec.active and tag then
      for _, filter in ipairs(sec.filters) do
        local t = totals[filter.key]
        if not t then
          t = { reserve = 0, cargo = 0, depot = 0 }
          totals[filter.key] = t
        end
        local n = resolver.amount(filter, sec.multiplier)
        if tag.kind == 'reserve' then
          t.reserve = t.reserve + n
        elseif tag.kind == 'cargo' then
          t.cargo = t.cargo + n
        elseif tag.kind == 'depot' and tags.depot_active_at(tag, snap.location) then
          t.depot = t.depot + n
        end
      end
    end
  end
  return totals
end

--- Кому решатель разрешил отдачу: секции груза, открытые на этой орбите, —
--- как в resolver.resolve, причина удержания склада считается по нему же.
local function giving_keys(snap)
  local giving = {}
  for _, sec in ipairs(snap.sections) do
    local tag = sec.tag
    if sec.active and tag and tag.kind == 'cargo' and tag.dests ~= nil and tags.cargo_open_at(tag, snap.location) then
      for _, filter in ipairs(sec.filters) do
        giving[filter.key] = true
      end
    end
  end
  return giving
end

--- Почему предмет стоит: первая по порядку секций решателя, которая его
--- защищает, — запас, груз вне назначения, склад вне орбит или уступка
--- привезённому грузу.
local function held_reason(snap, key, giving, cargo_here)
  for _, sec in ipairs(snap.sections) do
    local tag = sec.tag
    if sec.active and tag then
      local has = false
      for _, filter in ipairs(sec.filters) do
        has = has or filter.key == key
      end
      if has then
        if tag.kind == 'reserve' then
          return 'details-st-held-reserve'
        end
        if tag.kind == 'cargo' and tag.dests ~= nil and not tags.cargo_open_at(tag, snap.location) then
          return 'details-st-held-cargo'
        end
        if tag.kind == 'depot' then
          if not tags.depot_active_at(tag, snap.location) then
            return 'details-st-held-depot'
          end
          if cargo_here[key] and not giving[key] then
            return 'details-st-held-yield'
          end
        end
      end
    end
  end
  return 'details-st-held-reserve'
end

--- Значок и строка «почему предмет едет или стоит» — по решению на снимке.
local function item_status(snap, result, key, giving, cargo_here)
  if result.transit[key] then
    return 'transit', { L .. 'details-st-transit' }
  end
  if result.locks[key] then
    return 'held', { L .. held_reason(snap, key, giving, cargo_here) }
  end
  return 'giving', { L .. 'details-st-giving' }
end

--- Строка одного предмета в деталях: значок статуса, фраза поведения и числа
--- «есть / свой запас / груз / склад / в пути / можно отдать» — ТЗ, раздел 8.
local function detail_row(container, line)
  local item_flow = container.add({ type = 'flow', direction = 'horizontal' })
  item_flow.add({
    type = 'sprite-button',
    sprite = 'item/' .. line.name,
    style = 'slot_button',
    number = line.count,
    tooltip = '[item=' .. line.name .. (line.quality and (',quality=' .. line.quality) or '') .. ']',
  }).style.size = 32
  local text = item_flow.add({ type = 'flow', direction = 'vertical' })
  local phrase = text.add({ type = 'label', caption = { '', icon(line.kind), line.phrase } })
  phrase.style.single_line = false
  phrase.style.maximal_width = 440
  local second = { '' }
  if line.status then
    second[#second + 1] = line.status
    second[#second + 1] = ' · '
  end
  second[#second + 1] = line.amounts
  local numbers = text.add({ type = 'label', caption = second })
  numbers.style.single_line = false
  numbers.style.maximal_width = 440
  numbers.style.font_color = { 0.7, 0.7, 0.7 }
end

local function detail_label(container, caption)
  local label = container.add({ type = 'label', caption = caption })
  label.style.single_line = false
  label.style.maximal_width = 440
  return label
end

--- Детали группы в «Группах»: свёрнуто — короткая строка статуса, как в
--- «Отдаче», развёрнуто — по строке на предмет с полным описанием поведения.
--- Контейнер перечитывается раз в секунду и раскрытость не сбрасывает:
--- раскрытость живёт в кнопке-треугольнике, а перестройка панели по
--- сигнатуре её сбрасывает — это осознанно.
local function fill_details(container, snap, result, cargo_here)
  container.clear()
  local index = container.tags.details
  local section
  for _, entry in ipairs(snap.sections) do
    if entry.index == index then
      section = entry
      break
    end
  end
  if section == nil then
    return
  end
  local location = snap.location
  local saved = storage.platforms and snap.platform and storage.platforms[snap.platform.index]
  local released = saved and saved.released or {}
  local row = container.parent
  local expander = find_named(row, 'shm_ol_expand')
  local expanded = (expander and expander.tags.expanded) == true
  local totals = item_totals(snap)
  local giving = giving_keys(snap)

  if section.tag then
    if not expanded then
      -- «Выключена до отлёта» — про секцию, которую держит мод и игрок не
      -- вернул; включённая обратно секция живёт по своей метке дальше.
      local held = released[section.group] ~= nil and section.vanilla_active ~= true
      local kind, caption = group_state(section.tag, location, held, snap_items(section))
      -- Секция выключена игроком (не модом): что бы ни обещала метка,
      -- секция ничего не делает — «выключена».
      if section.vanilla_active ~= true and not held then
        kind, caption = 'inactive', { L .. 'now-inactive' }
      end
      detail_label(container, { '', icon(kind), caption })
    else
      for _, filter in ipairs(section.filters) do
        local name, quality = own_section.split(filter.key)
        local kind, status = item_status(snap, result, filter.key, giving, cargo_here)
        local t = totals[filter.key]
        detail_row(container, {
          name = name,
          quality = quality,
          count = snap.contents[filter.key] or 0,
          kind = kind,
          phrase = item_phrase(section.tag, location, filter, section.multiplier),
          status = status,
          amounts = { L .. 'details-amounts',
            snap.contents[filter.key] or 0,
            t and t.reserve or 0,
            t and t.cargo or 0,
            t and t.depot or 0,
            snap.incoming[filter.key] or 0,
            (result.locks[filter.key] or result.transit[filter.key]) and { L .. 'details-no' } or { L .. 'details-yes' },
          },
        })
      end
    end
  else
    -- Секция без метки: ванильный груз описывается по своим фильтрам на
    -- орбитах со складом — там решатель ищет его для транзита (fact V-01a,
    -- entity `engine-space-platforms`).
    local on_depot_orbit = depot_orbit(snap.platform)
    local sources = {}
    for _, filter in ipairs(section.filters) do
      local source = filter.request_from or 'planet'
      if filter.import_from and source == 'planet' then
        sources[filter.import_from] = true
      end
    end
    if not expanded then
      if on_depot_orbit and next(sources) then
        local offered = location ~= nil
        for name in pairs(sources) do
          offered = offered and name ~= location
        end
        detail_label(container, { '', icon(offered and 'giving' or 'held'), { L .. 'details-cargo-vanilla', places_rich(sources) } })
      end
    else
      for _, filter in ipairs(section.filters) do
        local name, quality = own_section.split(filter.key)
        local source = filter.request_from or 'planet'
        local kind, status
        if result.locks[filter.key] then
          kind, status = 'held', { L .. held_reason(snap, filter.key, giving, cargo_here) }
        elseif filter.import_from and source == 'planet' and filter.import_from ~= location then
          kind, status = 'giving', { L .. 'details-st-giving' }
        elseif (filter.import_from and source == 'planet') or source ~= 'planet' then
          -- Импорт с текущей планеты — ещё наполняется; источник с
          -- платформами ваниль не отдаёт (V-01b).
          kind = 'held'
        else
          -- Запрос «Планета» без импорта отдаётся, как и без запроса (V-01a).
          kind, status = 'giving', { L .. 'details-st-giving' }
        end
        local phrase
        if on_depot_orbit then
          phrase = item_phrase(nil, location, filter, section.multiplier)
        else
          phrase = { L .. 'details-none' }
        end
        local t = totals[filter.key]
        detail_row(container, {
          name = name,
          quality = quality,
          count = snap.contents[filter.key] or 0,
          kind = kind,
          phrase = phrase,
          status = status,
          amounts = { L .. 'details-amounts',
            snap.contents[filter.key] or 0,
            t and t.reserve or 0,
            t and t.cargo or 0,
            t and t.depot or 0,
            snap.incoming[filter.key] or 0,
            (result.locks[filter.key] or result.transit[filter.key]) and { L .. 'details-no' } or { L .. 'details-yes' },
          },
        })
      end
    end
  end

  -- Выбранное, но не применённое назначение: строки «будет: …» до «Применить».
  local dropdown = find_named(row, 'shm_ol_purpose_' .. index)
  local places = find_named(row, 'shm_ol_places_' .. index)
  if dropdown and places then
    local kind = PURPOSES[dropdown.selected_index] or 'none'
    local chosen = tags.from_choice(kind, picker.text(picker.read(places)))
    if not same_tag(chosen, section.tag) then
      for _, filter in ipairs(section.filters) do
        detail_label(container, { L .. 'details-preview', item_phrase(chosen, location, filter, section.multiplier) })
      end
    end
  end
end

--- «Группы»: по строке на группу — треугольник деталей, имя, назначение,
--- места и «Применить»; под строкой — контейнер деталей, перечитываемый раз
--- в секунду. Секции с одинаковым именем группы — одна строка со счётчиком
--- ×N: представитель — активная секция, статусы и детали считаются по ней.
local function add_sections(scroll, hub)
  local snap = controller.snapshot(hub)
  local cargo_here = orbit_cargo(hub.surface.platform)
  local result = resolver.resolve(snap, cargo_here)
  local saved = storage.platforms and storage.platforms[hub.surface.platform.index]
  local buckets = {}
  local order = {}
  for _, section in ipairs(snap.sections) do
    -- Безымянные секции не сливаются: у каждой свой номер в имени строки.
    local key = section.group ~= '' and section.group or '#' .. section.index
    local bucket = buckets[key]
    if not bucket then
      bucket = { sections = {}, representative = section }
      buckets[key] = bucket
      order[#order + 1] = key
    end
    bucket.sections[#bucket.sections + 1] = section
    -- Представитель — секция с живой галочкой: у группы, чью секцию игрок
    -- включил обратно, статусы и детали считаются по ней.
    if bucket.representative.vanilla_active ~= true and section.vanilla_active then
      bucket.representative = section
    end
  end
  for _, key in ipairs(order) do
    local bucket = buckets[key]
    local section = bucket.representative
    local index = section.index
    local tag = section.tag
    local owner = line_of(hub.force, section.group)
    local locked = owner and { L .. 'section-of-line', owner.name } or nil
    local caption = section.group ~= '' and section.group or { L .. 'section-unnamed', index }
    if #bucket.sections > 1 then
      caption = { '', caption, ' ×' .. #bucket.sections }
    end
    local row = scroll.add({ type = 'flow', direction = 'vertical', name = 'shm_ol_row_' .. index })
    local table = row.add({ type = 'table', column_count = 5 })
    -- Треугольник у каждой строки: колонки строк выровнены, у группы с
    -- меткой развёрнутость показывает детали предметов.
    toggle_button(table, 'shm_ol_expand', false, { details = index })
    local label = table.add({ type = 'label', caption = caption, style = 'label' })
    label.style.maximal_width = 220
    label.style.minimal_width = 220
    -- Снятая галочка у группы груза — дело мода, а не поломка: подсказать.
    -- Вернувший галочку игрок включает секцию — метки «до отлёта» на ней быть
    -- не должно.
    if saved and saved.released and saved.released[section.group] and section.vanilla_active ~= true then
      label.caption = { '', caption, ' ', { L .. 'section-released-mark' } }
      label.tooltip = { L .. 'section-released' }
      label.style.font_color = { 1, 0.75, 0.3 }
    end
    local items = {}
    for i, purpose in ipairs(PURPOSES) do
      items[i] = { L .. 'purpose-' .. purpose }
    end
    table.add({
      type = 'drop-down',
      name = 'shm_ol_purpose_' .. index,
      items = items,
      selected_index = purpose_index(tag),
      tags = { section = index },
      enabled = locked == nil,
      tooltip = locked,
    })
    -- У запаса нет мест: пикер не показывается строкам с меткой запаса.
    if tag == nil or tag.kind ~= 'reserve' then
      picker.add(table, 'shm_ol_places_' .. index, hub.force, tag and (tag.dests or tag.orbits) or {}, {
        tooltip = locked or { L .. 'places-tooltip' },
        enabled = locked == nil,
      })
    end
    table.add({
      type = 'button',
      name = 'shm_ol_apply_' .. index,
      caption = { L .. 'apply' },
      tooltip = locked or { L .. 'apply-tooltip' },
      tags = { section = index },
      enabled = locked == nil,
    }).style.minimal_width = 100
    local container = row.add({
      type = 'flow',
      direction = 'vertical',
      name = 'shm_ol_details_' .. index,
      tags = { details = index },
    })
    fill_details(container, snap, result, cargo_here)
  end
end

function panel.build(player, entity)
  panel.destroy(player)
  local position = position_of(player)
  local wide = position == 'bottom' or position == 'top'
  local collapsed = is_collapsed(player.index)
  local cap = height_cap(player)
  local frame = player.gui.relative.add({
    type = 'frame',
    name = panel.NAME,
    caption = { L .. 'panel-title' },
    direction = (wide or collapsed) and 'horizontal' or 'vertical',
    anchor = { gui = anchor(entity), position = defines.relative_gui_position[position] },
    tags = {
      unit_number = entity.unit_number,
      collapsed = collapsed or nil,
      signature = (not collapsed and entity.type == 'space-platform-hub') and signature(entity) or nil,
    },
  })
  -- Кнопка сворачивания — первый элемент панели: слева в ряду, сверху в столбике.
  toggle_button(frame, 'shm_ol_toggle', not collapsed, { toggle = not collapsed })
  if collapsed then
    -- Свёрнутый вид: мини-окошко «Orbital Logistics» с кнопкой разворачивания.
    return frame
  end
  if not wide then
    frame.style.maximal_width = 560
  end
  if cap then
    frame.style.maximal_height = cap
    -- Потолок сжимает содержимое: без сжимаемости прокрутки блоки
    -- выталкивались бы за рамку.
    frame.style.vertically_squashable = true
  end
  local first = 0
  --- Блок панели: в ряду — свой столбец с разделителем, в столбике — свой
  --- поток. Тянется и сжимается по высоте, чтобы потолок рамки доходил
  --- до прокрутки внутри.
  local function block(name)
    if wide and first > 0 then
      frame.add({ type = 'line', direction = 'vertical' })
    end
    first = first + 1
    local container = frame.add({ type = 'flow', direction = 'vertical', name = name })
    if wide then
      container.style.right_padding = 8
      container.style.left_padding = 8
    end
    container.style.vertically_stretchable = true
    container.style.vertically_squashable = true
    return container
  end
  if entity.type == 'space-platform-hub' then
    -- «Группы»: предупреждения и секции.
    local sections_block = block('shm_ol_block_sections')
    if block_collapsed(player.index, 'sections') then
      collapsed_block(sections_block, 'sections', { L .. 'collapsed-sections', section_rows(entity) })
    else
      block_header(sections_block, 'sections', 'sections')
      local scroll = scroll_pane(sections_block, 'shm_ol_scroll_sections', cap)
      fill_warnings(scroll.add({ type = 'flow', name = 'shm_ol_warnings', direction = 'vertical' }), entity)
      add_sections(scroll, entity)
    end
    -- «Отдача на этой орбите».
    local now_block = block('shm_ol_block_now')
    if block_collapsed(player.index, 'now') then
      local rows, exceptions = now_data(entity)
      collapsed_block(now_block, 'now', { L .. 'collapsed-now', #rows, #exceptions })
    else
      block_header(now_block, 'now', 'now')
      local scroll = scroll_pane(now_block, 'shm_ol_scroll_now', cap)
      fill_now(scroll.add({ type = 'flow', name = 'shm_ol_now', direction = 'vertical' }), entity)
    end
  end
  -- «Линии»: пустой блок — одна кнопка, без заголовка и подписи «пока нет».
  local lines_block = block('shm_ol_block_lines')
  local member = lines.of_entity(player.force, entity)
  if #member == 0 and #lines.list(player.force) == 0 then
    lines_block.add({ type = 'button', name = 'shm_ol_open_lines', caption = { L .. 'lines-open' } }).style.minimal_width = 100
  elseif block_collapsed(player.index, 'lines') then
    collapsed_block(lines_block, 'lines', { L .. 'collapsed-lines', #member })
  else
    block_header(lines_block, 'lines', 'lines')
    add_lines(scroll_pane(lines_block, 'shm_ol_scroll_lines', cap), player, entity)
  end
  return frame
end

--- Игрок сменил положение панели — перестроить, если хаб открыт.
function panel.on_setting_changed(event)
  if event.setting ~= panel.POSITION_SETTING or not event.player_index then
    return
  end
  local player = game.get_player(event.player_index)
  local entity = player and player.opened
  if player.gui.relative[panel.NAME] and entity and entity.valid then
    panel.build(player, entity)
  end
end

local function opened_entity(player)
  local entity = player.opened
  if player.opened_gui_type == defines.gui_type.entity and entity and entity.valid
    and (entity.type == 'space-platform-hub' or entity.type == 'cargo-landing-pad') then
    return entity
  end
  return nil
end

function panel.on_opened(event)
  local player = game.get_player(event.player_index)
  local entity = player and opened_entity(player)
  if entity then
    panel.build(player, entity)
  end
end

--- Раз в секунду: группы изменились — перестроить панель, иначе обновить
--- только «Отдачу», предупреждения и детали групп, чтобы не сбивать выбор
--- в полях. Свёрнутая панель без обновлений; свёрнутый блок не имеет
--- контейнера, и его обновление пропускается.
function panel.refresh_all()
  for _, player in pairs(game.connected_players) do
    local frame = player.gui.relative[panel.NAME]
    local entity = frame and opened_entity(player)
    if entity and entity.type == 'space-platform-hub' and not frame.tags.collapsed then
      if frame.tags.signature ~= signature(entity) then
        panel.build(player, entity)
      else
        local now = find_named(frame, 'shm_ol_now')
        if now then
          fill_now(now, entity)
        end
        local warnings = find_named(frame, 'shm_ol_warnings')
        if warnings then
          fill_warnings(warnings, entity)
        end
        -- Детали групп: перечитать на свежем снимке; раскрытость остаётся,
        -- потому что контейнеры не пересоздаются.
        local details = collect_named(frame, 'shm_ol_details_')
        if #details > 0 then
          local snap = controller.snapshot(entity)
          local cargo_here = orbit_cargo(entity.surface.platform)
          local result = resolver.resolve(snap, cargo_here)
          for _, container in ipairs(details) do
            fill_details(container, snap, result, cargo_here)
          end
        end
      end
    end
  end
end

local function apply_purpose(player, entity, index)
  local frame = player.gui.relative[panel.NAME]
  local section = entity.get_logistic_sections().get_section(index)
  if not (frame and section and section.is_manual) then
    return
  end
  local purpose_element, places_element
  local function find(parent)
    for _, child in pairs(parent.children) do
      if child.name == 'shm_ol_purpose_' .. index then
        purpose_element = child
      elseif child.name == 'shm_ol_places_' .. index then
        places_element = child
      end
      find(child)
    end
  end
  find(frame)
  if not purpose_element then
    return
  end
  local kind = PURPOSES[purpose_element.selected_index] or 'none'
  -- У строки с меткой запаса пикера мест нет: пустой список мест.
  local places_text = places_element and picker.text(picker.read(places_element)) or ''
  local tag = tags.from_choice(kind, places_text)
  -- «Груз» без мест — поведение ванили, метка ничего не меняет: имя группы
  -- не трогаем вовсе, даже если [cargo] там уже стоит.
  if tag ~= nil and tag.kind == 'cargo' and tag.dests == nil then
    return
  end
  local fallback = (entity.surface.platform and entity.surface.platform.name or 'Hub') .. ' #' .. index
  local name = groups.name_for(section, tag, fallback)
  if section.group == '' and tag == nil then
    return
  end
  local ok, reason = groups.rename(player.force, section, name)
  if not ok then
    player.print({ L .. 'error-' .. reason })
  end
  controller.pass()
  panel.build(player, entity)
end

--- Нажатие в панели. Возвращает true, если событие её.
function panel.on_click(event, open_lines)
  local element = event.element
  if not (element and element.valid) then
    return false
  end
  local player = game.get_player(event.player_index)
  local entity = player and opened_entity(player)
  if element.name == 'shm_ol_toggle' then
    storage.panel_collapsed = storage.panel_collapsed or {}
    if element.tags.toggle then
      storage.panel_collapsed[event.player_index] = true
    else
      storage.panel_collapsed[event.player_index] = nil
    end
    if entity then
      panel.build(player, entity)
    end
    return true
  end
  -- Сворачивание блока: треугольник в заголовке или клик по строке-итогу.
  if element.name == 'shm_ol_block_toggle' or element.name == 'shm_ol_block_summary' then
    local key = element.tags.block
    if key then
      storage.panel_block_collapsed = storage.panel_block_collapsed or {}
      local state = storage.panel_block_collapsed[event.player_index] or {}
      if state[key] then
        state[key] = nil
      else
        state[key] = true
      end
      storage.panel_block_collapsed[event.player_index] = state
      if entity then
        panel.build(player, entity)
      end
      return true
    end
  end
  -- Разворачиватель деталей группы: состояние в самой кнопке, поэтому
  -- обновление раз в секунду его не сбрасывает, а перестройка панели — да.
  if element.name == 'shm_ol_expand' then
    local state = element.tags
    state.expanded = not state.expanded and true or nil
    element.tags = state
    local to_collapsed = state.expanded == true
    local path = to_collapsed and 'utility/collapse' or 'utility/expand'
    local key = to_collapsed and 'collapse' or 'expand'
    if element.type == 'sprite-button' and helpers.is_valid_sprite_path(path) then
      element.sprite = path
    else
      element.caption = { L .. key }
    end
    element.tooltip = { L .. key }
    if entity then
      local row = element.parent.parent
      local container = row and row['shm_ol_details_' .. state.details]
      if container then
        local snap = controller.snapshot(entity)
        local cargo_here = orbit_cargo(entity.surface.platform)
        local result = resolver.resolve(snap, cargo_here)
        fill_details(container, snap, result, cargo_here)
      end
    end
    return true
  end
  if string.sub(element.name, 1, 13) == 'shm_ol_apply_' then
    if entity then
      apply_purpose(player, entity, element.tags.section)
    end
    return true
  end
  if element.name == 'shm_ol_attach' then
    local dropdown = element.parent.shm_ol_attach_line
    local line = dropdown and lines.list(player.force)[dropdown.selected_index]
    if entity and line then
      lines.attach(player.force, line, entity)
      controller.pass()
      panel.build(player, entity)
      open_lines(player, line.id)
    end
    return true
  end
  if element.name == 'shm_ol_open_lines' then
    open_lines(player)
    return true
  end
  return false
end

return panel
