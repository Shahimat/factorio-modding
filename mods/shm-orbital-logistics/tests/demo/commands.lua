-- Демо-команда `/shm-orbital-demo` — только в отладочной сборке при
-- включённой настройке «Режим отладки», см. `tests/debug.lua`. Без
-- параметра — статическая сцена (`scene.lua`), `check` — сверить итог,
-- `live` — живая сцена с перелётами (`live.lua`), `status` — её состояние,
-- `clear` — убрать всё. Строки идут и в чат, и в лог с меткой `[OL-DEMO]`.

local scene = require('tests.demo.scene')
local live = require('tests.demo.live')

local commands_module = {}

commands_module.NAME = 'shm-orbital-demo'

local function writer(player)
  return function(line)
    log('[OL-DEMO] ' .. line)
    if player then
      player.print(line)
    else
      game.print(line)
    end
  end
end

function commands_module.handle(event)
  local player = event.player_index and game.get_player(event.player_index)
  local force = player and player.force or game.forces['player']
  local write = writer(player)
  local parameter = event.parameter
  if parameter == 'clear' then
    write('Orbital Logistics demo: убрано платформ ' .. (scene.clear(force) + live.clear(force)))
  elseif parameter == 'live' then
    for _, line in ipairs(live.build(force, event.tick)) do
      write(line)
    end
  elseif parameter == 'status' then
    for _, line in ipairs(live.status(force)) do
      write(line)
    end
  elseif parameter == 'check' then
    local passed = 0
    local results = scene.check(force)
    for _, result in ipairs(results) do
      if result.ok then
        passed = passed + 1
      end
      write((result.ok and '[color=green]✔[/color] ' or '[color=red]✘[/color] ') .. result.name .. ' — ' .. result.expect)
    end
    write(string.format('Orbital Logistics demo: как ожидается %d из %d', passed, #results))
  else
    local lines = scene.build(force)
    remote.call('shm-orbital-logistics', 'pass')
    for _, line in ipairs(lines) do
      write(line)
    end
  end
end

--- Раз в `live.PERIOD` тиков: защита демо-платформ и шаг живой сцены.
function commands_module.on_tick(event)
  for _, force in pairs(game.forces) do
    live.shield(force)
    for _, line in ipairs(live.step(force, event.tick)) do
      log('[OL-DEMO] ' .. line)
      game.print(line)
    end
  end
end

commands_module.PERIOD = live.PERIOD

function commands_module.register()
  commands.add_command(commands_module.NAME,
    'Orbital Logistics (debug): demo scene; check, live, status, clear', commands_module.handle)
end

return commands_module
