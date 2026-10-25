-- Переключатель режима полной руки: панель справа от окна манипулятора,
-- клавиша и перенос режима при копировании настроек.
--
-- Режим — это прототип (`logic/variants.lua`), поэтому переключение — замена
-- сущности на месте через `fast_replace`. То, что `fast_replace` может не
-- перенести, снимается до замены и восстанавливается после.

local variants = require('logic.variants')

local WINDOW = 'shm_full_hand_window'
local SWITCH = 'shm_full_hand_switch'

--- Имена обоих вариантов, которые реально есть в игре.
local function present_names()
  local names = {}
  for _, name in ipairs(variants.all_names()) do
    if prototypes.entity[name] then
      names[#names + 1] = name
    end
  end
  return names
end

--- @param entity LuaEntity?
local function is_switchable(entity)
  if not (entity and entity.valid and entity.type == 'inserter') then
    return false
  end
  local other = variants.toggled(entity.name)
  return other ~= nil and prototypes.entity[other] ~= nil
end

--- @param stack LuaItemStack
local function capture_stack(stack)
  if not stack.valid_for_read then
    return nil
  end
  return {
    name = stack.name,
    count = stack.count,
    quality = stack.quality.name,
    spoil_percent = stack.spoil_percent,
  }
end

--- @param entity LuaEntity
local function capture(entity)
  local filters = {}
  for i = 1, entity.filter_slot_count do
    filters[i] = entity.get_filter(i)
  end
  return {
    pickup_position = entity.pickup_position,
    drop_position = entity.drop_position,
    held = capture_stack(entity.held_stack),
    health = entity.health,
    last_user = entity.last_user,
    use_filters = entity.use_filters,
    filter_mode = entity.inserter_filter_mode,
    filters = filters,
    spoil_priority = entity.inserter_spoil_priority,
    stack_size_override = entity.inserter_stack_size_override,
    pickup_from_left_lane = entity.pickup_from_left_lane,
    pickup_from_right_lane = entity.pickup_from_right_lane,
  }
end

--- @param entity LuaEntity
local function restore(entity, state)
  if entity.prototype.allow_custom_vectors then
    entity.pickup_position = state.pickup_position
    entity.drop_position = state.drop_position
  end
  if state.held and not entity.held_stack.valid_for_read then
    entity.held_stack.set_stack(state.held)
  end
  entity.health = state.health
  entity.last_user = state.last_user
  entity.use_filters = state.use_filters
  if state.filter_mode then
    entity.inserter_filter_mode = state.filter_mode
  end
  for i, filter in pairs(state.filters) do
    entity.set_filter(i, filter)
  end
  entity.inserter_spoil_priority = state.spoil_priority
  entity.inserter_stack_size_override = state.stack_size_override
  entity.pickup_from_left_lane = state.pickup_from_left_lane
  entity.pickup_from_right_lane = state.pickup_from_right_lane
end

--- Ставит на место `entity` вариант нужного режима. Возвращает новую
--- сущность либо nil, если замена не удалась (старая тогда остаётся).
--- @param entity LuaEntity
--- @param waiting boolean
local function switch_to(entity, waiting)
  if variants.is_waiting(entity.name) == waiting then
    return entity
  end
  local openers = {}
  for _, player in pairs(game.connected_players) do
    if player.opened == entity then
      openers[#openers + 1] = player
    end
  end
  local state = capture(entity)
  local replacement = entity.surface.create_entity({
    name = variants.with_mode(entity.name, waiting),
    position = entity.position,
    direction = entity.direction,
    mirror = entity.mirroring,
    quality = entity.quality,
    force = entity.force,
    fast_replace = true,
    spill = false,
    raise_built = true,
    create_build_effect_smoke = false,
  })
  if not replacement then
    return nil
  end
  restore(replacement, state)
  for _, player in ipairs(openers) do
    player.opened = replacement
  end
  return replacement
end

--- @param entity LuaEntity
local function announce(entity)
  local key = variants.is_waiting(entity.name) and 'gui.shm-full-hand-message-full'
    or 'gui.shm-full-hand-message-instant'
  for _, player in pairs(game.connected_players) do
    if player.surface == entity.surface then
      player.create_local_flying_text({ text = { key }, position = entity.position })
    end
  end
end

--- @param player LuaPlayer
--- @param entity LuaEntity?
local function refresh_gui(player, entity)
  local window = player.gui.relative[WINDOW]
  if window then
    window.destroy()
  end
  if not is_switchable(entity) then
    return
  end
  --- @cast entity LuaEntity
  local frame = player.gui.relative.add({
    type = 'frame',
    name = WINDOW,
    caption = { 'gui.shm-full-hand-caption' },
    anchor = {
      gui = defines.relative_gui_type.inserter_gui,
      position = defines.relative_gui_position.right,
      names = present_names(),
    },
  })
  local inner = frame.add({ type = 'frame', style = 'inside_shallow_frame_with_padding' })
  inner.add({
    type = 'switch',
    name = SWITCH,
    left_label_caption = { 'gui.shm-full-hand-instant' },
    right_label_caption = { 'gui.shm-full-hand-full' },
    switch_state = variants.is_waiting(entity.name) and 'right' or 'left',
  })
end

--- @param player LuaPlayer
--- @param key string
local function refuse(player, key)
  player.create_local_flying_text({ text = { key }, create_at_cursor = true })
  player.play_sound({ path = 'utility/cannot_build' })
end

script.on_event(defines.events.on_gui_opened, function(e)
  local player = game.get_player(e.player_index)
  if not player or e.gui_type ~= defines.gui_type.entity then
    return
  end
  refresh_gui(player, e.entity)
end)

script.on_event(defines.events.on_gui_switch_state_changed, function(e)
  if e.element.name ~= SWITCH then
    return
  end
  local player = game.get_player(e.player_index)
  if not player or player.opened_gui_type ~= defines.gui_type.entity then
    return
  end
  local entity = player.opened --[[@as LuaEntity?]]
  if not is_switchable(entity) then
    return
  end
  --- @cast entity LuaEntity
  local replacement = switch_to(entity, e.element.switch_state == 'right')
  if replacement then
    announce(replacement)
  elseif e.element.valid then
    e.element.switch_state = variants.is_waiting(entity.name) and 'right' or 'left'
  end
end)

script.on_event('shm-full-hand-toggle', function(e)
  local player = game.get_player(e.player_index)
  if not player then
    return
  end
  local entity = player.selected
  if not entity then
    return
  end
  if entity.type == 'entity-ghost' and variants.is_family(entity.ghost_name) then
    refuse(player, 'gui.shm-full-hand-ghost')
    return
  end
  if not is_switchable(entity) or entity.force ~= player.force then
    return
  end
  if not player.can_reach_entity(entity) then
    refuse(player, 'cant-reach')
    return
  end
  local replacement = switch_to(entity, not variants.is_waiting(entity.name))
  if replacement then
    announce(replacement)
  end
end)

script.on_event(defines.events.on_entity_settings_pasted, function(e)
  local source, destination = e.source, e.destination
  if not (is_switchable(source) and is_switchable(destination)) then
    return
  end
  switch_to(destination, variants.is_waiting(source.name))
end)
