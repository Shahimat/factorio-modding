-- Переключение режима полной руки в рантайме: замена сущности, панель у
-- окна манипулятора, разбор нажатия клавиши и вставки настроек.
--
-- Режим — это прототип (`logic/variants.lua`), поэтому переключение — замена
-- сущности на месте через `fast_replace`. То, что `fast_replace` может не
-- перенести, снимается до замены и восстанавливается после.
--
-- Модуль обращается к игровому API и юнит-тестом не берётся; его проверяют
-- тесты внутри игры (`tests/ingame/`). `control.lua` только связывает
-- функции модуля с событиями.

local variants = require('logic.variants')

local switch = {}

switch.WINDOW = 'shm_full_hand_window'
switch.SWITCH = 'shm_full_hand_switch'

--- Имена обоих вариантов, которые реально есть в игре.
function switch.present_names()
  local names = {}
  for _, name in ipairs(variants.all_names()) do
    if prototypes.entity[name] then
      names[#names + 1] = name
    end
  end
  return names
end

--- @param entity LuaEntity?
function switch.is_switchable(entity)
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
--- сущность (или ту же, если режим уже нужный) либо nil, если замена не
--- удалась — старая тогда остаётся.
--- @param entity LuaEntity
--- @param waiting boolean
function switch.switch_to(entity, waiting)
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

--- Что делать с сущностью под курсором при нажатии клавиши:
--- `'switch'` — переключать, `'ghost'` — призрак семьи (отказ с подсказкой),
--- `'ignore'` — не наше дело, молча ничего.
--- @param entity LuaEntity?
--- @param force LuaForce
function switch.classify(entity, force)
  if not (entity and entity.valid) then
    return 'ignore'
  end
  if entity.type == 'entity-ghost' and variants.is_family(entity.ghost_name) then
    return 'ghost'
  end
  if not switch.is_switchable(entity) or entity.force ~= force then
    return 'ignore'
  end
  return 'switch'
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
--- @param key string
local function refuse(player, key)
  player.create_local_flying_text({ text = { key }, create_at_cursor = true })
  player.play_sound({ path = 'utility/cannot_build' })
end

--- Нажатие клавиши: переключает манипулятор под курсором. Возвращает новую
--- сущность либо nil, если переключения не было.
--- @param player LuaPlayer
function switch.toggle_selected(player)
  local entity = player.selected
  local verdict = switch.classify(entity, player.force)
  if verdict == 'ghost' then
    refuse(player, 'gui.shm-full-hand-ghost')
    return nil
  end
  if verdict ~= 'switch' then
    return nil
  end
  --- @cast entity LuaEntity
  if not player.can_reach_entity(entity) then
    refuse(player, 'cant-reach')
    return nil
  end
  local replacement = switch.switch_to(entity, not variants.is_waiting(entity.name))
  if replacement then
    announce(replacement)
  end
  return replacement
end

--- Вставка настроек: приёмник получает режим источника.
--- @param source LuaEntity
--- @param destination LuaEntity
function switch.paste(source, destination)
  if not (switch.is_switchable(source) and switch.is_switchable(destination)) then
    return nil
  end
  return switch.switch_to(destination, variants.is_waiting(source.name))
end

--- Пересоздаёт панель режима для открытой сущности; для чужой — убирает.
--- @param player LuaPlayer
--- @param entity LuaEntity?
function switch.refresh_gui(player, entity)
  local window = player.gui.relative[switch.WINDOW]
  if window then
    window.destroy()
  end
  if not switch.is_switchable(entity) then
    return
  end
  --- @cast entity LuaEntity
  local frame = player.gui.relative.add({
    type = 'frame',
    name = switch.WINDOW,
    caption = { 'gui.shm-full-hand-caption' },
    anchor = {
      gui = defines.relative_gui_type.inserter_gui,
      position = defines.relative_gui_position.right,
      names = switch.present_names(),
    },
  })
  local inner = frame.add({ type = 'frame', style = 'inside_shallow_frame_with_padding' })
  inner.add({
    type = 'switch',
    name = switch.SWITCH,
    left_label_caption = { 'gui.shm-full-hand-instant' },
    right_label_caption = { 'gui.shm-full-hand-full' },
    switch_state = variants.is_waiting(entity.name) and 'right' or 'left',
  })
end

--- Щелчок переключателя в панели: ставит режим по его положению открытому
--- манипулятору. Возвращает новую сущность либо nil.
--- @param player LuaPlayer
--- @param element LuaGuiElement
function switch.on_switch_changed(player, element)
  if player.opened_gui_type ~= defines.gui_type.entity then
    return nil
  end
  local entity = player.opened --[[@as LuaEntity?]]
  if not switch.is_switchable(entity) then
    return nil
  end
  --- @cast entity LuaEntity
  local replacement = switch.switch_to(entity, element.switch_state == 'right')
  if replacement then
    announce(replacement)
  elseif element.valid then
    element.switch_state = variants.is_waiting(entity.name) and 'right' or 'left'
  end
  return replacement
end

return switch
