local variants = require('logic.variants')

local SUP = 'kr-superior-inserter'
local LONG = 'kr-superior-long-inserter'
local SUP_INSTANT = 'shm-kr-superior-inserter-instant'

describe('имена', function()
  it('вариант «Сразу» несёт префикс shm- и суффикс -instant', function()
    assert_eq(variants.instant_name(SUP), SUP_INSTANT)
  end)

  it('оба варианта узнаются как семья и сводятся к исходному имени', function()
    assert_eq(variants.base_name(SUP), SUP)
    assert_eq(variants.base_name(SUP_INSTANT), SUP)
    assert_true(variants.is_family(variants.instant_name(LONG)))
  end)

  it('чужие манипуляторы в семью не входят', function()
    assert_false(variants.is_family('bulk-inserter'))
    assert_nil(variants.is_waiting('stack-inserter'))
    assert_nil(variants.toggled('bulk-inserter'))
    assert_nil(variants.with_mode('inserter', true))
  end)

  it('исходный ждёт полную руку, копия — нет', function()
    assert_true(variants.is_waiting(SUP))
    assert_false(variants.is_waiting(SUP_INSTANT))
  end)

  it('переключение ходит туда и обратно внутри своей семьи', function()
    assert_eq(variants.toggled(SUP), SUP_INSTANT)
    assert_eq(variants.toggled(SUP_INSTANT), SUP)
    assert_eq(variants.toggled(LONG), variants.instant_name(LONG))
  end)

  it('with_mode выбирает режим, а не переключает', function()
    assert_eq(variants.with_mode(SUP, true), SUP)
    assert_eq(variants.with_mode(SUP_INSTANT, true), SUP)
    assert_eq(variants.with_mode(SUP, false), SUP_INSTANT)
    assert_eq(variants.with_mode(SUP_INSTANT, false), SUP_INSTANT)
  end)

  it('all_names перечисляет оба варианта каждого члена семьи', function()
    assert_eq(variants.all_names(), {
      SUP,
      SUP_INSTANT,
      LONG,
      variants.instant_name(LONG),
    })
  end)
end)

-- Фрагмент `data.raw` в форме K2 2.1 + K2 Spaced Out: оба превосходных
-- манипулятора со стакингом на ленте и посторонний массовый манипулятор.
local function k2_raw()
  return {
    inserter = {
      [SUP] = {
        type = 'inserter',
        name = SUP,
        minable = { mining_time = 0.1, result = SUP },
        fast_replaceable_group = 'inserter',
        bulk = true,
        max_belt_stack_size = 4,
        allow_custom_vectors = true,
        next_upgrade = 'some-better-inserter',
        energy_source = { type = 'electric', drain = '1kW' },
      },
      [LONG] = {
        type = 'inserter',
        name = LONG,
        minable = { mining_time = 0.1, result = LONG },
        bulk = true,
        localised_name = { 'custom-name.long' },
      },
      ['bulk-inserter'] = { type = 'inserter', name = 'bulk-inserter', bulk = true },
    },
  }
end

describe('apply', function()
  it('исходным прототипам включает ожидание полной руки', function()
    local raw = k2_raw()
    variants.apply(raw)
    for _, name in ipairs({ SUP, LONG }) do
      local p = raw.inserter[name]
      assert_true(p.wait_for_full_hand, name)
      assert_true(p.grab_less_to_match_belt_stack, name)
      assert_true(p.enter_drop_mode_if_held_stack_spoiled, name)
    end
  end)

  it('чужие манипуляторы не трогает', function()
    local raw = k2_raw()
    variants.apply(raw)
    assert_eq(raw.inserter['bulk-inserter'], { type = 'inserter', name = 'bulk-inserter', bulk = true })
  end)

  it('возвращает по копии на каждый найденный прототип семьи, в порядке семьи', function()
    local created = variants.apply(k2_raw())
    assert_eq(#created, 2)
    assert_eq(created[1].name, SUP_INSTANT)
    assert_eq(created[2].name, variants.instant_name(LONG))
  end)

  it('копия выкладывает сразу и наследует всё остальное', function()
    local copy = variants.apply(k2_raw())[1]
    assert_false(copy.wait_for_full_hand)
    assert_false(copy.grab_less_to_match_belt_stack)
    assert_false(copy.enter_drop_mode_if_held_stack_spoiled)
    assert_eq(copy.max_belt_stack_size, 4)
    assert_true(copy.allow_custom_vectors)
    assert_eq(copy.fast_replaceable_group, 'inserter')
    assert_eq(copy.minable, { mining_time = 0.1, result = SUP })
  end)

  it('копия ставится предметом исходного, скрыта и вне цепочки улучшений', function()
    local copy = variants.apply(k2_raw())[1]
    assert_eq(copy.placeable_by, { item = SUP, count = 1 })
    assert_true(copy.hidden)
    assert_true(copy.hidden_in_factoriopedia)
    assert_eq(copy.factoriopedia_alternative, SUP)
    assert_nil(copy.next_upgrade)
  end)

  it('копия называется как исходный, свой localised_name исходного сохраняется', function()
    local created = variants.apply(k2_raw())
    assert_eq(created[1].localised_name, { 'entity-name.' .. SUP })
    assert_eq(created[1].localised_description, { 'entity-description.' .. SUP })
    assert_eq(created[2].localised_name, { 'custom-name.long' })
  end)

  it('копия не делит таблицы с исходным', function()
    local raw = k2_raw()
    local copy = variants.apply(raw)[1]
    copy.energy_source.drain = '0kW'
    assert_eq(raw.inserter[SUP].energy_source.drain, '1kW')
  end)

  it('предмет берётся из placeable_by или из results, если result нет', function()
    local by = variants.make_instant({ name = SUP, placeable_by = { item = 'x', count = 1 } })
    assert_eq(by.placeable_by, { item = 'x', count = 1 })
    local results = variants.make_instant({
      name = SUP,
      minable = { results = { { type = 'item', name = 'y', amount = 1 } } },
    })
    assert_eq(results.placeable_by, { item = 'y', count = 1 })
  end)

  it('без K2 ничего не меняет и ничего не создаёт', function()
    local raw = { inserter = { ['bulk-inserter'] = { name = 'bulk-inserter' } } }
    assert_eq(variants.apply(raw), {})
    assert_eq(raw, { inserter = { ['bulk-inserter'] = { name = 'bulk-inserter' } } })
    assert_eq(variants.apply({}), {})
  end)
end)
