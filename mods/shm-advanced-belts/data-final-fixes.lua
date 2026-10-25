-- Последняя стадия данных: к этому моменту все моды создали свои лоадеры.
-- Делитель цены лоадеров AAI, их открытие технологиями лент, стак на ленте и
-- ожидание полной стопки с копиями для переключателя.

local names = require('logic.setting-names')
local price = require('logic.price')
local recycling = require('prototypes.recycling')
local unlocks = require('logic.unlocks')
local variants = require('logic.variants')

local startup = settings.startup

if mods['aai-loaders'] and startup['aai-loaders-mode'].value == 'expensive' then
  local changed = price.apply(data.raw, startup[names.PRICE_DIVISOR].value)
  local recipe_names = {}
  for i, recipe in ipairs(changed) do
    recipe_names[i] = recipe.name
  end
  recycling.generate(recipe_names)
end

if mods['aai-loaders'] and startup[names.LOADERS_IN_BELT_TECHNOLOGIES].value then
  unlocks.apply(data.raw)
end

local max_stack = data.raw['utility-constants'].default.max_belt_stack_size
if startup[names.STACKING].value and max_stack > 1 then
  variants.apply_stacking(data.raw, max_stack)
end

if startup[names.FULL_STACK].value then
  local created = variants.apply(data.raw, startup[names.FULL_STACK_DEFAULT].value)
  if #created > 0 then
    data:extend(created)
  end
end
