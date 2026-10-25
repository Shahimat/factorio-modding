-- Зонд стенда: фиксирует настройки штатным для чужого мода способом.
-- `forced_value` есть только у булевых настроек; строковую фиксирует
-- единственное разрешённое значение.

local mode = data.raw['string-setting']['aai-loaders-mode']
mode.hidden = true
mode.default_value = 'expensive'
mode.allowed_values = { 'expensive' }

local ultra = data.raw['bool-setting']['shm-advanced-belts-ultra-enabled']
ultra.hidden = true
ultra.forced_value = false
