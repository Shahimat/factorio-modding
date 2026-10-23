-- Самодиагностика каркаса: отвечает на вопрос «оснастка вообще работает»,
-- до того как от прототипа ждут ответов про механику игры. Проверки механик
-- приносят цели 1.3–1.6 итерации 01, каждая своим файлом темы.

local report = require('report')
local registry = require('registry')

registry.add(
  'self/runtime',
  'игровой API отвечает: есть game, script, номер тика и список активных модов',
  function()
    if game == nil then
      return report.FAIL, 'глобальная game недоступна'
    end
    if type(game.tick) ~= 'number' then
      return report.FAIL, 'game.tick не число: ' .. tostring(game.tick)
    end
    if script == nil then
      return report.FAIL, 'глобальная script недоступна'
    end

    local mods = script.active_mods
    if type(mods) ~= 'table' then
      return report.FAIL, 'script.active_mods не таблица'
    end

    local count = 0
    for _ in pairs(mods) do
      count = count + 1
    end
    if mods[report.MOD_NAME] == nil then
      return report.FAIL, 'прототипа нет в списке активных модов'
    end

    return report.OK, string.format('тик %d, активных модов %d', game.tick, count)
  end
)

registry.add(
  'self/report-format',
  'строка отчёта собирается в едином формате, мусор в пояснении гасится',
  function()
    local expected = '[shm-probe] ок | пример | пояснение'
    local actual = report.line(report.OK, 'пример', 'пояснение')
    if actual ~= expected then
      return report.FAIL, 'ожидалось «' .. expected .. '», получено «' .. actual .. '»'
    end

    if report.line(report.OK, 'пример', nil) ~= '[shm-probe] ок | пример | —' then
      return report.FAIL, 'пустое пояснение не превратилось в «—»'
    end

    -- Пояснение с переводом строки и разделителем не должно ломать разбор:
    -- полей остаётся три, перевод строки исчезает.
    local dirty = report.line(report.OK, 'пример', 'две\nстроки и ' .. report.SEPARATOR .. ' разделитель')
    if string.find(dirty, '\n', 1, true) ~= nil then
      return report.FAIL, 'перевод строки в пояснении не погашен'
    end
    local _, escaped = string.gsub(dirty, '/', '')
    if escaped ~= 1 then
      return report.FAIL, 'разделитель в пояснении не погашен: ' .. dirty
    end
    local _, separators = string.gsub(dirty, '|', '')
    if separators ~= 2 then
      return report.FAIL, 'полей в строке не три: ' .. dirty
    end

    return report.OK, 'формат, пустое пояснение и гашение разделителя на месте'
  end
)
