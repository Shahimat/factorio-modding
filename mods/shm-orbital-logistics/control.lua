-- Точка входа: контроллер на проходе раз в секунду и на смене состояния
-- платформы — прилёт, отлёт, ожидание на орбите.

local controller = require('runtime.controller')

local PASS_TICKS = 60

script.on_init(function()
  storage.platforms = {}
end)

script.on_configuration_changed(function()
  storage.platforms = storage.platforms or {}
end)

script.on_nth_tick(PASS_TICKS, controller.pass)

script.on_event(defines.events.on_space_platform_changed_state, controller.pass)

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

-- Стенд для тестов внутри игры: сценарии запускает мод `factorio-test`, когда
-- он включён. В зависимостях мода он не объявляется, в обычной игре ничего не
-- делает, а `tests/` в zip релиза не попадает.
if script.active_mods['factorio-test'] then
  -- Сценарии ждут передачу по ~950 тиков, и не по разу: дефолтной минуты на
  -- тест не хватает.
  require('__factorio-test__/init')({
    'tests.ingame.core',
  }, { default_timeout = 5 * 60 * 60 })
end
