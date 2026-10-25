-- Имена стартовых настроек мода — общие для `settings.lua` и стадий данных.

local names = {}

local PREFIX = 'shm-advanced-belts-'

function names.tier(key, field)
  return PREFIX .. key .. '-' .. field
end

names.PRICE_DIVISOR = PREFIX .. 'aai-price-divisor'
names.LOADERS_IN_BELT_TECHNOLOGIES = PREFIX .. 'loaders-in-belt-technologies'
names.STACKING = PREFIX .. 'loader-stacking'
names.FULL_STACK = PREFIX .. 'full-stack'
names.FULL_STACK_DEFAULT = PREFIX .. 'full-stack-default'

return names
