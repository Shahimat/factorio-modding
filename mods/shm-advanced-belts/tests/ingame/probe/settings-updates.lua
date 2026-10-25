-- Зонд стенда: фиксирует настройки штатным для чужого мода способом.
-- `forced_value` есть только у булевых настроек; строковую фиксирует
-- единственное разрешённое значение.

local mode = data.raw['string-setting']['aai-loaders-mode']
mode.hidden = true
mode.default_value = 'expensive'
mode.allowed_values = { 'expensive' }

local function force(name, value)
  local setting = data.raw['bool-setting'][name]
  setting.hidden = true
  setting.forced_value = value
end

force('shm-advanced-belts-ultra-enabled', false)
force('shm-advanced-belts-loaders-in-belt-technologies', true)
