-- Переключатель режима полной руки: связывает события игры с
-- `runtime/switch.lua`, где живёт вся логика.

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

script.on_event('shm-full-hand-toggle', function(e)
  local player = game.get_player(e.player_index)
  if player then
    switch.toggle_selected(player)
  end
end)

script.on_event(defines.events.on_entity_settings_pasted, function(e)
  switch.paste(e.source, e.destination)
end)

-- Стенд для тестов внутри игры: сценарии запускает мод `factorio-test`, когда
-- он активен, то есть только под `npm run test:ingame -w <мод>`. Зависимостью
-- мода он не объявляется, в обычной игре ничего не делает, а `tests/` в
-- релиз не попадает — convention `testing`.
if script.active_mods['factorio-test'] then
  require('__factorio-test__/init')({
    'tests.ingame.prototypes',
    'tests.ingame.full-hand',
    'tests.ingame.switch',
    'tests.ingame.blueprint',
    'tests.ingame.gui',
  })
end
