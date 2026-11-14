-- Демо-команда `/shm-orbital-demo` — только в отладочной сборке при
-- включённой настройке «Режим отладки», см. `tests/debug.lua`. Без
-- параметра — статическая сцена (`scene.lua`), `check` — сверить итог,
-- `live` — живая сцена с перелётами (`live.lua`), `status` — её состояние,
-- `network` — планетарная сеть, `network-clear` — только её объекты,
-- `clear` — объекты всех демо-сцен. Грунт и разрешения силы не откатываются.
-- Строки идут и в чат, и в лог с меткой `[OL-DEMO]`.

local scene = require('tests.demo.scene')
local live = require('tests.demo.live')
local network = require('tests.demo.network')

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
  if (parameter == 'network' or parameter == 'network-clear' or parameter == 'clear') and player and not player.admin then
    write('Демо-сеть может создавать и убирать только администратор тестовой карты.')
    return
  end
  if parameter == 'clear' then
    write('Orbital Logistics demo: убрано платформ ' .. (scene.clear(force) + live.clear(force) + network.clear(force)))
  elseif parameter == 'network-clear' then
    write('Orbital Logistics network: убрано платформ ' .. network.clear(force) .. ' и созданные планетарные ячейки.')
  elseif parameter == 'network' then
    local ok, result = pcall(network.build, force, event.tick)
    if ok then
      for _, line in ipairs(result) do write(line) end
    else
      write('Демо-сеть не создана: ' .. tostring(result))
    end
  elseif parameter == 'live' then
    for _, line in ipairs(live.build(force, event.tick)) do
      write(line)
    end
  elseif parameter == 'status' then
    for _, line in ipairs(live.status(force)) do
      write(line)
    end
    for _, line in ipairs(network.status(force)) do write(line) end
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
  elseif parameter == nil or parameter == '' then
    local lines = scene.build(force)
    remote.call('shm-orbital-logistics', 'pass')
    for _, line in ipairs(lines) do
      write(line)
    end
  else
    write('/shm-orbital-demo: check, live, network, status, network-clear, clear')
  end
end

--- Раз в `live.PERIOD` тиков: защита демо-платформ и шаг живой сцены.
function commands_module.on_tick(event)
  for _, force in pairs(game.forces) do
    live.shield(force)
    network.step(force)
    for _, line in ipairs(live.step(force, event.tick)) do
      log('[OL-DEMO] ' .. line)
      game.print(line)
    end
  end
end

commands_module.PERIOD = live.PERIOD

function commands_module.register()
  commands.add_command(commands_module.NAME,
    'Orbital Logistics (debug): demo scene; check, live, network, status, network-clear, clear', commands_module.handle)
end

return commands_module
