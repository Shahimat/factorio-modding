-- Переключатель режима полной стопки лоадеров: связывает события игры с
-- `runtime/switch.lua`, где живёт вся логика. Механика выключена
-- настройкой — переключателя нет.

local names = require('logic.setting-names')

if settings.startup[names.FULL_STACK].value then
  local switch = require('runtime.switch')

  script.on_event(defines.events.on_gui_opened, function(e)
    local player = game.get_player(e.player_index)
    if not player or e.gui_type ~= defines.gui_type.entity then
      return
    end
    switch.refresh_gui(player, e.entity)
  end)

  script.on_event(defines.events.on_gui_switch_state_changed, function(e)
    if e.element.name ~= switch.SWITCH then
      return
    end
    local player = game.get_player(e.player_index)
    if player then
      switch.on_switch_changed(player, e.element)
    end
  end)

  -- Постройка из руки поверх призрака другого варианта: режим берётся у
  -- призрака, а не у предмета.
  script.on_event(defines.events.on_pre_build, function(e)
    local player = game.get_player(e.player_index)
    if player then
      switch.on_pre_build(player, e.position)
    end
  end)

  -- Достройка призрака при открытом окне: `on_gui_opened` игра не шлёт.
  local BUILT_FILTER = { { filter = 'type', type = 'loader' }, { filter = 'type', type = 'loader-1x1' } }
  local function on_built(e)
    if e.entity.valid then
      switch.on_built(e.entity)
    end
  end
  script.on_event(defines.events.on_built_entity, function(e)
    local player = game.get_player(e.player_index)
    local entity = player and switch.on_player_built(player, e.entity) or e.entity
    if entity and entity.valid then
      switch.on_built(entity)
    end
  end, BUILT_FILTER)
  for _, event in ipairs({
    defines.events.on_robot_built_entity,
    defines.events.on_space_platform_built_entity,
    defines.events.script_raised_built,
    defines.events.script_raised_revive,
  }) do
    script.on_event(event, on_built, BUILT_FILTER)
  end

  script.on_event('shm-advanced-belts-full-stack-toggle', function(e)
    local player = game.get_player(e.player_index)
    if player then
      switch.toggle_selected(player)
    end
  end)

  script.on_event(defines.events.on_entity_settings_pasted, function(e)
    switch.paste(e.source, e.destination)
  end)
end

-- Стенд для тестов внутри игры: сценарии запускает мод `factorio-test`, когда
-- он активен, то есть только под `npm run test:ingame -w <мод>`. Зависимостью
-- мода он не объявляется, в обычной игре ничего не делает, а `tests/` в
-- релиз не попадает — convention `testing`.
if script.active_mods['factorio-test'] then
  require('__factorio-test__/init')({
    'tests.ingame.prototypes',
    'tests.ingame.loaders',
    'tests.ingame.switch',
    'tests.ingame.gui',
  })
end
