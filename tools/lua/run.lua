-- Запускает Lua-тесты одного мода и печатает результат в формате, который
-- разбирает `tools/lib/lua-test-runner.ts`.
--
-- Вызывается не руками, а из `tools/lua-test.ts`:
--
--     lua tools/lua/run.lua --root <каталог-мода> <файл-теста>...
--
-- Корень мода попадает в `package.path`, поэтому тест требует модули мода по
-- их обычным именам: `require('logic.demand')`. Заглушки игрового API — через
-- `require('stubs.factorio')`.

local args = { ... }

local root = nil
local files = {}

local index = 1
while index <= #args do
  local arg = args[index]
  if arg == '--root' then
    root = args[index + 1]
    index = index + 2
  else
    table.insert(files, arg)
    index = index + 1
  end
end

if root == nil then
  io.stderr:write('run.lua: не передан --root\n')
  os.exit(2)
end

local here = debug.getinfo(1, 'S').source:match('^@(.*)/[^/]*$') or '.'

package.path = table.concat({
  root .. '/?.lua',
  root .. '/?/init.lua',
  here .. '/?.lua',
  here .. '/?/init.lua',
  package.path,
}, ';')

local harness = require('harness')
harness.install()

local failed_to_load = {}

for _, file in ipairs(files) do
  local chunk, load_error = loadfile(file)
  if chunk == nil then
    table.insert(failed_to_load, { file = file, message = tostring(load_error) })
  else
    local ok, run_error = pcall(chunk)
    if not ok then
      table.insert(failed_to_load, { file = file, message = tostring(run_error) })
    end
  end
end

local passed = 0
local failed = 0

for _, result in ipairs(harness.results()) do
  if result.ok then
    passed = passed + 1
    io.write('TEST ok ', result.name, '\n')
  else
    failed = failed + 1
    local message = (result.message or ''):gsub('[\r\n]+', ' ')
    io.write('TEST fail ', result.name, ' :: ', message, '\n')
  end
end

-- Файл, который не загрузился, — тоже упавший тест: иначе синтаксическая
-- ошибка выглядела бы как отсутствие тестов.
for _, broken in ipairs(failed_to_load) do
  failed = failed + 1
  local message = broken.message:gsub('[\r\n]+', ' ')
  io.write('TEST fail ', broken.file, ' :: файл не выполнился: ', message, '\n')
end

io.write('TOTAL ', tostring(passed), ' ', tostring(failed), '\n')

if failed > 0 then
  os.exit(1)
end
