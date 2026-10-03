-- Минимальный харнесс для Lua-тестов модов. Внешних зависимостей нет —
-- тот же принцип, что у `node:test` для инструментов, convention `testing`.
--
-- Тесты исполняются сразу при объявлении: отложенный реестр потребовал бы
-- вдвое больше кода и ничего бы не дал, пока тестов на мод десятки.
--
-- Код держится в границах Lua 5.2: игра исполняет именно его, и харнесс не
-- должен быть тем местом, где правило нарушено.

local harness = {}

local results = {}
local prefix = nil

local function qualified(name)
  if prefix == nil then
    return name
  end
  return prefix .. ': ' .. name
end

local function render(value, seen)
  local kind = type(value)
  if kind == 'string' then
    return string.format('%q', value)
  end
  if kind ~= 'table' then
    return tostring(value)
  end

  seen = seen or {}
  if seen[value] then
    return '<цикл>'
  end
  seen[value] = true

  local keys = {}
  for key in pairs(value) do
    table.insert(keys, key)
  end
  table.sort(keys, function(a, b)
    return tostring(a) < tostring(b)
  end)

  local parts = {}
  for _, key in ipairs(keys) do
    table.insert(parts, tostring(key) .. ' = ' .. render(value[key], seen))
  end
  return '{ ' .. table.concat(parts, ', ') .. ' }'
end

local function deep_equal(a, b)
  if a == b then
    return true
  end
  if type(a) ~= 'table' or type(b) ~= 'table' then
    return false
  end

  for key, value in pairs(a) do
    if not deep_equal(value, b[key]) then
      return false
    end
  end
  for key in pairs(b) do
    if a[key] == nil then
      return false
    end
  end
  return true
end

--- Группирует тесты и добавляет имя группы к именам случаев.
function harness.describe(name, body)
  local outer = prefix
  prefix = outer == nil and name or (outer .. ': ' .. name)
  local ok, err = pcall(body)
  prefix = outer
  if not ok then
    table.insert(results, {
      name = qualified(name),
      ok = false,
      message = 'группа упала вне теста: ' .. tostring(err),
    })
  end
end

--- Один проверяемый случай. Падение внутри превращается в запись, а не в
--- остановку прогона: остальные тесты файла всё равно нужно увидеть.
function harness.it(name, body)
  local ok, err = pcall(body)
  if ok then
    table.insert(results, { name = qualified(name), ok = true })
  else
    table.insert(results, {
      name = qualified(name),
      ok = false,
      message = tostring(err),
    })
  end
end

function harness.assert_eq(actual, expected, note)
  if not deep_equal(actual, expected) then
    local text = 'ожидалось ' .. render(expected) .. ', получено ' .. render(actual)
    if note ~= nil then
      text = note .. ' — ' .. text
    end
    error(text, 2)
  end
end

function harness.assert_true(value, note)
  if value ~= true then
    error((note or 'ожидалось true') .. ', получено ' .. render(value), 2)
  end
end

function harness.assert_false(value, note)
  if value ~= false then
    error((note or 'ожидалось false') .. ', получено ' .. render(value), 2)
  end
end

function harness.assert_nil(value, note)
  if value ~= nil then
    error((note or 'ожидался nil') .. ', получено ' .. render(value), 2)
  end
end

--- Ждёт падения. `fragment` — устойчивая часть сообщения, не текст целиком:
--- тесты не должны ломаться от правки формулировки, convention `testing`.
function harness.assert_error(body, fragment)
  local ok, err = pcall(body)
  if ok then
    error('ожидалось падение, но вызов прошёл', 2)
  end
  if fragment ~= nil and not string.find(tostring(err), fragment, 1, true) then
    error(
      'падение есть, но без фрагмента ' .. render(fragment) .. ': ' .. tostring(err),
      2
    )
  end
end

--- Ставит функции харнесса глобальными, чтобы файл теста начинался сразу с
--- `describe`, без строки импорта.
function harness.install(env)
  local target = env or _G
  for _, name in ipairs({
    'describe',
    'it',
    'assert_eq',
    'assert_true',
    'assert_false',
    'assert_nil',
    'assert_error',
  }) do
    target[name] = harness[name]
  end
end

function harness.results()
  return results
end

function harness.reset()
  results = {}
  prefix = nil
end

harness.render = render
harness.deep_equal = deep_equal

return harness
