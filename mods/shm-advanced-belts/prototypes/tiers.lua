-- Сборка тиров в `data-updates`: ленты, подземки, сплиттеры, технологии,
-- цепочка улучшений и лоадеры AAI. Конфигурацию собирает `logic/tiers.lua`,
-- здесь только запись в `data.raw`.

local defaults = require('logic.defaults')
local graphics = require('logic.graphics')
local tiers = require('logic.tiers')
local names = require('logic.setting-names')
local recycling = require('prototypes.recycling')

local build = {}

local function player_settings()
  local result = {}
  for _, tier in ipairs(defaults.TIERS) do
    result[tier.key] = {
      enabled = settings.startup[names.tier(tier.key, 'enabled')].value,
      speed = settings.startup[names.tier(tier.key, 'speed')].value,
      underground = settings.startup[names.tier(tier.key, 'underground')].value,
    }
  end
  return result
end

--- Копия прототипа турбо под тир: имя, разборка, перекраска.
local function copy_entity(entity_type, source, name, entry)
  local copy = table.deepcopy(data.raw[entity_type][source])
  local tint = tiers.color01(entry.color)
  copy.name = name
  copy.minable.result = name
  copy.speed = tiers.speed_field(entry.speed)
  copy.factoriopedia_simulation = nil
  copy.localised_name = nil
  copy.localised_description = { 'entity-description.' .. source }
  graphics.recolor(copy, tint)
  graphics.recolor_icons(copy, tint)
  return copy
end

local function copy_item(source, name, entry, position)
  local copy = table.deepcopy(data.raw.item[source])
  copy.name = name
  copy.place_result = name
  copy.default_import_location = entry.import_location
  copy.color_hint = { text = tostring(4 + position) }
  copy.order = copy.order:gsub('d%[turbo%-', 'e[' .. string.format('%02d', position) .. '-shm-')
  graphics.recolor_icons(copy, tiers.color01(entry.color))
  return copy
end

local function recipe(name, spec, previous_item)
  return {
    type = 'recipe',
    name = name,
    categories = tiers.deepcopy(spec.categories or defaults.CATEGORIES),
    enabled = false,
    energy_required = spec.energy_required,
    ingredients = tiers.ingredients(spec, previous_item),
    results = { { type = 'item', name = name, amount = spec.results or 1 } },
  }
end

local function pack_ingredients(packs)
  local result = {}
  for i, pack in ipairs(packs) do
    result[i] = { pack, 1 }
  end
  return result
end

local function technology(entry)
  local source = data.raw.technology[tiers.TURBO.technology]
  local tech = {
    type = 'technology',
    name = entry.names.technology,
    icon = source.icon,
    icon_size = source.icon_size,
    effects = {
      { type = 'unlock-recipe', recipe = entry.names.belt },
      { type = 'unlock-recipe', recipe = entry.names.underground },
      { type = 'unlock-recipe', recipe = entry.names.splitter },
    },
    prerequisites = tiers.prerequisites(entry),
    unit = {
      count = entry.technology.count,
      ingredients = pack_ingredients(entry.packs),
      time = entry.technology.time,
    },
  }
  graphics.recolor_icons(tech, tiers.color01(entry.color))
  return tech
end

local function build_tier(entry, position)
  local n = entry.names
  local belt = copy_entity('transport-belt', tiers.TURBO.belt, n.belt, entry)
  belt.related_underground_belt = n.underground
  belt.next_upgrade = entry.next and entry.next.belt or nil

  local underground = copy_entity('underground-belt', tiers.TURBO.underground, n.underground, entry)
  underground.max_distance = entry.underground
  underground.next_upgrade = entry.next and entry.next.underground or nil

  local splitter = copy_entity('splitter', tiers.TURBO.splitter, n.splitter, entry)
  splitter.related_transport_belt = n.belt
  splitter.next_upgrade = entry.next and entry.next.splitter or nil

  data:extend({
    belt,
    underground,
    splitter,
    copy_item(tiers.TURBO.belt, n.belt, entry, position),
    copy_item(tiers.TURBO.underground, n.underground, entry, position),
    copy_item(tiers.TURBO.splitter, n.splitter, entry, position),
    recipe(n.belt, entry.recipes.belt, entry.previous.belt),
    recipe(n.underground, entry.recipes.underground, entry.previous.underground),
    recipe(n.splitter, entry.recipes.splitter, entry.previous.splitter),
    technology(entry),
  })
  recycling.generate({ n.belt, n.underground, n.splitter })
end

--- Лоадер AAI тира через `AAILoaders.make_tier`.
local function build_loader(entry)
  local n = entry.names
  local previous_loader = data.raw.item[entry.previous.loader] and entry.previous.loader or nil
  local function loader_recipe(spec)
    local ingredients = { { type = 'item', name = n.belt, amount = 1 } }
    if previous_loader then
      ingredients[#ingredients + 1] = { type = 'item', name = previous_loader, amount = 1 }
    end
    for _, ingredient in ipairs(spec.ingredients) do
      ingredients[#ingredients + 1] = tiers.deepcopy(ingredient)
    end
    return {
      categories = tiers.deepcopy(spec.categories or defaults.CATEGORIES),
      ingredients = ingredients,
      energy_required = spec.energy_required,
    }
  end
  local prerequisites = { n.technology }
  if previous_loader and data.raw.technology[entry.previous.loader_technology] then
    prerequisites[#prerequisites + 1] = entry.previous.loader_technology
  end
  local made = AAILoaders.make_tier({
    name = n.loader_tier,
    transport_belt = n.belt,
    color = tiers.color01(entry.color),
    fluid = 'lubricant',
    fluid_per_minute = tiers.items_per_second(tiers.speed_field(entry.speed)) * defaults.LUBRICANT_PER_ITEM_RATE,
    default_import_location = entry.import_location,
    technology = {
      prerequisites = prerequisites,
      unit = {
        count = entry.loader_technology.count,
        ingredients = pack_ingredients(entry.packs),
        time = entry.loader_technology.time,
      },
    },
    recipe = loader_recipe(entry.recipes.loader),
    unlubricated_recipe = loader_recipe(entry.recipes.loader_expensive),
    next_upgrade = entry.next and entry.next.loader or nil,
    -- Своё имя «<Тир> погрузчик» вместо шаблона AAI «<лента> погрузчик»;
    -- AAI отдаёт его и предмету, рецепту и технологии лоадера.
    localised_name = { 'entity-name.' .. n.loader },
  })
  if made and made.recipe then
    recycling.generate({ made.recipe.name })
  end
end

local function link_upgrades(first)
  data.raw['transport-belt'][tiers.TURBO.belt].next_upgrade = first.names.belt
  data.raw['underground-belt'][tiers.TURBO.underground].next_upgrade = first.names.underground
  data.raw.splitter[tiers.TURBO.splitter].next_upgrade = first.names.splitter
end

--- Собирает все включённые тиры. `overrides` — переопределения из API.
function build.run(overrides)
  local configs = tiers.merge(defaults.TIERS, player_settings(), overrides)
  local entries = tiers.resolve(configs, defaults.TURBO_PACKS)
  for _, entry in ipairs(entries) do
    local position = 0
    for i, tier in ipairs(defaults.TIERS) do
      if tier.key == entry.key then
        position = i
      end
    end
    build_tier(entry, position)
  end
  if entries[1] then
    link_upgrades(entries[1])
  end

  local aai_ready = mods['aai-loaders'] and AAILoaders and AAILoaders.make_tier
    and settings.startup['aai-loaders-mode'].value ~= 'graphics-only'
  if aai_ready then
    for _, entry in ipairs(entries) do
      build_loader(entry)
    end
    local turbo_loader = data.raw['loader-1x1'][tiers.TURBO.loader]
    if turbo_loader and entries[1] then
      turbo_loader.next_upgrade = entries[1].names.loader
    end
  end
  return entries
end

return build
