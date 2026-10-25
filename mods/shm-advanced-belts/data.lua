-- Публичный API для других модов и клавиша переключения режима полной
-- стопки. Сами тиры собираются в `data-updates.lua` — после того как
-- зависимые моды отработали свой `data.lua` и перенастроили тиры через API.

local api = require('logic.api')
local defaults = require('logic.defaults')
local names = require('logic.setting-names')

local keys = {}
for i, tier in ipairs(defaults.TIERS) do
  keys[i] = tier.key
end

--- Перенастройка тиров из `data.lua` другого мода с зависимостью
--- `? shm-advanced-belts`:
---
---     ShmAdvancedBelts.configure('hyper', { speed = 120, technology = { count = 3000 } })
---     ShmAdvancedBelts.set_enabled('ultra', false)
---
--- Поля тира — в `logic/defaults.lua`, правила — в `logic/api.lua`.
ShmAdvancedBelts = api.new(keys)

if settings.startup[names.FULL_STACK].value then
  data:extend({
    {
      type = 'custom-input',
      name = 'shm-advanced-belts-full-stack-toggle',
      key_sequence = 'SHIFT + M',
      action = 'lua',
    },
  })
end
