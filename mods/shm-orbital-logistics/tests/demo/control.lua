-- Dev-мод сцены для визуальной проверки: команда `/shm-orbital-demo`
-- расставляет платформы по сценариям, `check` сверяет итог; `live` — живая
-- сцена с перелётами и непрерывным потоком (`live.lua`), `status` — её
-- состояние; `clear` убирает всё.
-- Сама сцена — `scene.lua`, её же строит тест в игре основного мода.

local scene = require('scene')
local live = require('live')

commands.add_command('shm-orbital-demo', 'Orbital Logistics: построить демо-сцену; check — сверить итог; live — живая сцена с перелётами, status — её состояние; clear — убрать всё', function(event)
  local player = event.player_index and game.get_player(event.player_index)
  local force = player and player.force or game.forces['player']
  local write = function(line)
    -- В лог тоже: по `factorio-current.log` итог сцены видно без скриншотов.
    log('[OL-DEMO] ' .. line)
    if player then
      player.print(line)
    else
      game.print(line)
    end
  end
  if event.parameter == 'clear' then
    write('Orbital Logistics demo: убрано платформ ' .. (scene.clear(force) + live.clear(force)))
    return
  end
  if event.parameter == 'live' then
    for _, line in ipairs(live.build(force, event.tick)) do
      write(line)
    end
    return
  end
  if event.parameter == 'status' then
    for _, line in ipairs(live.status(force)) do
      write(line)
    end
    return
  end
  if event.parameter == 'check' then
    local passed = 0
    local results = scene.check(force)
    for _, result in ipairs(results) do
      if result.ok then
        passed = passed + 1
      end
      write((result.ok and '[color=green]✔[/color] ' or '[color=red]✘[/color] ') .. result.name .. ' — ' .. result.expect)
    end
    write(string.format('Orbital Logistics demo: как ожидается %d из %d', passed, #results))
    return
  end
  local lines = scene.build(force)
  remote.call('shm-orbital-logistics', 'pass')
  for _, line in ipairs(lines) do
    write(line)
  end
end)

script.on_nth_tick(live.PERIOD, function(event)
  for _, force in pairs(game.forces) do
    live.shield(force)
    for _, line in ipairs(live.step(force, event.tick)) do
      log('[OL-DEMO] ' .. line)
      game.print(line)
    end
  end
end)
