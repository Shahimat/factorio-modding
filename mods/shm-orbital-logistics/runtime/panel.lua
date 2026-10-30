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
  frame.add({ type = 'label', caption = { L .. 'sections' }, style = 'caption_label' })
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

local function item_filters(section)
  local list = {}
  for _, slot in pairs(section.filters) do
    local value = slot.value
    if value and value.name and (value.type == nil or value.type == 'item') and prototypes.item[value.name] then
      list[#list + 1] = { name = value.name, quality = quality_of(value) }
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

--- Состояние группы с меткой на текущей орбите: вид значка и строка.
local function group_state(tag, location, released, count)
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
    return 'giving', { L .. 'now-depot-here' }
  end
  if tag.anywhere then
    return 'held', { L .. 'now-depot-flight', count }
  end
  return 'held', { L .. 'now-depot-held', places_caption(tag.orbits), count }
end

--- «Отдача на этой орбите»: строка на каждую группу с меткой — что мод с ней делает на
--- этой орбите, — и исключения: предметы, которые ведут себя не как их
--- группа. Обновляется раз в секунду, поэтому живёт в своём контейнере.
local function fill_now(flow, hub)
  flow.clear()
  local state = own_state(hub)
  local platform = hub.surface.platform
  local location = platform and platform.space_location and platform.space_location.name
  local saved = storage.platforms and platform and storage.platforms[platform.index]
  local released = saved and saved.released or {}
  local groups = flow.add({ type = 'table', column_count = 3 })
  for column = 1, 3 do
    groups.style.column_alignments[column] = 'middle-left'
  end
  local expected = {}
  local reserved = {}
  local first_item = {}
  local rows = 0
  local sections = hub.get_logistic_sections()
  for index = 1, sections.sections_count do
    local section = sections.get_section(index)
    local tag = section.is_manual and not controller.is_service(section.group) and tags.parse(section.group)
    if tag then
      local items = item_filters(section)
      local kind, caption = group_state(tag, location, released[section.group], #items)
      local anchor = items[1]
      groups.add({
        type = 'sprite-button',
        sprite = anchor and ('item/' .. anchor.name) or 'utility/questionmark',
        style = 'slot_button',
        tooltip = section.group,
      }).style.size = 32
      local name = groups.add({ type = 'label', caption = section.group })
      name.style.maximal_width = 240
      name.style.font = 'default-semibold'
      groups.add({ type = 'label', caption = { '', icon(kind), caption } })
      rows = rows + 1
      for _, item in ipairs(items) do
        local key = own_section.key(item.name, item.quality)
        first_item[key] = first_item[key] or item
        if tag.kind == 'reserve' then
          reserved[key] = true
        end
        if expected[key] ~= 'held' then
          expected[key] = (kind == 'held') and 'held' or 'open'
        end
      end
    end
  end
  if rows == 0 then
    flow.clear()
    flow.add({ type = 'label', caption = { L .. 'now-nothing' } })
    return
  end
  local exceptions = {}
  for key, item in pairs(first_item) do
    local text = nil
    local kind = nil
    if state.transit[key] then
      kind, text = 'transit', { L .. 'now-ex-transit' }
    elseif state.locks[key] and expected[key] == 'open' then
      kind = 'held'
      text = reserved[key] and { L .. 'now-ex-reserve-left' } or { L .. 'now-ex-yield' }
    elseif not state.locks[key] and expected[key] == 'held' and reserved[key] then
      kind, text = 'giving', { L .. 'now-ex-over-reserve' }
    end
    if text then
      exceptions[#exceptions + 1] = { item = item, kind = kind, text = text, key = key }
    end
  end
  if #exceptions > 0 then
    table.sort(exceptions, function(a, b) return a.key < b.key end)
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

local function add_lines(frame, player, entity)
  frame.add({ type = 'label', caption = { L .. 'lines' }, style = 'caption_label' })
  local member = lines.of_entity(player.force, entity)
  for _, entry in ipairs(member) do
    frame.add({ type = 'label', caption = { L .. 'lines-member', entry.line.name } })
  end
  local all = lines.list(player.force)
  local flow = frame.add({ type = 'flow', direction = 'horizontal' })
  if #all > 0 then
    local items = {}
    for i, line in ipairs(all) do
      items[i] = line.name
    end
    flow.add({ type = 'drop-down', name = 'shm_ol_attach_line', items = items, selected_index = 1 })
    flow.add({ type = 'button', name = 'shm_ol_attach', caption = { L .. 'lines-attach' } }).style.minimal_width = 100
  else
    flow.add({ type = 'label', caption = { L .. 'lines-none' } })
  end
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

function panel.build(player, entity)
  panel.destroy(player)
  local position = position_of(player)
  local wide = position == 'bottom' or position == 'top'
  local frame = player.gui.relative.add({
    type = 'frame',
    name = panel.NAME,
    caption = { L .. 'panel-title' },
    direction = wide and 'horizontal' or 'vertical',
    anchor = { gui = anchor(entity), position = defines.relative_gui_position[position] },
    tags = { unit_number = entity.unit_number, signature = entity.type == 'space-platform-hub' and signature(entity) or nil },
  })
  if not wide then
    frame.style.maximal_width = 560
  end
  local first = 0
  --- Блок панели: в ряду — свой столбец с разделителем, в столбике — сама рамка.
  local function block()
    if not wide then
      return frame
    end
    if first > 0 then
      frame.add({ type = 'line', direction = 'vertical' })
    end
    first = first + 1
    local column = frame.add({ type = 'flow', direction = 'vertical' })
    column.style.right_padding = 8
    column.style.left_padding = 8
    return column
  end
  if entity.type == 'space-platform-hub' then
    local main = block()
    if not entity.providing_to_other_platforms and giving_tags(entity) then
      local warning = main.add({ type = 'label', name = 'shm_ol_warning', caption = { L .. 'warning-providing' } })
      warning.style.font_color = { 1, 0.3, 0.3 }
      warning.style.single_line = false
      warning.style.maximal_width = 500
    end
    add_sections(main, entity)
    local now = block()
    now.add({ type = 'label', caption = { L .. 'now' }, style = 'caption_label' })
    fill_now(now.add({ type = 'flow', name = 'shm_ol_now', direction = 'vertical' }), entity)
  end
  add_lines(block(), player, entity)
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
--- только «Отдача на этой орбите», чтобы не сбивать выбор в полях.
function panel.refresh_all()
  for _, player in pairs(game.connected_players) do
    local frame = player.gui.relative[panel.NAME]
    local entity = frame and opened_entity(player)
    if entity and entity.type == 'space-platform-hub' then
      if frame.tags.signature ~= signature(entity) then
        panel.build(player, entity)
      else
        local now = nil
        for _, child in pairs(frame.children) do
          now = now or (child.name == 'shm_ol_now' and child) or child['shm_ol_now']
        end
        if now then
          fill_now(now, entity)
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
