-- Единый формат строки отчёта прототипа. Формат один на все проверки
-- итерации: вывод читается глазами в чате и в логе, а в сводку разбирается
-- одним парсером.
--
--     [shm-probe] <статус> | <имя> | <пояснение>
--
-- Полей всегда три: пустое пояснение превращается в `—`, а разделитель и
-- переводы строк внутри полей гасятся — иначе строка перестаёт разбираться.
--
-- Модуль чистый: к `game`, `script` и `storage` не обращается, поэтому его
-- можно гонять и юнит-тестом, и внутри игры.

local report = {}

report.MOD_NAME = 'shm-logistic-buildings-probe'
report.PREFIX = '[shm-probe]'
report.SEPARATOR = ' | '
report.EMPTY = '—'

-- Статусы результата проверки.
report.OK = 'ок'
report.FAIL = 'нет'
report.SKIP = 'пропуск'
report.CRASH = 'сбой'

-- Служебные статусы: шапка прогона, строка списка, итог.
report.VERSION = 'версия'
report.LISTING = 'проверка'
report.TOTAL = 'итог'

--- Порядок счётчиков в итоговой строке.
report.RESULT_ORDER = { report.OK, report.FAIL, report.SKIP, report.CRASH }

local RESULT = {}
for _, status in ipairs(report.RESULT_ORDER) do
  RESULT[status] = true
end

local SERVICE = {
  [report.VERSION] = true,
  [report.LISTING] = true,
  [report.TOTAL] = true,
}

--- Статус результата проверки, а не служебной строки.
function report.is_result(status)
  return RESULT[status] == true
end

function report.is_status(status)
  return RESULT[status] == true or SERVICE[status] == true
end

--- Готовит поле строки: гасит разделитель, переводы строк и табы, сводит
--- пробелы и срезает краевые.
local function field(value)
  local text = value == nil and '' or tostring(value)
  text = string.gsub(text, '|', '/')
  text = string.gsub(text, '%s+', ' ')
  text = string.gsub(text, '^%s*(.-)%s*$', '%1')
  return text
end

report.field = field

--- Строка отчёта. Статус не валидируется: решение, что делать с неизвестным,
--- принимает `registry`, а печатать надо даже сломанный ответ.
function report.line(status, name, note)
  local tail = field(note)
  if tail == '' then
    tail = report.EMPTY
  end
  return table.concat({
    report.PREFIX .. ' ' .. field(status),
    field(name),
    tail,
  }, report.SEPARATOR)
end

--- Шапка прогона: версия прототипа и то, в какой игре он исполняется.
--- Версии приходят из `script.active_mods`, отсутствующий мод — `nil`.
function report.version(mod_version, base_version, space_age_version)
  local note = 'игра ' .. (base_version or 'неизвестно')
  if space_age_version == nil then
    note = note .. ', space-age нет'
  else
    note = note .. ', space-age ' .. space_age_version
  end
  return report.line(
    report.VERSION,
    report.MOD_NAME .. ' ' .. (mod_version or 'неизвестно'),
    note
  )
end

--- Строка списка доступных проверок.
function report.listing(name, description)
  return report.line(report.LISTING, name, description)
end

function report.empty_counts()
  local counts = {}
  for _, status in ipairs(report.RESULT_ORDER) do
    counts[status] = 0
  end
  return counts
end

--- Итог прогона. Последнее слово — «готово»: по нему видно, что прогон дошёл
--- до конца, а не оборвался на середине.
function report.total(counts)
  local parts = {}
  local total = 0
  for _, status in ipairs(report.RESULT_ORDER) do
    local value = counts[status] or 0
    total = total + value
    table.insert(parts, status .. ' ' .. tostring(value))
  end
  return report.line(
    report.TOTAL,
    'проверок ' .. tostring(total),
    table.concat(parts, ', ') .. ' — готово'
  )
end

return report
