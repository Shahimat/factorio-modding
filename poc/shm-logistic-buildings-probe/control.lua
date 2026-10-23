-- Точка входа прототипа: консольная команда и вывод отчёта. Логики проверок
-- здесь нет — она в `checks/<тема>.lua`, по одному файлу на тему, и каждый
-- подключается одной строкой ниже.

local report = require('report')
local registry = require('registry')

-- Модули проверок: одна строка на тему.
require('checks.self')

local COMMAND = 'shm-probe'
local HELP = 'без аргументов — список проверок и версия; `all` — прогон всех;'
  .. ' иначе имена проверок через пробел'

--- Строки уходят и в чат, и в лог: в чате владелец видит их сразу, из
--- `factorio-current.log` они кладутся в пруфы цели.
local function writer_for(player)
  return function(line)
    log(line)
    if player ~= nil then
      player.print(line)
    else
      game.print(line)
    end
  end
end

local function arguments(parameter)
  local args = {}
  if parameter == nil then
    return args
  end
  for word in string.gmatch(parameter, '%S+') do
    table.insert(args, word)
  end
  return args
end

--- Ответ на команду без аргументов: в какой игре мы исполняемся и что умеем.
local function describe(write)
  local mods = script.active_mods
  write(report.version(
    mods[report.MOD_NAME],
    mods['base'],
    mods['space-age']
  ))
  for _, entry in ipairs(registry.list()) do
    write(report.listing(entry.name, entry.description))
  end
end

local function handle(event)
  local player = nil
  if event.player_index ~= nil then
    player = game.get_player(event.player_index)
  end

  local write = writer_for(player)
  local args = arguments(event.parameter)

  if #args == 0 then
    describe(write)
    return
  end

  registry.run(args, write)
end

commands.add_command(COMMAND, HELP, handle)

-- Стенд для тестов внутри игры: сценарии запускает мод `factorio-test`, когда
-- он активен, то есть только под `npm run test:ingame`. Зависимостью
-- прототипа он не объявляется и в обычной игре ничего не делает — convention
-- `testing`, раздел «Интеграционные тесты в игре».
if script.active_mods['factorio-test'] then
  require('__factorio-test__/init')({ 'tests.stand' })
end
