local price = require('logic.price')

local function raw()
  return {
    ['loader-1x1'] = {
      ['aai-turbo-loader'] = {},
      ['aai-shm-superior-loader'] = {},
      ['kr-loader'] = {},
    },
    item = {
      ['aai-turbo-loader'] = { place_result = 'aai-turbo-loader' },
      ['aai-shm-superior-loader'] = { place_result = 'aai-shm-superior-loader' },
      ['kr-loader'] = { place_result = 'kr-loader' },
      ['iron-plate'] = {},
    },
    recipe = {
      ['aai-shm-superior-loader'] = {
        name = 'aai-shm-superior-loader',
        ingredients = {
          { type = 'item', name = 'shm-superior-transport-belt', amount = 1 },
          { type = 'item', name = 'aai-turbo-loader', amount = 1 },
          { type = 'item', name = 'holmium-plate', amount = 300 },
          { type = 'item', name = 'supercapacitor', amount = 53 },
          { type = 'fluid', name = 'lubricant', amount = 500 },
        },
        results = { { type = 'item', name = 'aai-shm-superior-loader', amount = 1 } },
      },
      ['kr-loader'] = {
        name = 'kr-loader',
        ingredients = { { type = 'item', name = 'iron-plate', amount = 50 } },
        results = { { type = 'item', name = 'kr-loader', amount = 1 } },
      },
    },
  }
end

describe('лоадеры AAI', function()
  it('узнаются по loader-1x1 с именем на aai-', function()
    local r = raw()
    assert_true(price.is_aai_loader(r, 'aai-turbo-loader'))
    assert_false(price.is_aai_loader(r, 'kr-loader'))
    assert_false(price.is_aai_loader(r, 'aai-nothing'))
  end)

  it('рецепты лоадеров AAI найдены, чужие лоадеры — нет', function()
    local found = price.loader_recipes(raw())
    assert_eq(#found, 1)
    assert_eq(found[1].name, 'aai-shm-superior-loader')
  end)
end)

describe('делитель', function()
  it('делит с округлением вверх, минимум 1, лоадер в ингредиентах не делит', function()
    local r = raw()
    price.apply(r, 5)
    local ingredients = r.recipe['aai-shm-superior-loader'].ingredients
    assert_eq(ingredients[1].amount, 1)
    assert_eq(ingredients[2].amount, 1)
    assert_eq(ingredients[3].amount, 60)
    assert_eq(ingredients[4].amount, 11)
    assert_eq(ingredients[5].amount, 100)
  end)

  it('чужие рецепты не трогаются', function()
    local r = raw()
    price.apply(r, 5)
    assert_eq(r.recipe['kr-loader'].ingredients[1].amount, 50)
  end)

  it('делитель 1 — ничего не меняется', function()
    local r = raw()
    assert_eq(#price.apply(r, 1), 0)
    assert_eq(r.recipe['aai-shm-superior-loader'].ingredients[3].amount, 300)
  end)
end)
