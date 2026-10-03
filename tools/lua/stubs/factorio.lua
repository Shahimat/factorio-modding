-- Заглушки игрового API для Lua-тестов. Намеренно минимальны: по convention
-- `testing` тестируется чистая логика, а обращения к `game` / `script` /
-- `storage` живут в тонкой обёртке. Заглушки нужны для той редкой логики,
-- которая обёрткой не изолируется, и расширяются по факту появления такого
-- кода — не на опережение.
--
-- Полноценной моделью игры это не является и не станет: проверка поведения в
-- настоящем рантайме — пункт DoD вида `proof`, convention `spec-program`.

local stubs = {}

--- Ставит глобальные `defines`, `script`, `storage` и `game` и возвращает
--- дескриптор для проверок: `handle.events`, `handle.printed`.
function stubs.install()
  local handle = {
    events = {},
    printed = {},
  }

  _G.defines = {
    events = {
      on_tick = 'on_tick',
      on_built_entity = 'on_built_entity',
      on_entity_died = 'on_entity_died',
      on_gui_click = 'on_gui_click',
    },
    direction = {
      north = 0,
      east = 2,
      south = 4,
      west = 6,
    },
    inventory = {
      chest = 1,
    },
  }

  _G.storage = {}

  _G.script = {
    on_event = function(event, handler)
      table.insert(handle.events, { event = event, handler = handler })
    end,
    on_init = function(handler)
      handle.on_init = handler
    end,
    on_configuration_changed = function(handler)
      handle.on_configuration_changed = handler
    end,
    mod_name = function()
      return 'shm-test'
    end,
  }

  _G.game = {
    tick = 0,
    print = function(message)
      table.insert(handle.printed, message)
    end,
    players = {},
    surfaces = {},
  }

  return handle
end

--- Убирает заглушки. Вызывать в конце файла теста, чтобы соседний файл не
--- получил чужое состояние: интерпретатор у всех файлов прогона один.
function stubs.remove()
  _G.defines = nil
  _G.storage = nil
  _G.script = nil
  _G.game = nil
end

return stubs
