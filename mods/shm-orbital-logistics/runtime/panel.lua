-- Панель у окна хаба и площадки: назначение секций меткой в имени группы,
-- состояние предметов по своей секции мода, предупреждение про флаг раздачи
-- и подключение к линиям снабжения. ТЗ, раздел 8.

local tags = require('logic.tags')
local groups = require('runtime.groups')
local lines = require('runtime.lines')
local own_section = require('logic.own_section')
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

local function add_sections(frame, hub)
  local table = frame.add({ type = 'table', column_count = 4 })
  local sections = hub.get_logistic_sections()
  local saved = storage.platforms and storage.platforms[hub.surface.platform.index]
  for index = 1, sections.sections_count do
    local section = sections.get_section(index)
    if section.is_manual and not controller.is_service(section.group) then
      local tag = tags.parse(section.group)
      local owner = line_of(hub.force, section.group)
      local locked = owner and { L .. 'section-of-line', owner.name } or nil
      local caption = section.group ~= '' and section.group or { L .. 'section-unnamed', index }
      local label = table.add({ type = 'label', caption = caption, style = 'label' })
      label.style.maximal_width = 220
      if saved and saved.released and saved.released[section.group] then
        -- Снятая галочка у группы груза — дело мода, а не поломка: подсказать.
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
      picker.add(table, 'shm_ol_places_' .. index, hub.force, tag and (tag.dests or tag.orbits) or {}, {
        tooltip = locked or { L .. 'places-tooltip' },
        enabled = locked == nil,
      })
      table.add({
        type = 'button',
        name = 'shm_ol_apply_' .. index,
        caption = { L .. 'apply' },
        tooltip = locked or { L .. 'apply-tooltip' },
        tags = { section = index },
        enabled = locked == nil,
      }).style.minimal_width = 100
    end
  end
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

--- Состояние группы с меткой на текущей орбите: вид значка и строка. Для
--- склада — третий итог: true, когда строка группы уже сказала «не сможет
--- отдавать платформам» и предметам повторять это не нужно.
local function group_state(tag, location, released, items)
  local count = #items
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
      local kind, caption, covered = group_state(tag, location, released[section.group], items)
      rows[#rows + 1] = { group = section.group, kind = kind, caption = caption, anchor = items[1] }
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
  local exceptions = {}
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
      exceptions[#exceptions + 1] = { item = item, kind = kind, text = text, key = key }
    end
  end
  table.sort(exceptions, function(a, b) return a.key < b.key end)
  return rows, exceptions
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
    for _, entry in ipairs(exceptions) do
      list.add({
        type = 'sprite-button',
        sprite = 'item/' .. entry.item.name,
        style = 'slot_button',
        number = hub.get_inventory(defines.inventory.hub_main).get_item_count({ name = entry.item.name, quality = entry.item.quality }),
        tooltip = '[item=' .. entry.item.name .. (entry.item.quality and (',quality=' .. entry.item.quality) or '') .. ']',
      }).style.size = 32
      list.add({ type = 'label', caption = { '', icon(entry.kind), entry.text } })
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

--- Поиск по имени на любой глубине: контейнеры «Отдачи» и предупреждений
--- живут в прокрутках своих блоков.
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

--- Раз в секунду: группы изменились — перестроить панель, иначе обновить
--- только «Отдачу» и предупреждения, чтобы не сбивать выбор в полях.
--- Свёрнутая панель без обновлений; свёрнутый блок не имеет контейнера,
--- и его обновление пропускается.
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
  if not (purpose_element and places_element) then
    return
  end
  local kind = PURPOSES[purpose_element.selected_index] or 'none'
  local tag = tags.from_choice(kind, picker.text(picker.read(places_element)))
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
