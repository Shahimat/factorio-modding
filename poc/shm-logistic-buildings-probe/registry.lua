-- Реестр проверок прототипа и их прогон.
--
-- Модуль темы (`checks/<тема>.lua`) регистрирует свои проверки сам, а
-- `control.lua` подключает его одной строкой. Порядок прогона — порядок
-- регистрации: он предсказуем и не зависит от имён.
--
-- Прогон пишет не в чат, а в переданную функцию вывода. Поэтому один и тот
-- же реестр обслуживает и консольную команду, и сценарий стенда в игре
-- (цель 1.2 итерации): к `game` и `script` модуль не обращается.

local report = require('report')

local registry = {}

local order = {}
local by_name = {}

--- Регистрирует проверку. Тело возвращает `status, note`, где `status` — один
--- из статусов результата `report`. Ошибки каркаса роняют загрузку мода
--- сразу: молча потерянная проверка хуже, чем мод, который не завёлся.
function registry.add(name, description, body)
  if type(name) ~= 'string' or name == '' then
    error('имя проверки должно быть непустой строкой', 2)
  end
  if string.find(name, '%s') ~= nil or string.find(name, '|', 1, true) ~= nil then
    error('имя проверки без пробелов и без разделителя отчёта: ' .. name, 2)
  end
  if type(description) ~= 'string' or description == '' then
    error('проверке ' .. name .. ' нужно описание одной строкой', 2)
  end
  if type(body) ~= 'function' then
    error('проверка ' .. name .. ' должна быть функцией', 2)
  end
  if by_name[name] ~= nil then
    error('проверка ' .. name .. ' уже зарегистрирована', 2)
  end

  local entry = { name = name, description = description, body = body }
  by_name[name] = entry
  table.insert(order, entry)
  return entry
end

function registry.count()
  return #order
end

--- Список проверок для вывода: имя и описание, без тел.
function registry.list()
  local out = {}
  for _, entry in ipairs(order) do
    table.insert(out, { name = entry.name, description = entry.description })
  end
  return out
end

--- Разбирает запрошенные имена. `nil`, пустой список и `all` означают все
--- проверки. Возвращает найденные записи и имена, которых в реестре нет.
function registry.resolve(names)
  if names == nil or #names == 0 or (#names == 1 and names[1] == 'all') then
    local all = {}
    for _, entry in ipairs(order) do
      table.insert(all, entry)
    end
    return all, {}
  end

  local found = {}
  local unknown = {}
  for _, name in ipairs(names) do
    local entry = by_name[name]
    if entry == nil then
      table.insert(unknown, name)
    else
      table.insert(found, entry)
    end
  end
  return found, unknown
end

--- Прогон. Падение проверки становится строкой `сбой`, а не остановкой
--- прогона: остальные проверки всё равно нужно увидеть — тот же принцип, что
--- у харнесса Lua-тестов.
function registry.run(names, writer)
  local targets, unknown = registry.resolve(names)
  local counts = report.empty_counts()

  for _, name in ipairs(unknown) do
    counts[report.CRASH] = counts[report.CRASH] + 1
    writer(report.line(report.CRASH, name, 'такой проверки нет'))
  end

  for _, entry in ipairs(targets) do
    local ok, status, note = pcall(entry.body)
    if not ok then
      status, note = report.CRASH, 'упала с ошибкой: ' .. tostring(status)
    elseif not report.is_result(status) then
      status, note = report.CRASH, 'вернула неизвестный статус ' .. tostring(status)
    end
    counts[status] = counts[status] + 1
    writer(report.line(status, entry.name, note))
  end

  writer(report.total(counts))
  return counts
end

--- Сбрасывает реестр. Нужен тестам: внутри игры реестр собирается заново при
--- каждой загрузке мода.
function registry.reset()
  order = {}
  by_name = {}
end

return registry
