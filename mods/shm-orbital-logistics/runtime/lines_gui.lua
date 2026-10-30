-- Окно «Линии снабжения»: выбор, создание, переименование и удаление линии,
-- шапка из предметов и таблица участников. Правки собираются из полей по
-- «Применить» и уходят в `runtime.lines.sync`. ТЗ, раздел 7.

local logic = require('logic.lines')
local lines = require('runtime.lines')
local controller = require('runtime.controller')
local picker = require('runtime.places_picker')

local window = {}

window.NAME = 'shm_ol_lines'
local L = 'shm-orbital-logistics.'

local function selected(player)
  storage.gui = storage.gui or {}
  storage.gui[player.index] = storage.gui[player.index] or {}
  return storage.gui[player.index]
end

local function current_line(player)
  local id = selected(player).line
  local line = id and lines.get(player.force, id)
  if not line then
    line = lines.list(player.force)[1]
    selected(player).line = line and line.id or nil
  end
  return line
end

local function index_of(list, value)
  for index, item in ipairs(list) do
    if item == value then
      return index
    end
  end
  return 1
end

local function participant_caption(participant)
  local entity = participant.entity
  if participant.kind == 'pad' then
    return { L .. 'pad-name', entity.surface.planet and entity.surface.planet.name or entity.surface.name }
  end
  local platform = entity.surface.platform
  return platform and platform.name or entity.surface.name
end

local function add_header(frame, player, line)
  local bar = frame.add({ type = 'flow', direction = 'horizontal' })
  local all = lines.list(player.force)
  if #all > 0 then
    local items = {}
    local chosen = 1
    for index, entry in ipairs(all) do
      items[index] = entry.name
      if line and entry.id == line.id then
        chosen = index
      end
    end
    bar.add({ type = 'drop-down', name = 'shm_ol_line_select', items = items, selected_index = chosen })
  end
  local name = bar.add({ type = 'textfield', name = 'shm_ol_line_name', text = line and line.name or '' })
  name.style.width = 200
  bar.add({ type = 'button', name = 'shm_ol_line_create', caption = { L .. 'line-create' } })
  if line then
    bar.add({ type = 'button', name = 'shm_ol_line_rename', caption = { L .. 'line-rename' } })
    bar.add({ type = 'button', name = 'shm_ol_line_delete', caption = { L .. 'line-delete' }, style = 'red_button' })
  end
end

local function add_items(frame, line)
  frame.add({ type = 'label', caption = { L .. 'line-items' }, style = 'caption_label' })
  local table = frame.add({ type = 'table', name = 'shm_ol_items_table', column_count = 3 })
  for index, item in ipairs(line.items) do
    table.add({
      type = 'choose-elem-button',
      name = 'shm_ol_item_' .. index,
      elem_type = 'item-with-quality',
      ['item-with-quality'] = { name = item.name, quality = item.quality or 'normal' },
      tags = { row = index },
    })
    local count = table.add({
      type = 'textfield',
      name = 'shm_ol_count_' .. index,
      text = tostring(item.count or 0),
      numeric = true,
      tooltip = { L .. 'line-count' },
    })
    count.style.width = 90
    table.add({ type = 'sprite-button', name = 'shm_ol_item_remove_' .. index, sprite = 'utility/close', style = 'tool_button_red', tooltip = { L .. 'remove' }, tags = { row = index } })
  end
  table.add({ type = 'choose-elem-button', name = 'shm_ol_item_add', elem_type = 'item-with-quality', tooltip = { L .. 'line-add-item' } })
end

local function localized(prefix, values)
  local items = {}
  for index, value in ipairs(values) do
    items[index] = { L .. prefix .. value }
  end
  return items
end

local function add_participants(frame, line, force)
  frame.add({ type = 'label', caption = { L .. 'line-participants' }, style = 'caption_label' })
  if #line.participants == 0 then
    frame.add({ type = 'label', caption = { L .. 'line-participants-none' } })
    return
  end
  local table = frame.add({ type = 'table', name = 'shm_ol_participants', column_count = 7 })
  for _, column in ipairs({ 'participant', 'role', 'places', 'import', 'source', 'multiplier', 'remove' }) do
    table.add({ type = 'label', caption = column == 'remove' and '' or { L .. 'col-' .. column }, style = 'caption_label' })
  end
  for index, participant in ipairs(line.participants) do
    local hub = participant.kind ~= 'pad'
    table.add({ type = 'label', caption = participant_caption(participant) }).style.maximal_width = 180
    table.add({
      type = 'drop-down',
      name = 'shm_ol_role_' .. index,
      items = localized('role-', logic.ROLES),
      selected_index = index_of(logic.ROLES, participant.role),
      enabled = hub,
    })
    picker.add(table, 'shm_ol_pplaces_' .. index, force, picker.set(participant.places) or {}, {
      enabled = hub,
      tooltip = { L .. 'places-tooltip' },
    })
    picker.add(table, 'shm_ol_import_' .. index, force, participant.import_from and { [participant.import_from] = true } or {}, {
      enabled = hub,
      single = true,
      tooltip = { L .. 'import-tooltip' },
    })
    table.add({
      type = 'drop-down',
      name = 'shm_ol_source_' .. index,
      items = localized('source-', logic.SOURCES),
      selected_index = index_of(logic.SOURCES, participant.request_from or 'planet'),
      enabled = hub,
    })
    table.add({ type = 'textfield', name = 'shm_ol_mult_' .. index, text = tostring(participant.multiplier or 1), numeric = true, allow_decimal = true }).style.width = 60
    table.add({ type = 'sprite-button', name = 'shm_ol_detach_' .. index, sprite = 'utility/close', style = 'tool_button_red', tooltip = { L .. 'remove' }, tags = { row = index } })
  end
end

function window.close(player)
  local existing = player.gui.screen[window.NAME]
  if existing then
    existing.destroy()
  end
end

function window.open(player, line_id)
  if line_id then
    selected(player).line = line_id
  end
  window.close(player)
  local frame = player.gui.screen.add({ type = 'frame', name = window.NAME, direction = 'vertical' })
  local title = frame.add({ type = 'flow', direction = 'horizontal' })
  title.add({ type = 'label', caption = { L .. 'window-title' }, style = 'frame_title' })
  local drag = title.add({ type = 'empty-widget', style = 'draggable_space_header' })
  drag.style.horizontally_stretchable = true
  drag.style.height = 24
  drag.drag_target = frame
  title.add({ type = 'sprite-button', name = 'shm_ol_lines_close', sprite = 'utility/close', style = 'frame_action_button' })
  local body = frame.add({ type = 'frame', style = 'inside_shallow_frame_with_padding', direction = 'vertical' })
  local line = current_line(player)
  add_header(body, player, line)
  if line then
    add_items(body, line)
    add_participants(body, line, player.force)
    body.add({ type = 'button', name = 'shm_ol_line_apply', caption = { L .. 'apply' }, style = 'confirm_button' })
  else
    body.add({ type = 'label', caption = { L .. 'line-select' } })
  end
  frame.force_auto_center()
  return frame
end

local function find(root, name)
  if root.name == name then
    return root
  end
  for _, child in pairs(root.children) do
    local found = find(child, name)
    if found then
      return found
    end
  end
  return nil
end

--- Собирает поля окна в линию. Пустой выбор предмета убирает строку.
local function read_fields(frame, line)
  local items = {}
  for index in ipairs(line.items) do
    local chosen = find(frame, 'shm_ol_item_' .. index)
    local count = find(frame, 'shm_ol_count_' .. index)
    local value = chosen and chosen.elem_value
    if value and value.name then
      items[#items + 1] = {
        name = value.name,
        quality = value.quality or 'normal',
        count = math.max(0, math.floor(tonumber(count and count.text) or 0)),
      }
    end
  end
  line.items = items
  for index, participant in ipairs(line.participants) do
    if participant.kind ~= 'pad' then
      local role = find(frame, 'shm_ol_role_' .. index)
      local places = find(frame, 'shm_ol_pplaces_' .. index)
      local import = find(frame, 'shm_ol_import_' .. index)
      local source = find(frame, 'shm_ol_source_' .. index)
      participant.role = role and logic.ROLES[role.selected_index] or participant.role
      if places then
        participant.places = picker.text(picker.read(places))
      end
      if import then
        local chosen = picker.read(import)
        participant.import_from = chosen and next(chosen) or nil
      end
      participant.request_from = source and logic.SOURCES[source.selected_index] or participant.request_from
    end
    local multiplier = find(frame, 'shm_ol_mult_' .. index)
    participant.multiplier = logic.multiplier(multiplier and multiplier.text) or participant.multiplier or 1
  end
end

local function apply(player, line)
  local frame = player.gui.screen[window.NAME]
  if frame then
    read_fields(frame, line)
  end
  lines.sync(player.force, line)
  controller.pass()
end

--- Нажатие в окне. Возвращает true, если событие его.
function window.on_click(event)
  local element = event.element
  if not (element and element.valid) or string.sub(element.name, 1, 7) ~= 'shm_ol_' then
    return false
  end
  local player = game.get_player(event.player_index)
  local frame = player.gui.screen[window.NAME]
  local name = element.name
  if name == 'shm_ol_lines_close' then
    window.close(player)
    return true
  end
  if not frame then
    return false
  end
  local line = current_line(player)
  if name == 'shm_ol_line_create' then
    local created, reason = lines.create(player.force, find(frame, 'shm_ol_line_name').text)
    if created then
      window.open(player, created.id)
    else
      player.print({ L .. 'error-' .. reason })
    end
    return true
  end
  if name == 'shm_ol_line_rename' and line then
    local ok, reason = lines.rename(player.force, line, find(frame, 'shm_ol_line_name').text)
    if not ok then
      player.print({ L .. 'error-' .. reason })
    end
    window.open(player)
    return true
  end
  if name == 'shm_ol_line_delete' and line then
    lines.delete(player.force, line)
    selected(player).line = nil
    controller.pass()
    window.open(player)
    return true
  end
  if name == 'shm_ol_line_apply' and line then
    apply(player, line)
    window.open(player)
    return true
  end
  if string.sub(name, 1, 19) == 'shm_ol_item_remove_' and line then
    read_fields(frame, line)
    table.remove(line.items, element.tags.row)
    apply(player, line)
    window.open(player)
    return true
  end
  if string.sub(name, 1, 14) == 'shm_ol_detach_' and line then
    read_fields(frame, line)
    lines.detach(player.force, line, element.tags.row)
    controller.pass()
    window.open(player)
    return true
  end
  return false
end

function window.on_selection(event)
  local element = event.element
  if element and element.valid and element.name == 'shm_ol_line_select' then
    local player = game.get_player(event.player_index)
    local line = lines.list(player.force)[element.selected_index]
    window.open(player, line and line.id)
    return true
  end
  return false
end

--- Выбор предмета в пустой строке шапки — новая строка с нулевым количеством.
function window.on_elem_changed(event)
  local element = event.element
  if not (element and element.valid and element.name == 'shm_ol_item_add') then
    return false
  end
  local player = game.get_player(event.player_index)
  local line = current_line(player)
  local value = element.elem_value
  if line and value and value.name then
    read_fields(player.gui.screen[window.NAME], line)
    line.items[#line.items + 1] = { name = value.name, quality = value.quality or 'normal', count = 0 }
    window.open(player)
  end
  return true
end

return window
