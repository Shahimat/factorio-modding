-- Стартовые настройки: по тиру — включение, скорость и дальность подземки;
-- общие — делитель цены лоадеров AAI, стак и ожидание полной стопки.
-- Другой мод фиксирует любую из них в своём `settings-updates.lua`:
-- булеву — `forced_value` и `hidden`, числовую — `default_value`,
-- `allowed_values` из одного значения и `hidden` (`forced_value` у числовых
-- и строковых настроек нет).

local defaults = require('logic.defaults')
local names = require('logic.setting-names')

local settings = {}

for index, tier in ipairs(defaults.TIERS) do
  local order = string.format('a-%02d', index)
  local tier_name = { 'shm-advanced-belts.tier-' .. tier.key }
  settings[#settings + 1] = {
    type = 'bool-setting',
    name = names.tier(tier.key, 'enabled'),
    setting_type = 'startup',
    default_value = true,
    order = order .. '-a',
    localised_name = { 'mod-setting-name.shm-advanced-belts-tier-enabled', tier_name },
    localised_description = { 'mod-setting-description.shm-advanced-belts-tier-enabled' },
  }
  settings[#settings + 1] = {
    type = 'int-setting',
    name = names.tier(tier.key, 'speed'),
    setting_type = 'startup',
    default_value = tier.speed,
    allowed_values = defaults.SPEED_CHOICES,
    order = order .. '-b',
    localised_name = { 'mod-setting-name.shm-advanced-belts-tier-speed', tier_name },
    localised_description = { 'mod-setting-description.shm-advanced-belts-tier-speed' },
  }
  settings[#settings + 1] = {
    type = 'int-setting',
    name = names.tier(tier.key, 'underground'),
    setting_type = 'startup',
    default_value = tier.underground,
    minimum_value = 2,
    maximum_value = 100,
    order = order .. '-c',
    localised_name = { 'mod-setting-name.shm-advanced-belts-tier-underground', tier_name },
    localised_description = { 'mod-setting-description.shm-advanced-belts-tier-underground' },
  }
end

settings[#settings + 1] = {
  type = 'int-setting',
  name = names.PRICE_DIVISOR,
  setting_type = 'startup',
  default_value = defaults.PRICE_DIVISOR,
  minimum_value = 1,
  maximum_value = 10,
  order = 'b-a',
}
settings[#settings + 1] = {
  type = 'bool-setting',
  name = names.STACKING,
  setting_type = 'startup',
  default_value = true,
  order = 'c-a',
}
settings[#settings + 1] = {
  type = 'bool-setting',
  name = names.FULL_STACK,
  setting_type = 'startup',
  default_value = true,
  order = 'c-b',
}
settings[#settings + 1] = {
  type = 'bool-setting',
  name = names.FULL_STACK_DEFAULT,
  setting_type = 'startup',
  default_value = true,
  order = 'c-c',
}

data:extend(settings)
