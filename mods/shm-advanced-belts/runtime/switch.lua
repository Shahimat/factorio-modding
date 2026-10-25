-- Переключение режима полной стопки в рантайме: замена лоадера, панель у
-- его окна, разбор клавиши и вставки настроек.
--
-- Режим — это прототип (`logic/variants.lua`), поэтому переключение — замена
-- сущности на месте через `fast_replace`. То, что `fast_replace` может не
-- перенести, снимается до замены и восстанавливается после. Старый лоадер
-- объявляется снесённым, новый — построенным: так моды с компаньонами
-- лоадера (AAI и его труба с лубрикантом) успевают убрать старое и
-- поставить новое, а лубрикант переносится в новую трубу.
--
-- Модуль обращается к игровому API и юнит-тестом не берётся; его проверяют
-- тесты внутри игры (`tests/ingame/`). `control.lua` только связывает
-- функции модуля с событиями.

local names = require('logic.setting-names')
local variants = require('logic.variants')

local switch = {}

switch.WINDOW = 'shm_advanced_belts_full_stack_window'
switch.SWITCH = 'shm_advanced_belts_full_stack_switch'

--- Смещение трубы AAI относительно лоадера — как в скрипте AAI.
local PIPE_OFFSET = 1 / 32

local function default_waiting()
  return settings.startup[names.FULL_STACK_DEFAULT].value
end

function switch.is_waiting(name)
  return variants.is_waiting(name, default_waiting())
end

local function is_loader_type(entity_type)
  return entity_type == 'loader' or entity_type == 'loader-1x1'
end

--- Есть ли у прототипа пара другого режима.
function switch.is_family(name)
  local base = variants.base_name(name)
  return prototypes.entity[base] ~= nil and prototypes.entity[variants.alt_name(base)] ~= nil
end

--- @param entity LuaEntity?
function switch.is_switchable(entity)
  return entity ~= nil and entity.valid and is_loader_type(entity.type) and switch.is_family(entity.name)
end

--- @param entity LuaEntity
local function capture(entity)
  local filters = {}
  for i = 1, entity.filter_slot_count do
    filters[i] = entity.get_filter(i)
  end
  return {
    loader_type = entity.loader_type,
    filters = filters,
    filter_mode = entity.loader_filter_mode,
    stack_size_override = entity.loader_belt_stack_size_override,
    health = entity.health,
    last_user = entity.last_user,
  }
end

--- @param entity LuaEntity
local function restore(entity, state)
  entity.loader_type = state.loader_type
  for i, filter in pairs(state.filters) do
    entity.set_filter(i, filter)
  end
  if state.filter_mode then
    entity.loader_filter_mode = state.filter_mode
  end
  entity.loader_belt_stack_size_override = state.stack_size_override
  entity.health = state.health
  entity.last_user = state.last_user
end

--- Скрытая труба AAI при лоадере, если она есть.
--- @param entity LuaEntity
function switch.find_pipe(entity)
  local pipe_name = entity.name .. variants.PIPE_SUFFIX
  if prototypes.entity[pipe_name] == nil then
    return nil
  end
  local position = entity.position
  return entity.surface.find_entity(pipe_name, { position.x, position.y + PIPE_OFFSET })
end

--- Ставит на место `entity` вариант нужного режима. Возвращает новую
--- сущность (или ту же, если режим уже нужный) либо nil, если замена не
--- удалась — старая тогда остаётся.
--- @param entity LuaEntity
--- @param waiting boolean
function switch.switch_to(entity, waiting)
  if switch.is_waiting(entity.name) == waiting then
    return entity
  end
  local openers = {}
  for _, player in pairs(game.connected_players) do
    if player.opened == entity then
      openers[#openers + 1] = player
    end
  end
  local state = capture(entity)
  local pipe = switch.find_pipe(entity)
  local fluid = pipe and pipe.get_fluid(1) or nil
  local surface = entity.surface
  local spec = {
    name = variants.with_mode(entity.name, waiting, default_waiting()),
    position = entity.position,
    direction = entity.direction,
    quality = entity.quality,
    force = entity.force,
    type = entity.loader_type,
    fast_replace = true,
    spill = false,
    raise_built = true,
    create_build_effect_smoke = false,
  }
  if not surface.can_fast_replace({ name = spec.name, position = spec.position, direction = spec.direction, force = spec.force }) then
    return nil
  end
  script.raise_script_destroy({ entity = entity })
  local replacement = surface.create_entity(spec)
  if not replacement then
    return nil
  end
  restore(replacement, state)
  if fluid then
    local new_pipe = switch.find_pipe(replacement)
    if new_pipe then
      new_pipe.insert_fluid(fluid)
    end
  end
  for _, player in ipairs(openers) do
    player.opened = replacement
  end
  return replacement
end

--- Что делать с сущностью под курсором при нажатии клавиши:
--- `'switch'` — переключать, `'ghost'` — призрак лоадера с парой (отказ с
--- подсказкой), `'ignore'` — не наше дело, молча ничего.
--- @param entity LuaEntity?
--- @param force LuaForce
function switch.classify(entity, force)
  if not (entity and entity.valid) then
    return 'ignore'
  end
  if entity.type == 'entity-ghost' and is_loader_type(entity.ghost_type) and switch.is_family(entity.ghost_name) then
    return 'ghost'
  end
  if not switch.is_switchable(entity) or entity.force ~= force then
    return 'ignore'
  end
  return 'switch'
end

--- @param entity LuaEntity
local function announce(entity)
  local key = switch.is_waiting(entity.name) and 'gui.shm-advanced-belts-message-full'
    or 'gui.shm-advanced-belts-message-instant'
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

--- Нажатие клавиши: переключает лоадер под курсором. Возвращает новую
--- сущность либо nil, если переключения не было.
--- @param player LuaPlayer
function switch.toggle_selected(player)
  local entity = player.selected
  local verdict = switch.classify(entity, player.force)
  if verdict == 'ghost' then
    refuse(player, 'gui.shm-advanced-belts-ghost')
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
  local replacement = switch.switch_to(entity, not switch.is_waiting(entity.name))
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
  return switch.switch_to(destination, switch.is_waiting(source.name))
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
    caption = { 'gui.shm-advanced-belts-caption' },
    anchor = {
      gui = defines.relative_gui_type.loader_gui,
      position = defines.relative_gui_position.right,
    },
  })
  local inner = frame.add({ type = 'frame', style = 'inside_shallow_frame_with_padding' })
  inner.add({
    type = 'switch',
    name = switch.SWITCH,
    left_label_caption = { 'gui.shm-advanced-belts-instant' },
    right_label_caption = { 'gui.shm-advanced-belts-full' },
    switch_state = switch.is_waiting(entity.name) and 'right' or 'left',
  })
end

--- Щелчок переключателя в панели: ставит режим по его положению открытому
--- лоадеру. Возвращает новую сущность либо nil.
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
    element.switch_state = switch.is_waiting(entity.name) and 'right' or 'left'
  end
  return replacement
end

return switch
