-- Значения тиров по умолчанию. Скорость, дальность подземки и включение
-- меняет игрок настройками, всё остальное — другие моды через API
-- `ShmAdvancedBelts` (`logic/api.lua`).
--
-- Рецепты — по образцу турбо: в `ingredients` только ресурсы тира, предмет
-- предыдущего тира добавляется сборщиком в количестве `previous`.
--
-- Цвета продублированы в `tools/lib/recolor-jobs.ts` для картинки мода:
-- при правке менять в обоих местах.

local defaults = {}

--- Колбы технологии турбо-лент; колбы тиров добавляются к ним по порядку.
defaults.TURBO_PACKS = {
  'automation-science-pack',
  'logistic-science-pack',
  'chemical-science-pack',
  'production-science-pack',
  'space-science-pack',
  'metallurgic-science-pack',
}

--- Категории рецептов: сборочный автомат с жидкостью и всё, что умеет
--- `metallurgy` (литейка и, например, продвинутая печь K2).
defaults.CATEGORIES = { 'crafting-with-fluid', 'metallurgy' }

--- Расход лубриканта лоадером AAI в минуту на 1 предм./с: у турбо — 0,25 на 60.
defaults.LUBRICANT_PER_ITEM_RATE = 0.25 / 60

local function item(name, amount)
  return { type = 'item', name = name, amount = amount }
end

local function lubricant(amount)
  return { type = 'fluid', name = 'lubricant', amount = amount }
end

local function times(ingredients, factor)
  local result = {}
  for i, ingredient in ipairs(ingredients) do
    result[i] = { type = ingredient.type, name = ingredient.name, amount = ingredient.amount * factor }
  end
  return result
end

--- Рецепты ленты, подземки и сплиттера по образцу турбо и лоадера AAI по
--- образцу турбо-лоадера AAI. `plate` — ресурс тира, `part` — деталь
--- сплиттера и лоадера.
local function planet_recipes(plate, part)
  local loader = { item(plate, 30), item(part, 5), lubricant(50) }
  return {
    belt = { ingredients = { item(plate, 5), lubricant(20) }, previous = 1, results = 1, energy_required = 0.5 },
    underground = { ingredients = { item(plate, 40), lubricant(40) }, previous = 2, results = 2, energy_required = 2 },
    splitter = {
      ingredients = { item(plate, 15), item(part, 2), lubricant(80) },
      previous = 1,
      results = 1,
      energy_required = 2,
    },
    loader = { ingredients = loader, energy_required = 2 },
    loader_expensive = { ingredients = times(loader, 10), energy_required = 10 },
  }
end

local function absolute_recipes()
  local loader = { item('speed-module-3', 5), item('biter-egg', 10), lubricant(50) }
  return {
    belt = {
      ingredients = { item('speed-module-3', 1), item('biter-egg', 4), lubricant(80) },
      previous = 4,
      results = 4,
      energy_required = 2,
    },
    underground = {
      ingredients = { item('speed-module-3', 2), item('biter-egg', 8), lubricant(80) },
      previous = 2,
      results = 2,
      energy_required = 2,
    },
    splitter = {
      ingredients = { item('speed-module-3', 2), item('biter-egg', 4), lubricant(80) },
      previous = 1,
      results = 1,
      energy_required = 2,
    },
    loader = { ingredients = loader, energy_required = 2 },
    loader_expensive = { ingredients = times(loader, 10), energy_required = 10 },
  }
end

--- Тиры по порядку. `import_location` — планета тира для доставки на
--- платформы, `pack` — колба планеты тира, `prerequisites` — технологии,
--- кроме предыдущего тира, без которых ресурсы тира недоступны.
defaults.TIERS = {
  {
    key = 'superior',
    import_location = 'fulgora',
    speed = 90,
    underground = 13,
    color = { 210, 1, 247 },
    pack = 'electromagnetic-science-pack',
    technology = {
      count = 1000,
      time = 60,
      prerequisites = { 'electromagnetic-science-pack', 'holmium-processing', 'electromagnetic-plant' },
    },
    loader_technology = { count = 1000, time = 15 },
    recipes = planet_recipes('holmium-plate', 'supercapacitor'),
  },
  {
    key = 'ultra',
    import_location = 'gleba',
    speed = 105,
    underground = 15,
    color = { 255, 110, 0 },
    pack = 'agricultural-science-pack',
    technology = {
      count = 1500,
      time = 60,
      prerequisites = { 'agricultural-science-pack', 'carbon-fiber' },
    },
    loader_technology = { count = 1500, time = 15 },
    recipes = planet_recipes('carbon-fiber', 'processing-unit'),
  },
  {
    key = 'hyper',
    import_location = 'aquilo',
    speed = 135,
    underground = 17,
    color = { 160, 235, 255 },
    pack = 'cryogenic-science-pack',
    technology = {
      count = 2000,
      time = 60,
      prerequisites = { 'cryogenic-science-pack', 'lithium-processing', 'quantum-processor' },
    },
    loader_technology = { count = 2000, time = 15 },
    recipes = planet_recipes('lithium-plate', 'quantum-processor'),
  },
  {
    key = 'absolute',
    import_location = 'nauvis',
    speed = 150,
    underground = 19,
    color = { 20, 40, 170 },
    pack = 'promethium-science-pack',
    technology = {
      count = 2500,
      time = 60,
      prerequisites = { 'promethium-science-pack', 'biter-egg-handling', 'speed-module-3' },
    },
    loader_technology = { count = 2500, time = 15 },
    recipes = absolute_recipes(),
  },
}

--- Скорости в списке настройки: кратные 15 — только они целые при шаге
--- движка 1,875 предм./с.
defaults.SPEED_CHOICES = {}
for speed = 60, 240, 15 do
  defaults.SPEED_CHOICES[#defaults.SPEED_CHOICES + 1] = speed
end

defaults.PRICE_DIVISOR = 5

return defaults
