-- Окно обзора платформ: кнопка в левом верхнем углу экрана открывает
-- большое плавающее окно. Платформа — карточка: в заголовке имя (клик
-- открывает окно хаба) и маршрут иконками мест по ванильному расписанию —
-- планета, где платформа стоит, в рамке, перегоном полёта — активная
-- стрелка. Разворот карточки показывает настройки мода целиком: секции,
-- «Отдача на этой орбите» и линии снабжения. Панели у окна хаба больше
-- нет: это окно — единственное место настроек платформ. Решение владельца
-- 2026-11-05: контент карточки — на всю ширину окна, карточки по умолчанию
-- свёрнуты, окно скроллится целиком.

local tags = require('logic.tags')
local groups = require('runtime.groups')
local lines = require('runtime.lines')
local own_section = require('logic.own_section')
local resolver = require('logic.resolver')
local controller = require('runtime.controller')
local lines_gui = require('runtime.lines_gui')
local lines_logic = require('logic.lines')
local picker = require('runtime.places_picker')
local mod_gui = require('mod-gui')
local layout = require('logic.overview_layout')
local route_logic = require('logic.overview_route')

local overview = {}

overview.NAME = 'shm_ol_overview'
overview.BUTTON = 'shm_ol_overview_button'
local L = 'shm-orbital-logistics.'

local PURPOSES = { 'none', 'reserve', 'cargo', 'depot' }
local CARD_PREFIX = 'shm_ol_card_'
local WINDOW_SHARE = 0.6 --- ширина окна, доля экрана
local WINDOW_MIN = 760
local WINDOW_MAX = 1200
local WINDOW_HEIGHT_SHARE = 0.82
local SHIFT_WIDTH = 560  --- ширина окна, сдвинутого при открытом окне хаба

local function sized(element, width)
  element.style.width = width
  return element
end

local function block_width(element)
  return element.style.minimal_width - 2 * layout.BLOCK_PADDING
end

local function configure_scroll(scroll)
  -- Окно уже имеет рамку: у viewport не появляется ещё одна при overflow.
  scroll.style = 'naked_scroll_pane'
  scroll.horizontal_scroll_policy = 'never'
  scroll.vertical_scroll_policy = 'auto-and-reserve-space'
  scroll.style.padding = 0
  scroll.style.extra_padding_when_activated = 0
  scroll.style.horizontally_stretchable = true
  scroll.style.vertically_stretchable = true
  scroll.style.horizontally_squashable = true
end

-- ---------------------------------------------------------------- детали ---

local function purpose_index(tag)
  local kind = tag and tag.kind or 'none'
  for index, purpose in ipairs(PURPOSES) do
    if purpose == kind then
      return index
    end
  end
  return 1
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
--- space-location.
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
      -- Ванильная галочка: секция, выключенная игроком, ничего
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
  local width = flow.style.minimal_width
  local rows, exceptions = now_data(hub)
  if #rows == 0 then
    local label = flow.add({ type = 'label', caption = { L .. 'now-nothing' } })
    label.style.single_line = false
    label.style.maximal_width = width
    return
  end
  local groups_grid = flow.add({ type = 'table', column_count = 3 })
  groups_grid.style.cell_padding = 0
  groups_grid.style.horizontal_spacing = layout.GAP
  local name_width = math.floor((width - layout.ITEM - 2 * layout.GAP) / 2)
  local status_width = width - layout.ITEM - 2 * layout.GAP - name_width
  for column = 1, 3 do
    groups_grid.style.column_alignments[column] = 'top-left'
  end
  for _, row in ipairs(rows) do
    groups_grid.add({
      type = 'sprite-button',
      sprite = row.anchor and ('item/' .. row.anchor.name) or 'utility/questionmark',
      style = 'slot_button',
      tooltip = row.group,
    }).style.size = layout.ITEM
    local name = groups_grid.add({ type = 'label', caption = row.group })
    name.style.width = name_width
    name.style.font = 'default-semibold'
    name.tooltip = row.group
    local status = groups_grid.add({ type = 'label', caption = { '', icon(row.kind), row.caption } })
    status.style.single_line = false
    status.style.width = status_width
  end
  if #exceptions > 0 then
    flow.add({ type = 'label', caption = { L .. 'now-exceptions' }, style = 'caption_label' })
    local list = flow.add({ type = 'table', column_count = 2 })
    list.style.cell_padding = 0
    list.style.horizontal_spacing = layout.GAP
    for column = 1, 2 do
      list.style.column_alignments[column] = 'top-left'
    end
    local inventory = hub.get_inventory(defines.inventory.hub_main)
    local max_items = 0
    for _, entry in ipairs(exceptions) do max_items = math.max(max_items, #entry.items) end
    -- Таблица делит ширины колонок между всеми строками: бюджет общий,
    -- иначе максимумы от двух разных строк складываются в overflow.
    local widths = layout.exceptions(width, max_items)
    -- Одна строка на тип состояния: сетка иконок до 10 и «+N ещё», полный
    -- список предметов — в тултипе строки.
    for _, entry in ipairs(exceptions) do
      local cell = sized(list.add({ type = 'flow', direction = 'vertical' }), widths.icons)
      local grid = cell.add({ type = 'table', name = 'shm_ol_exception_grid', column_count = widths.columns })
      grid.style.cell_padding = 0
      grid.style.horizontal_spacing = layout.GAP
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
        }).style.size = layout.ITEM
      end
      if #entry.items > 10 then
        local more = cell.add({ type = 'label', name = 'shm_ol_exception_more', caption = { L .. 'now-more', #entry.items - 10 } })
        more.style.font_color = { 0.7, 0.7, 0.7 }
        more.style.single_line = false
        more.style.maximal_width = widths.icons
        more.tooltip = tooltip
      end
      local status = list.add({ type = 'label', caption = { '', icon(entry.kind), entry.text } })
      status.style.single_line = false
      status.style.width = widths.status
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
  label.style.maximal_width = flow.style.minimal_width
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
--- Столбец узкий: выпадающий список и кнопки в ряд, с ограниченной шириной.
local function add_lines(frame, player, entity, plat)
  local width = block_width(frame)
  local member = lines.of_entity(player.force, entity)
  for _, entry in ipairs(member) do
    local label = frame.add({ type = 'label', caption = { L .. 'lines-member', entry.line.name } })
    label.style.single_line = false
    label.style.maximal_width = width
  end
  local items = {}
  for i, line in ipairs(lines.list(player.force)) do
    items[i] = line.name
  end
  local flow = frame.add({ type = 'flow', direction = width < 260 and 'vertical' or 'horizontal' })
  local dropdown = flow.add({ type = 'drop-down', name = 'shm_ol_attach_line', items = items, selected_index = 1 })
  dropdown.style.width = math.min(150, width)
  local attach = flow.add({ type = 'button', name = 'shm_ol_attach', caption = { L .. 'lines-attach' }, tags = { card = plat } })
  attach.style.maximal_width = width < 260 and width or width - 150 - layout.GAP
  attach.tooltip = { L .. 'lines-attach' }
  local open = frame.add({ type = 'button', name = 'shm_ol_open_lines', caption = { L .. 'lines-open' } })
  open.style.maximal_width = width
  open.tooltip = { L .. 'lines-open' }
end

--- Отпечаток групп хаба: если игрок добавил, убрал, переименовал группу или
--- мод выключил её, контент карточки перестраивается целиком.
local function signature(entity)
  local parts = {}
  local sections = entity.get_logistic_sections()
  for index = 1, sections.sections_count do
    local section = sections.get_section(index)
    -- Служебная группа меняется с каждым замком — из-за неё не
    -- перестраиваем.
    if not controller.is_service(section.group) then
      parts[#parts + 1] = index .. ':' .. section.group .. ':' .. tostring(section.active) .. ':' .. section.filters_count
    end
  end
  return table.concat(parts, '|')
end

--- Отпечаток линий снабжения хаба: линии силы с числом участников и
--- участие хаба. Создание линии в окне линий перестраивает блок «Линии»
--- развёрнутых карточек.
local function lines_sig(force, hub)
  local parts = {}
  for _, line in ipairs(lines.list(force)) do
    parts[#parts + 1] = line.name .. '=' .. #line.participants
  end
  parts[#parts + 1] = #lines.of_entity(force, hub)
  return table.concat(parts, '|')
end

--- Отпечаток контента карточки: группы секций плюс линии снабжения.
local function content_sig(platform)
  return signature(platform.hub) .. '|' .. lines_sig(platform.force, platform.hub)
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
    button.style.size = layout.TOGGLE
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

--- Свёрнутость блока внутри карточки — на игрока, переживает сохранение
--- и загрузку само: storage сохраняется. Ключ — платформа и блок.
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

--- Ширина и высота экрана в GUI-единицах; nil, если данных дисплея нет.
local function gui_width_of(player)
  local resolution = player.display_resolution
  local scale = player.display_scale
  if not resolution or not scale or scale <= 0 then
    return nil
  end
  return resolution.width / scale
end

local function gui_height_of(player)
  local resolution = player.display_resolution
  local scale = player.display_scale
  if not resolution or not scale or scale <= 0 then
    return nil
  end
  return resolution.height / scale
end

--- Заголовок блока: треугольник сворачивания и название.
local function block_header(parent, plat, key, title_key)
  local header = parent.add({ type = 'flow', direction = 'horizontal', name = 'shm_ol_header_' .. key })
  toggle_button(header, 'shm_ol_block_toggle', true, { card = plat, block = key })
  local label = header.add({ type = 'label', caption = { L .. title_key }, style = 'caption_label' })
  label.style.single_line = false
  label.style.maximal_width = block_width(parent) - layout.TOGGLE - layout.GAP
end

--- Свёрнутый блок: строка-итог; клик по ней разворачивает. Треугольника
--- рядом нет — один итог (решение владельца 2026-11-05: пустой экспанд
--- лишний).
local function collapsed_block(parent, plat, key, summary)
  local button = parent.add({
    type = 'button',
    name = 'shm_ol_block_summary',
    caption = summary,
    tags = { card = plat, block = key },
  })
  button.style.width = block_width(parent)
  button.tooltip = summary
end

--- Поиск по имени на любой глубине: контейнеры «Отдачи», предупреждений и
--- деталей живут в потоках своих блоков.
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
--- «есть / свой запас / груз / склад / в пути / можно отдать». Ширина текста
--- под столбец «Групп» (~40% окна).
local function detail_row(container, line)
  local item_flow = container.add({ type = 'flow', direction = 'horizontal' })
  item_flow.add({
    type = 'sprite-button',
    sprite = 'item/' .. line.name,
    style = 'slot_button',
    number = line.count,
    tooltip = '[item=' .. line.name .. (line.quality and (',quality=' .. line.quality) or '') .. ']',
  }).style.size = layout.ITEM
  local text_width = container.style.minimal_width - layout.ITEM - layout.GAP
  local text = sized(item_flow.add({ type = 'flow', direction = 'vertical' }), text_width)
  local phrase = text.add({ type = 'label', caption = { '', icon(line.kind), line.phrase } })
  phrase.style.single_line = false
  phrase.style.maximal_width = text_width
  local second = { '' }
  if line.status then
    second[#second + 1] = line.status
    second[#second + 1] = ' · '
  end
  second[#second + 1] = line.amounts
  local numbers = text.add({ type = 'label', caption = second })
  numbers.style.single_line = false
  numbers.style.maximal_width = text_width
  numbers.style.font_color = { 0.7, 0.7, 0.7 }
end

local function detail_label(container, caption)
  local label = container.add({ type = 'label', caption = caption })
  label.style.single_line = false
  label.style.maximal_width = container.style.minimal_width
  return label
end

--- Детали группы в «Группах»: свёрнуто — короткая строка статуса, как в
--- «Отдаче», развёрнуто — по строке на предмет с полным описанием поведения.
--- Контейнер перечитывается раз в секунду и раскрытость не сбрасывает:
--- раскрытость живёт в кнопке-треугольнике, а перестройка контента карточки
--- по сигнатуре её сбрасывает — это осознанно.
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
      else
        -- Стабильная строка вместо пустоты: высота строк групп не пляшет,
        -- когда склад прилетает и улетает с орбиты (замечание владельца
        -- 2026-11-05 про «пляшущий» контент).
        detail_label(container, { L .. 'details-none' })
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
  local plat = container.tags.card
  local dropdown = find_named(row, 'shm_ol_purpose_' .. plat .. '_' .. index)
  local places = find_named(row, 'shm_ol_places_' .. plat .. '_' .. index)
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
--- места; под строкой — контейнер деталей, перечитываемый раз в секунду.
--- Секции с одинаковым именем группы — одна строка со счётчиком ×N:
--- представитель — активная секция, статусы и детали считаются по ней.
local function add_sections(parent, hub, plat)
  local width = block_width(parent)
  local row_layout = layout.section_row(width)
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
    local row = sized(parent.add({ type = 'flow', direction = 'vertical', name = 'shm_ol_row_' .. plat .. '_' .. index }), width)
    local grid = row.add({ type = 'table', column_count = row_layout.below and 2 or 4 })
    grid.style.cell_padding = 0
    grid.style.horizontal_spacing = layout.GAP
    for column = 1, grid.column_count do grid.style.column_alignments[column] = 'top-left' end
    -- Треугольник у каждой строки: колонки строк выровнены, у группы с
    -- меткой развёрнутость показывает детали предметов.
    toggle_button(grid, 'shm_ol_expand', false, { card = plat, details = index })
    local label = grid.add({ type = 'label', caption = caption, style = 'label' })
    label.style.width = row_layout.name
    label.tooltip = caption
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
    local controls = row_layout.below and row.add({ type = 'flow', direction = 'horizontal' }) or grid
    local dropdown = controls.add({
      type = 'drop-down',
      name = 'shm_ol_purpose_' .. plat .. '_' .. index,
      items = items,
      selected_index = purpose_index(tag),
      tags = { card = plat, section = index },
      enabled = locked == nil,
      tooltip = locked,
    })
    dropdown.style.width = layout.PURPOSE
    -- У запаса нет мест: пикер не показывается строкам с меткой запаса.
    if tag == nil or tag.kind ~= 'reserve' then
      local places = picker.add(controls, 'shm_ol_places_' .. plat .. '_' .. index, hub.force, tag and (tag.dests or tag.orbits) or {}, {
        tooltip = locked or { L .. 'places-tooltip' },
        enabled = locked == nil,
        columns = row_layout.places,
      })
      places.style.width = row_layout.picker
    end
    local container = row.add({
      type = 'flow',
      direction = 'vertical',
      name = 'shm_ol_details_' .. plat .. '_' .. index,
      tags = { card = plat, details = index },
    })
    container.style.width = width
    fill_details(container, snap, result, cargo_here)
  end
end

-- ------------------------------------------------------ платформы и окно ---

--- Живые платформы силы: с хабом и без пометки на удаление.
local function platforms_of(force)
  local list = {}
  for _, platform in pairs(force.platforms) do
    if platform.valid and platform.hub and platform.hub.valid and platform.scheduled_for_deletion == 0 then
      list[#list + 1] = platform
    end
  end
  table.sort(list, function(a, b) return a.index < b.index end)
  return list
end

local function platform_of(player, index)
  if index == nil then
    return nil
  end
  local platform = player.force.platforms[index]
  if platform and platform.valid and platform.hub and platform.hub.valid and platform.scheduled_for_deletion == 0 then
    return platform
  end
  return nil
end

--- Карточка платформы: подъём от любого элемента внутри неё.
local function card_of(element)
  local current = element
  while current and current.valid do
    local name = current.name
    if type(name) == 'string' and string.sub(name, 1, #CARD_PREFIX) == CARD_PREFIX then
      return current
    end
    current = current.parent
  end
  return nil
end

--- Окно хаба открывается только из удалённого вида: у персонажа на планете
--- чужая поверхность молча не открывается (vanilla открывает платформы из
--- вида карты). Из персонажа — войти в удалённый вид поверхности платформы,
--- как по клику на платформу в карте.
local function open_platform_gui(player, hub)
  if player.controller_type == defines.controllers.character then
    player.set_controller({ type = defines.controllers.remote, surface = hub.surface, position = hub.position })
  end
  player.opened = hub
end

--- PlatformSchedule — снимок {current, records}, не массив записей.
local function route_model(platform, old)
  local stops = {}
  local schedule = platform.schedule
  for index, record in ipairs(schedule and schedule.records or {}) do
    stops[index] = record.station or '?'
  end
  local location = platform.space_location
  local connection = platform.space_connection
  local last = platform.last_visited_space_location
  local from, to
  if connection and last then
    -- Концы прототипа связи фиксированы и при обратном рейсе не меняются.
    if last.name == connection.from.name then
      from, to = last.name, connection.to.name
    elseif last.name == connection.to.name then
      from, to = last.name, connection.from.name
    end
  end
  local records_signature = helpers.table_to_json(stops)
  local departure = old.records_signature == records_signature and old.departure or nil
  local model = route_logic.build(stops, schedule and schedule.current, location and location.name, from, to, departure)
  if location then departure = model.active_stop end
  return model, records_signature, departure
end

--- Полная петля расписания. Состав перестраивается только при изменении
--- остановок/числа колонок; стоянка и полёт меняют оформление существующих узлов.
local function fill_route(flow, platform)
  local card = card_of(flow)
  local widths = layout.route(card.style.minimal_width)
  flow.style.width = widths.width
  local old = flow.tags
  local model, records_signature, departure = route_model(platform, old)
  local signature = helpers.table_to_json({ 2, model.stops, model.loop, widths.columns })
  local rebuild = old.signature ~= signature
  if rebuild then
    flow.clear()
    if #model.stops == 0 then
      flow.add({ type = 'sprite', sprite = 'utility/questionmark', tooltip = { L .. 'route-none' } }).style.size = layout.ROUTE_PLANET
    else
      local grid = flow.add({ type = 'table', column_count = widths.columns })
      grid.style.cell_padding = 0
      grid.style.horizontal_spacing = layout.GAP
      for index in ipairs(model.stops) do
        local cell = sized(grid.add({ type = 'flow', direction = 'horizontal' }), widths.cell)
        cell.style.height = layout.ROUTE_PLANET
        cell.style.horizontal_spacing = layout.GAP
        cell.style.vertical_align = 'center'
        cell.add({ type = 'sprite-button', name = 'shm_ol_route_planet', tags = { route_stop = index } }).style.size = layout.ROUTE_PLANET
        if index < #model.stops or model.loop then
          local loop = index == #model.stops
          local arrow = cell.add({ type = 'sprite', name = 'shm_ol_route_arrow', tags = { route_leg = index, route_loop = loop } })
          arrow.resize_to_sprite = false
          arrow.style.width = layout.ROUTE_ARROW
          arrow.style.height = loop and layout.ROUTE_ARROW or 10
          arrow.style.stretch_image_to_widget_size = true
        end
      end
    end
  end
  if not rebuild and old.active_stop == model.active_stop and old.active_leg == model.active_leg and old.departure == departure then return end
  if #model.stops > 0 then
    for index, cell in ipairs(flow.children[1].children) do
      local name = model.stops[index]
      local here = model.active_stop == index
      local prototype = prototypes.space_location[name]
      local button = cell.children[1]
      button.sprite = prototype and ('space-location/' .. name) or 'utility/questionmark'
      button.style = here and 'shm_ol_route_planet_active' or 'slot_button'
      button.style.size = layout.ROUTE_PLANET
      button.tooltip = here and { '', prototype and prototype.localised_name or name, '\n', { L .. 'route-here' } }
        or (prototype and prototype.localised_name or name)
      local arrow = cell.children[2]
      if arrow then
        local active = model.active_leg == index
        local target = model.stops[index % #model.stops + 1]
        local sprite = arrow.tags.route_loop and 'shm-ol-route-loop' or 'shm-ol-route-arrow'
        arrow.sprite = sprite .. (active and '-active' or '')
        arrow.tooltip = active and { L .. 'route-flying', place_link(name), place_link(target) }
          or { '', place_link(name), ' → ', place_link(target) }
      end
    end
  end
  flow.tags = { signature = signature, records_signature = records_signature, departure = departure,
    active_stop = model.active_stop, active_leg = model.active_leg }
end

--- Обновить один блок, не уничтожая соседние поля и раскрытые детали.
local function fill_block(container, player, platform, key)
  container.clear()
  local hub, plat = platform.hub, platform.index
  local width = block_width(container)
  if key == 'sections' then
    if block_collapsed(player.index, plat .. ':sections') then
      collapsed_block(container, plat, key, { L .. 'collapsed-sections', section_rows(hub) })
    else
      block_header(container, plat, key, 'sections')
      local warnings = sized(container.add({ type = 'flow', name = 'shm_ol_warnings', direction = 'vertical' }), width)
      fill_warnings(warnings, hub)
      add_sections(container, hub, plat)
    end
  elseif key == 'now' then
    if block_collapsed(player.index, plat .. ':now') then
      local rows, exceptions = now_data(hub)
      collapsed_block(container, plat, key, { L .. 'collapsed-now', #rows, #exceptions })
    else
      block_header(container, plat, key, 'now')
      fill_now(sized(container.add({ type = 'flow', name = 'shm_ol_now', direction = 'vertical' }), width), hub)
    end
  elseif key == 'lines' then
    local member = lines.of_entity(player.force, hub)
    if #member == 0 and #lines.list(player.force) == 0 then
      local button = container.add({ type = 'button', name = 'shm_ol_open_lines', caption = { L .. 'lines-open' } })
      button.style.maximal_width = width
      button.tooltip = { L .. 'lines-open' }
    elseif block_collapsed(player.index, plat .. ':lines') then
      collapsed_block(container, plat, key, { L .. 'collapsed-lines', #member })
    else
      block_header(container, plat, key, 'lines')
      add_lines(container, player, hub, plat)
    end
  end
end

--- Контент карточки: три столбца — «Группы», «Отдача на этой орбите»,
--- «Линии» (решение владельца 2026-11-05). Высота по содержимому: целиком
--- скроллит окно, у блоков своих прокруток нет. Ширина окна делится между
--- столбцами в фиксированных долях.
local function fill_content(card, player, platform)
  local frame = card.parent
  while frame and frame.valid and frame.name ~= overview.NAME do
    frame = frame.parent
  end
  local width = (frame and frame.valid and frame.style.minimal_width) or 1100
  local widths = layout.widths(width)
  local content = sized(card.add({ type = 'flow', name = 'shm_ol_content', direction = 'horizontal' }), widths.content)
  content.style.horizontal_spacing = layout.GAP
  local separated = false
  local function block(name, block_width)
    if separated then
      local divider = content.add({ type = 'line', direction = 'vertical' })
      divider.style.width = layout.DIVIDER
    end
    separated = true
    local container = content.add({ type = 'flow', direction = 'vertical', name = name })
    container.style.width = block_width
    container.style.left_padding = layout.BLOCK_PADDING
    container.style.right_padding = layout.BLOCK_PADDING
    return container
  end
  -- «Группы»: предупреждения и секции.
  fill_block(block('shm_ol_block_sections', widths.sections), player, platform, 'sections')
  -- «Отдача на этой орбите».
  fill_block(block('shm_ol_block_now', widths.now), player, platform, 'now')
  -- «Линии»: пустой блок — одна кнопка, без заголовка и подписи «пока нет».
  fill_block(block('shm_ol_block_lines', widths.lines), player, platform, 'lines')
end

--- Пересобрать контент карточки: разворот, смена групп, применение метки.
local function rebuild_content(card, player, platform)
  local old = find_named(card, 'shm_ol_content')
  if old then
    old.destroy()
  end
  fill_content(card, player, platform)
  local t = card.tags
  t.signature = content_sig(platform)
  card.tags = t
end

--- Карточка платформы: рамка с заголовком — треугольник разворота, значок и
--- имя (клик открывает окно хаба) и маршрут.
local function add_card(cards, player, platform)
  local plat = platform.index
  local card = cards.add({
    type = 'frame',
    name = CARD_PREFIX .. plat,
    style = 'inside_shallow_frame_with_padding',
    direction = 'vertical',
    tags = { card = plat },
  })
  card.style.width = cards.style.minimal_width
  card.style.padding = layout.CARD_PADDING
  local header = card.add({ type = 'flow', direction = 'horizontal' })
  header.style.horizontal_spacing = layout.GAP
  header.style.vertical_align = 'center'
  toggle_button(header, 'shm_ol_card_toggle', false, { card = plat })
  local tooltip = { L .. 'card-open', platform.name }
  local open_icon = header.add({
    type = 'sprite-button',
    name = 'shm_ol_card_icon',
    sprite = 'item/space-platform-hub',
    style = 'slot_button',
    tooltip = tooltip,
    tags = { card = plat },
  })
  open_icon.style.size = layout.CARD_ICON
  local open_button = header.add({
    type = 'button',
    name = 'shm_ol_card_open',
    caption = platform.name,
    tooltip = tooltip,
    tags = { card = plat },
  })
  open_button.style.width = layout.NAME
  open_button.style.horizontal_align = 'left'
  local route = header.add({ type = 'flow', name = 'shm_ol_route', direction = 'horizontal' })
  route.style.horizontally_stretchable = true
  route.style.vertical_align = 'center'
  fill_route(route, platform)
  return card
end

function overview.ensure_button(player)
  -- Сохранения до mod-gui содержат отдельную кнопку прямо в gui.top.
  -- Общую рамку и кнопки других модов не трогаем.
  local legacy = player.gui.top[overview.BUTTON]
  if legacy and legacy.get_mod() == script.mod_name then
    legacy.destroy()
  end
  local flow = mod_gui.get_button_flow(player)
  local button = flow[overview.BUTTON]
  if button == nil then
    button = flow.add({
      type = 'sprite-button',
      name = overview.BUTTON,
      sprite = 'shm-ol-gui-button',
    })
  end
  -- Присваивание стиля сбрасывает и старые runtime overrides размеров.
  button.style = 'shm_ol_mod_button'
  button.style.size = 37
  button.style.padding = -2
  button.sprite = 'shm-ol-gui-button'
  button.tooltip = { L .. 'overview-open' }
  return button
end

--- Список карточек по живым платформам силы; окно с размером «как helmod» —
--- большая доля экрана, целиком скроллится.
function overview.open(player)
  overview.close(player)
  local frame = player.gui.screen.add({
    type = 'frame',
    name = overview.NAME,
    direction = 'vertical',
    tags = { layout_version = layout.VERSION },
  })
  frame.style.left_padding = layout.FRAME_PADDING
  frame.style.right_padding = layout.FRAME_PADDING
  local title = frame.add({ type = 'flow', direction = 'horizontal' })
  title.add({ type = 'label', caption = { L .. 'panel-title' }, style = 'frame_title' })
  local drag = title.add({ type = 'empty-widget', style = 'draggable_space_header' })
  drag.style.horizontally_stretchable = true
  drag.style.height = 24
  drag.drag_target = frame
  title.add({
    type = 'sprite-button',
    name = 'shm_ol_overview_close',
    sprite = 'utility/close',
    style = 'frame_action_button',
    tooltip = { L .. 'overview-close' },
  })
  local scroll = frame.add({
    type = 'scroll-pane', name = 'shm_ol_overview_scroll', direction = 'vertical',
    horizontal_scroll_policy = 'never', vertical_scroll_policy = 'auto-and-reserve-space',
  })
  configure_scroll(scroll)
  local cards = scroll.add({ type = 'flow', name = 'shm_ol_cards', direction = 'vertical' })
  cards.style.horizontally_stretchable = true
  cards.style.vertical_spacing = 6
  local width = gui_width_of(player)
  local height = gui_height_of(player)
  if width and height then
    local frame_width = math.floor(math.max(WINDOW_MIN, math.min(WINDOW_MAX, width * WINDOW_SHARE)))
    local frame_height = math.floor(height * WINDOW_HEIGHT_SHARE)
    frame.style.minimal_width = frame_width
    frame.style.maximal_width = frame_width
    frame.style.minimal_height = frame_height
    frame.style.maximal_height = frame_height
    frame.force_auto_center()
  end
  overview.fill_cards(player, frame)
  return frame
end

--- Список карточек заново: по живым платформам. Пусто — одна подпись.
function overview.fill_cards(player, frame)
  local scroll = find_named(frame, 'shm_ol_overview_scroll')
  if not scroll then
    return
  end
  local cards = find_named(scroll, 'shm_ol_cards')
  cards.style.width = layout.widths(frame.style.minimal_width).cards
  cards.clear()
  local list = platforms_of(player.force)
  local indices = {}
  for _, platform in ipairs(list) do
    indices[#indices + 1] = platform.index
    add_card(cards, player, platform)
  end
  if #list == 0 then
    cards.add({ type = 'label', caption = { L .. 'overview-empty' } })
  end
  -- Сдвиг окна при открытом хабе и его прежнее место не теряются.
  local t = frame.tags or {}
  t.setsig = table.concat(indices, ',')
  frame.tags = t
end

--- Ширина меняется только при намеренном открытии/закрытии окна хаба.
local function resize_cards(player, frame)
  local cards = find_named(frame, 'shm_ol_cards')
  if not cards then return end
  local width = layout.widths(frame.style.minimal_width).cards
  cards.style.width = width
  for _, card in ipairs(cards.children) do
    if card.tags.card then
      card.style.width = width
      card.style.padding = layout.CARD_PADDING
      local route = find_named(card, 'shm_ol_route')
      local platform = platform_of(player, card.tags.card)
      if platform and route then fill_route(route, platform) end
      if platform and card.tags.expanded then rebuild_content(card, player, platform) end
    end
  end
end

function overview.close(player)
  local existing = player.gui.screen[overview.NAME]
  if existing then
    existing.destroy()
  end
end

function overview.toggle(player)
  if player.gui.screen[overview.NAME] then
    overview.close(player)
  else
    overview.open(player)
  end
end

--- Раз в секунду: состав платформ изменился — пересобрать список карточек;
--- структура маршрута по отпечатку, его подсветка без пересоздания элементов;
--- контент развёрнутой карточки по сигнатуре групп,
--- иначе перечитать «Отдачу», предупреждения и детали групп.
function overview.refresh_all()
  for _, player in pairs(game.connected_players) do
    -- Рабочая копия сохраняет номер до релиза: обычная загрузка не обязана
    -- вызвать on_configuration_changed. Ремонтируем кнопку и без открытого окна.
    overview.ensure_button(player)
    local frame = player.gui.screen[overview.NAME]
    if frame then
      -- Номер пакета до релиза не меняется: открытый GUI из сохранения
      -- ремонтируется один раз без пересоздания окна и заголовков карточек.
      if frame.tags.layout_version ~= layout.VERSION then
        frame.style.left_padding = layout.FRAME_PADDING
        frame.style.right_padding = layout.FRAME_PADDING
        configure_scroll(find_named(frame, 'shm_ol_overview_scroll'))
        resize_cards(player, frame)
        local state = frame.tags
        state.layout_version = layout.VERSION
        frame.tags = state
      end
      local list = platforms_of(player.force)
      local indices = {}
      for _, platform in ipairs(list) do
        indices[#indices + 1] = platform.index
      end
      local setsig = table.concat(indices, ',')
      if frame.tags.setsig ~= setsig then
        overview.fill_cards(player, frame)
      else
        local cards = find_named(frame, 'shm_ol_cards')
        for _, card in ipairs(cards.children) do
          local t = card.tags
          if card.valid and t and t.card ~= nil then
            local platform = platform_of(player, t.card)
            if platform then
              local hub = platform.hub
              local route = find_named(card, 'shm_ol_route')
              if route then fill_route(route, platform) end
              if t.expanded then
                local sig = content_sig(platform)
                if t.signature ~= sig then
                  rebuild_content(card, player, platform)
                else
                  local now = find_named(card, 'shm_ol_now')
                  if now then
                    fill_now(now, hub)
                  end
                  local warnings = find_named(card, 'shm_ol_warnings')
                  if warnings then
                    fill_warnings(warnings, hub)
                  end
                  local details = collect_named(card, 'shm_ol_details_')
                  if #details > 0 then
                    local snap = controller.snapshot(hub)
                    local cargo_here = orbit_cargo(hub.surface.platform)
                    local result = resolver.resolve(snap, cargo_here)
                    for _, container in ipairs(details) do
                      fill_details(container, snap, result, cargo_here)
                    end
                  end
                end
              end
            end
          end
        end
      end
    end
  end
end

-- --------------------------------------------------------------- события ---

--- Стоянка может быть короче секундного refresh. Запомнить её и обновить
--- только маршрут этой платформы на самом событии, не теряя источник рейса.
function overview.on_platform_changed(event)
  local platform = event.platform
  if not (platform and platform.valid and platform.hub and platform.hub.valid and platform.scheduled_for_deletion == 0) then return end
  for _, player in pairs(game.connected_players) do
    if player.force == platform.force then
      local frame = player.gui.screen[overview.NAME]
      local card = frame and find_named(frame, CARD_PREFIX .. platform.index)
      local route = card and find_named(card, 'shm_ol_route')
      if route then fill_route(route, platform) end
    end
  end
end

--- Окно хаба или площадки открылось: окно обзора — налево и поуже, чтобы не
--- накрывать ванильное окно: экранные окна модов рисуются поверх игровых.
--- Позиция запоминается — по закрытию окна хаба вернётся.
function overview.on_opened(event)
  local player = game.get_player(event.player_index)
  local frame = player and player.gui.screen[overview.NAME]
  if not frame then
    return
  end
  local entity = player.opened
  if player.opened_gui_type ~= defines.gui_type.entity or not (entity and entity.valid)
    or (entity.type ~= 'space-platform-hub' and entity.type ~= 'cargo-landing-pad') then
    return
  end
  local t = frame.tags
  if not t.shifted then
    local location = frame.location
    t.shifted = true
    t.restore_x = location.x
    t.restore_y = location.y
    t.restore_w = frame.style.minimal_width
    frame.tags = t
    local height = gui_height_of(player)
    frame.style.minimal_width = SHIFT_WIDTH
    frame.style.maximal_width = SHIFT_WIDTH
    if height then
      local shifted_height = math.floor(height * 0.8)
      frame.style.minimal_height = shifted_height
      frame.style.maximal_height = shifted_height
      frame.location = { x = 0, y = math.max(0, math.floor((height - shifted_height) / 2)) }
    else
      frame.location = { x = 0, y = 0 }
    end
    resize_cards(player, frame)
  end
end

--- Окно хаба закрылось — окну обзора его прежний размер и место.
function overview.on_closed(event)
  if event.gui_type ~= defines.gui_type.entity then
    return
  end
  local player = game.get_player(event.player_index)
  local frame = player and player.gui.screen[overview.NAME]
  if not frame then
    return
  end
  local t = frame.tags
  if t.shifted then
    if t.restore_w then
      frame.style.minimal_width = t.restore_w
      frame.style.maximal_width = t.restore_w
    end
    frame.location = { x = t.restore_x or 0, y = t.restore_y or 0 }
    t.shifted = nil
    t.restore_x = nil
    t.restore_y = nil
    t.restore_w = nil
    frame.tags = t
    resize_cards(player, frame)
  end
end

--- Применить выбор назначения строки секции: метка уходит в имя группы,
--- контент карточки пересобирается по новой сигнатуре.
local function apply_purpose(player, platform, index)
  local hub = platform.hub
  local plat = platform.index
  local card = find_named(player.gui.screen[overview.NAME], CARD_PREFIX .. plat)
  if not card then
    return
  end
  local section = hub.get_logistic_sections().get_section(index)
  if not (section and section.is_manual) then
    return
  end
  local purpose_element = find_named(card, 'shm_ol_purpose_' .. plat .. '_' .. index)
  local places_element = find_named(card, 'shm_ol_places_' .. plat .. '_' .. index)
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
  local fallback = (hub.surface.platform and hub.surface.platform.name or 'Hub') .. ' #' .. index
  local name = groups.name_for(section, tag, fallback)
  if section.group == '' and tag == nil then
    return
  end
  local ok, reason = groups.rename(player.force, section, name)
  if not ok then
    player.print({ L .. 'error-' .. reason })
  end
  controller.pass()
  rebuild_content(card, player, platform)
end

--- Места строки секции: событие внутри потока «shm_ol_places_<плат>_<N>».
local function places_row(event)
  local element = event.element
  if not (element and element.valid) then
    return nil, nil
  end
  local parent = element.parent
  if not (parent and parent.valid) then
    return nil, nil
  end
  local plat, index = string.match(parent.name, '^shm_ol_places_(%d+)_(%d+)$')
  return tonumber(plat), tonumber(index), parent
end

--- Селектор назначения строки: применяется сразу. Возвращает true, если
--- событие её.
function overview.on_selection(event)
  local element = event.element
  if not (element and element.valid) or not (element.tags and element.tags.card) then
    return false
  end
  if type(element.name) ~= 'string' or string.sub(element.name, 1, 15) ~= 'shm_ol_purpose_' then
    return false
  end
  local player = game.get_player(event.player_index)
  local platform = player and platform_of(player, element.tags.card)
  if platform then
    apply_purpose(player, platform, element.tags.section)
  end
  return true
end

--- Место добавлено из окна выбора: дополнить выбор и применить. Внимание:
--- elem_value у space-location — строка, не таблица.
function overview.on_elem_changed(event)
  local element = event.element
  if not (element and element.valid) or not (element.tags and element.tags.picker_add) then
    return false
  end
  local plat, index, flow = places_row(event)
  if not plat then
    return false
  end
  local value = element.elem_value
  local name = type(value) == 'table' and value.name or value
  if not name then
    return true
  end
  local selected = {}
  for _, place in ipairs(flow.tags.selected or {}) do
    selected[place] = true
  end
  selected[name] = true
  local names = {}
  for place in pairs(selected) do
    names[#names + 1] = place
  end
  table.sort(names)
  picker.set_selected(flow, names)
  local player = game.get_player(event.player_index)
  local platform = player and platform_of(player, plat)
  if player and platform then
    apply_purpose(player, platform, index)
  end
  return true
end

--- Нажатия в окне обзора. Возвращает true, если событие его.
function overview.on_click(event)
  local element = event.element
  if not (element and element.valid) then
    return false
  end
  local name = element.name
  if name == overview.BUTTON then
    local player = game.get_player(event.player_index)
    if player then
      overview.toggle(player)
    end
    return true
  end
  if name == 'shm_ol_overview_close' then
    local player = game.get_player(event.player_index)
    if player then
      overview.close(player)
    end
    return true
  end
  local player = game.get_player(event.player_index)
  -- Убрать место из выбора строки секции: иконки мест, применить сразу.
  if element.tags and element.tags.picker_remove then
    local parent = element.parent
    local plat, index
    if parent and parent.valid then
      plat, index = string.match(parent.name, '^shm_ol_places_(%d+)_(%d+)$')
    end
    if plat then
      plat = tonumber(plat)
      index = tonumber(index)
      local selected = {}
      for _, place in ipairs(parent.tags.selected or {}) do
        if place ~= element.tags.picker_remove then
          selected[#selected + 1] = place
        end
      end
      picker.set_selected(parent, selected)
      local platform = player and platform_of(player, plat)
      if player and platform then
        apply_purpose(player, platform, index)
      end
      return true
    end
  end
  if not player then
    return false
  end
  -- Кнопка окна: значок и имя карточки открывают окно хаба платформы.
  if name == 'shm_ol_card_open' or name == 'shm_ol_card_icon' then
    local platform = platform_of(player, element.tags and element.tags.card)
    if platform then
      open_platform_gui(player, platform.hub)
    end
    return true
  end
  -- Разворот карточки: контент настроек появляется и убирается целиком.
  if name == 'shm_ol_card_toggle' then
    local card = element.parent and element.parent.parent
    local platform = platform_of(player, element.tags and element.tags.card)
    if card and card.valid and platform then
      local t = card.tags
      local expanded = t.expanded == true
      if expanded then
        local content = find_named(card, 'shm_ol_content')
        if content then
          content.destroy()
        end
        t.expanded = nil
      else
        t.expanded = true
        card.tags = t
        fill_content(card, player, platform)
        t = card.tags
      end
      t.signature = expanded and nil or content_sig(platform)
      card.tags = t
      local to_collapsed = not expanded
      local path = to_collapsed and 'utility/collapse' or 'utility/expand'
      local key = to_collapsed and 'collapse' or 'expand'
      if element.type == 'sprite-button' and helpers.is_valid_sprite_path(path) then
        element.sprite = path
      else
        element.caption = { L .. key }
      end
      element.tooltip = { L .. key }
    end
    return true
  end
  -- Сворачивание блока внутри карточки: треугольник или строка-итог.
  if name == 'shm_ol_block_toggle' or name == 'shm_ol_block_summary' then
    local t = element.tags
    if t and t.block and t.card then
      storage.panel_block_collapsed = storage.panel_block_collapsed or {}
      local state = storage.panel_block_collapsed[event.player_index] or {}
      local key = t.card .. ':' .. t.block
      if state[key] then
        state[key] = nil
      else
        state[key] = true
      end
      storage.panel_block_collapsed[event.player_index] = state
      local platform = platform_of(player, t.card)
      local card = card_of(element)
      if platform and card then
        local block = find_named(card, 'shm_ol_block_' .. t.block)
        if block then fill_block(block, player, platform, t.block) end
      end
      return true
    end
  end
  -- Разворачиватель деталей группы: состояние в самой кнопке, поэтому
  -- обновление раз в секунду его не сбрасывает, а перестройка контента — да.
  if name == 'shm_ol_expand' then
    local t = element.tags
    t.expanded = not t.expanded and true or nil
    element.tags = t
    local to_collapsed = t.expanded == true
    local path = to_collapsed and 'utility/collapse' or 'utility/expand'
    local key = to_collapsed and 'collapse' or 'expand'
    if element.type == 'sprite-button' and helpers.is_valid_sprite_path(path) then
      element.sprite = path
    else
      element.caption = { L .. key }
    end
    element.tooltip = { L .. key }
    local platform = platform_of(player, t.card)
    if platform then
      local row = element.parent.parent
      local container = row and row['shm_ol_details_' .. t.card .. '_' .. t.details]
      if container then
        local hub = platform.hub
        local snap = controller.snapshot(hub)
        local cargo_here = orbit_cargo(hub.surface.platform)
        local result = resolver.resolve(snap, cargo_here)
        fill_details(container, snap, result, cargo_here)
      end
    end
    return true
  end
  if name == 'shm_ol_attach' then
    local dropdown = element.parent and element.parent.shm_ol_attach_line
    local platform = platform_of(player, element.tags and element.tags.card)
    local line = dropdown and lines.list(player.force)[dropdown.selected_index]
    if platform and line then
      lines.attach(player.force, line, platform.hub)
      controller.pass()
      local card = card_of(element)
      if card and card.valid then
        rebuild_content(card, player, platform)
      end
      lines_gui.open(player, line.id)
    end
    return true
  end
  if name == 'shm_ol_open_lines' then
    lines_gui.open(player)
    return true
  end
  return false
end

return overview
