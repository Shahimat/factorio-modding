-- Точка входа: контроллер обходит платформы порциями — полный круг раз в
-- секунду — и сразу обрабатывает платформу, сменившую состояние: прилёт,
-- отлёт, ожидание на орбите.

local controller = require('runtime.controller')
local overview = require('runtime.overview_gui')
local lines_gui = require('runtime.lines_gui')
local picker = require('runtime.places_picker')

script.on_init(function()
  storage.platforms = {}
  storage.panel_block_collapsed = {}
  for _, player in pairs(game.players) do
    overview.ensure_button(player)
  end
end)

script.on_configuration_changed(function()
  storage.platforms = storage.platforms or {}
  storage.panel_block_collapsed = storage.panel_block_collapsed or {}
  -- Панель у окна хаба больше нет; её свёрнутость и старая настройка
  -- положения — из хранилища убрать.
  storage.panel_collapsed = nil
  controller.migrate()
  for _, player in pairs(game.players) do
    overview.ensure_button(player)
  end
end)

script.on_event(defines.events.on_player_created, function(event)
  local player = game.get_player(event.player_index)
  if player then
    overview.ensure_button(player)
  end
end)

script.on_nth_tick(controller.SLICE_TICKS, controller.slice)

script.on_event(defines.events.on_space_platform_changed_state, controller.on_platform_changed)

script.on_event(defines.events.on_entity_logistic_slot_changed, controller.on_slot_changed)

-- Интерфейс: окно обзора платформ, окно линий снабжения.
script.on_event(defines.events.on_gui_opened, overview.on_opened)

script.on_event(defines.events.on_gui_closed, overview.on_closed)

script.on_event(defines.events.on_gui_click, function(event)
  if overview.on_click(event) then
    return
  end
  if picker.on_click(event) then
    return
  end
  lines_gui.on_click(event)
end)

script.on_event(defines.events.on_gui_selection_state_changed, function(event)
  if overview.on_selection(event) then
    return
  end
  lines_gui.on_selection(event)
end)

script.on_event(defines.events.on_gui_elem_changed, function(event)
  if overview.on_elem_changed(event) then
    return
  end
  if picker.on_elem_changed(event) then
    return
  end
  lines_gui.on_elem_changed(event)
end)

-- Отладочная сборка: настройка «Режим отладки» есть, только если в моде
-- лежат отладочные файлы (`tests/debug.lua`), а в zip релиза их нет.
local debug_build = settings.startup['shm-orbital-logistics-debug'] ~= nil
local demo = nil
if debug_build and settings.startup['shm-orbital-logistics-debug'].value then
  demo = require('tests.demo.commands')
  demo.register()
end

script.on_nth_tick(60, function(event)
  overview.refresh_all()
  if demo then
    demo.on_tick(event)
  end
end)

commands.add_command('shm-orbital-lines', { 'shm-orbital-logistics.command-lines' }, function(event)
  local player = event.player_index and game.get_player(event.player_index)
  if player then
    lines_gui.open(player)
  end
end)

-- `pass` — пройти контроллером сейчас, не дожидаясь секунды: так тот, кто
-- только что поставил метки скриптом (демо-сцена, другой мод), не даёт ванили
-- отдать груз до первого прохода.
remote.add_interface('shm-orbital-logistics', {
  pass = controller.pass,
})

script.on_event(defines.events.on_runtime_mod_setting_changed, function(event)
  if event.setting ~= controller.SETTING then
    return
  end
  if settings.global[controller.SETTING].value then
    controller.pass()
  else
    controller.release_all()
  end
end)

-- Стенд для тестов внутри игры — только в отладочной сборке: сценарии
-- запускает мод `factorio-test`, когда он включён. В релизе `tests/` нет, и
-- установленный у игрока `factorio-test` не заставит мод искать тесты.
if debug_build and script.active_mods['factorio-test'] then
  -- Сценарии ждут передачу по ~950 тиков, и не по разу: дефолтной минуты на
  -- тест не хватает.
  require('__factorio-test__/init')({
    'tests.ingame.core',
    'tests.ingame.perf',
    'tests.ingame.groups',
    'tests.ingame.lines',
    'tests.ingame.gui',
  }, { default_timeout = 5 * 60 * 60 })
end
