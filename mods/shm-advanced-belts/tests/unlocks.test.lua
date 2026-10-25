local unlocks = require('logic.unlocks')

local function unlock(recipe)
  return { type = 'unlock-recipe', recipe = recipe }
end

local function raw()
  return {
    ['transport-belt'] = {
      ['transport-belt'] = { speed = 0.03125 },
      ['fast-transport-belt'] = { speed = 0.0625 },
    },
    ['loader-1x1'] = {
      ['aai-loader'] = { speed = 0.03125 },
      ['aai-fast-loader'] = { speed = 0.0625 },
    },
    item = {
      ['transport-belt'] = { place_result = 'transport-belt' },
      ['fast-transport-belt'] = { place_result = 'fast-transport-belt' },
      ['aai-loader'] = { place_result = 'aai-loader' },
      ['aai-fast-loader'] = { place_result = 'aai-fast-loader' },
      ['iron-plate'] = {},
    },
    recipe = {
      ['transport-belt'] = { name = 'transport-belt', results = { { type = 'item', name = 'transport-belt', amount = 2 } } },
      ['fast-transport-belt'] = { name = 'fast-transport-belt', results = { { type = 'item', name = 'fast-transport-belt', amount = 1 } } },
      ['aai-loader'] = {
        name = 'aai-loader',
        ingredients = { { type = 'item', name = 'transport-belt', amount = 1 }, { type = 'item', name = 'iron-plate', amount = 5 } },
        results = { { type = 'item', name = 'aai-loader', amount = 1 } },
      },
      -- Рецепт без ленты: лента находится по скорости.
      ['aai-fast-loader'] = {
        name = 'aai-fast-loader',
        ingredients = { { type = 'item', name = 'aai-loader', amount = 1 } },
        results = { { type = 'item', name = 'aai-fast-loader', amount = 1 } },
      },
    },
    technology = {
      logistics = { effects = { unlock('transport-belt') } },
      ['logistics-2'] = { effects = { unlock('fast-transport-belt') }, prerequisites = { 'logistics' } },
      ['aai-loader'] = { effects = { unlock('aai-loader') }, prerequisites = { 'logistics' } },
      ['aai-fast-loader'] = { effects = { unlock('aai-fast-loader') }, prerequisites = { 'aai-loader', 'logistics-2' } },
      ['next-thing'] = { effects = {}, prerequisites = { 'aai-fast-loader', 'logistics-2' } },
    },
  }
end

local function unlocks_recipe(tech, recipe)
  for _, effect in ipairs(tech.effects) do
    if effect.recipe == recipe then
      return true
    end
  end
  return false
end

describe('лоадеры в технологиях лент', function()
  it('рецепт лоадера открывается технологией его ленты', function()
    local r = raw()
    unlocks.apply(r)
    assert_true(unlocks_recipe(r.technology.logistics, 'aai-loader'))
    assert_true(unlocks_recipe(r.technology['logistics-2'], 'aai-fast-loader'))
  end)

  it('лента находится по скорости, если в рецепте её нет', function()
    local r = raw()
    local moved = unlocks.apply(r)
    assert_eq(moved['aai-fast-loader'], 'logistics-2')
  end)

  it('пустые технологии лоадеров спрятаны', function()
    local r = raw()
    unlocks.apply(r)
    assert_true(r.technology['aai-loader'].hidden)
    assert_true(r.technology['aai-fast-loader'].hidden)
  end)

  it('пререквизиты на спрятанные технологии заменены технологиями лент без дублей', function()
    local r = raw()
    unlocks.apply(r)
    assert_eq(r.technology['next-thing'].prerequisites, { 'logistics-2' })
  end)

  it('технология лоадера с другими эффектами не прячется', function()
    local r = raw()
    table.insert(r.technology['aai-loader'].effects, unlock('something-else'))
    unlocks.apply(r)
    assert_nil(r.technology['aai-loader'].hidden)
    assert_false(unlocks_recipe(r.technology['aai-loader'], 'aai-loader'))
  end)

  it('рецепт ленты открыт с начала игры — берётся технология её подземки', function()
    local r = raw()
    r.technology.logistics.effects = { unlock('underground-belt') }
    r['transport-belt']['transport-belt'].related_underground_belt = 'underground-belt'
    r.item['underground-belt'] = { place_result = 'underground-belt' }
    r.recipe['underground-belt'] = { name = 'underground-belt', results = { { type = 'item', name = 'underground-belt', amount = 2 } } }
    unlocks.apply(r)
    assert_true(unlocks_recipe(r.technology.logistics, 'aai-loader'))
    assert_true(r.technology['aai-loader'].hidden)
  end)

  it('две ленты одной скорости и ленты нет в рецепте — лоадер не трогается', function()
    local r = raw()
    r['transport-belt']['other-fast-belt'] = { speed = 0.0625 }
    r.item['other-fast-belt'] = { place_result = 'other-fast-belt' }
    unlocks.apply(r)
    assert_nil(r.technology['aai-fast-loader'].hidden)
    assert_true(unlocks_recipe(r.technology['aai-fast-loader'], 'aai-fast-loader'))
  end)
end)
