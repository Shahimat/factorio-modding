local fuel_merge = require('logic.fuel-merge')

local FROM = 'kr-vehicle-fuel'
local TO = 'chemical'

describe('replace', function()
  it('заменяет категорию на том же месте', function()
    assert_eq(fuel_merge.replace({ 'nuclear', FROM }, FROM, TO), { 'nuclear', TO })
  end)

  it('не плодит дубль, если целевая категория уже есть', function()
    assert_eq(fuel_merge.replace({ TO, FROM }, FROM, TO), { TO })
    assert_eq(fuel_merge.replace({ FROM, TO }, FROM, TO), { TO })
  end)

  it('возвращает nil, если исходной категории нет', function()
    assert_nil(fuel_merge.replace({ TO, 'nuclear' }, FROM, TO))
    assert_nil(fuel_merge.replace({}, FROM, TO))
  end)
end)

-- Фрагмент `data.raw` в форме K2 2.1: топливо, транспорт, локомотив с обеими
-- категориями, генератор-эквипмент с полем `burner` и посторонние прототипы.
local function k2_raw()
  return {
    item = {
      ['kr-fuel'] = { name = 'kr-fuel', fuel_categories = { FROM }, fuel_value = '15MJ' },
      ['kr-advanced-fuel'] = {
        name = 'kr-advanced-fuel',
        fuel_categories = { FROM },
        fuel_acceleration_multiplier = 1.25,
      },
      ['coal'] = { name = 'coal', fuel_categories = { TO } },
      ['kr-dt-fuel-cell'] = { name = 'kr-dt-fuel-cell', fuel_categories = { 'kr-fusion-fuel' } },
      ['iron-plate'] = { name = 'iron-plate' },
    },
    car = {
      ['car'] = { name = 'car', energy_source = { type = 'burner', fuel_categories = { FROM } } },
      ['vehicle-miner'] = {
        name = 'vehicle-miner',
        energy_source = { type = 'burner', fuel_categories = { TO, FROM } },
      },
    },
    locomotive = {
      ['locomotive'] = {
        name = 'locomotive',
        energy_source = { type = 'burner', fuel_categories = { TO, FROM } },
      },
    },
    ['generator-equipment'] = {
      ['kr-portable-generator-equipment'] = {
        name = 'kr-portable-generator-equipment',
        burner = { type = 'burner', fuel_categories = { TO, FROM } },
      },
    },
    reactor = {
      ['kr-antimatter-reactor'] = {
        name = 'kr-antimatter-reactor',
        energy_source = { type = 'burner', fuel_categories = { 'kr-antimatter-fuel' } },
      },
    },
    ['assembling-machine'] = {
      ['assembling-machine-1'] = {
        name = 'assembling-machine-1',
        energy_source = { type = 'electric', usage_priority = 'secondary-input' },
      },
    },
    ['fuel-category'] = {
      [FROM] = { type = 'fuel-category', name = FROM },
    },
  }
end

describe('merge', function()
  it('переводит топливо K2 в химическую категорию с сохранением множителей', function()
    local raw = k2_raw()
    fuel_merge.merge(raw, FROM, TO)
    assert_eq(raw.item['kr-fuel'].fuel_categories, { TO })
    assert_eq(raw.item['kr-advanced-fuel'].fuel_categories, { TO })
    assert_eq(raw.item['kr-advanced-fuel'].fuel_acceleration_multiplier, 1.25)
  end)

  it('переводит транспорт на химическое топливо без дублей', function()
    local raw = k2_raw()
    fuel_merge.merge(raw, FROM, TO)
    assert_eq(raw.car['car'].energy_source.fuel_categories, { TO })
    assert_eq(raw.car['vehicle-miner'].energy_source.fuel_categories, { TO })
    assert_eq(raw.locomotive['locomotive'].energy_source.fuel_categories, { TO })
  end)

  it('находит burner-источник в любом поле прототипа, не только energy_source', function()
    local raw = k2_raw()
    fuel_merge.merge(raw, FROM, TO)
    assert_eq(raw['generator-equipment']['kr-portable-generator-equipment'].burner.fuel_categories, { TO })
  end)

  it('не трогает чужие категории, электрические источники и сам прототип категории', function()
    local raw = k2_raw()
    fuel_merge.merge(raw, FROM, TO)
    assert_eq(raw.item['kr-dt-fuel-cell'].fuel_categories, { 'kr-fusion-fuel' })
    assert_eq(raw.reactor['kr-antimatter-reactor'].energy_source.fuel_categories, { 'kr-antimatter-fuel' })
    assert_nil(raw['assembling-machine']['assembling-machine-1'].energy_source.fuel_categories)
    assert_eq(raw['fuel-category'][FROM], { type = 'fuel-category', name = FROM })
  end)

  it('считает изменённые списки', function()
    assert_eq(fuel_merge.merge(k2_raw(), FROM, TO), { items = 2, burners = 4 })
  end)

  it('без K2 ничего не меняет', function()
    local raw = {
      item = { ['coal'] = { name = 'coal', fuel_categories = { TO } } },
      car = { ['car'] = { name = 'car', energy_source = { type = 'burner', fuel_categories = { TO } } } },
    }
    assert_eq(fuel_merge.merge(raw, FROM, TO), { items = 0, burners = 0 })
    assert_eq(raw.car['car'].energy_source.fuel_categories, { TO })
  end)

  it('повторный прогон ничего не меняет', function()
    local raw = k2_raw()
    fuel_merge.merge(raw, FROM, TO)
    assert_eq(fuel_merge.merge(raw, FROM, TO), { items = 0, burners = 0 })
  end)
end)
