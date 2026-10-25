local variants = require('logic.variants')

local function raw()
  return {
    ['loader-1x1'] = {
      ['aai-turbo-loader'] = {
        name = 'aai-turbo-loader',
        max_belt_stack_size = 4,
        minable = { result = 'aai-turbo-loader' },
        next_upgrade = 'aai-shm-superior-loader',
      },
      ['hidden-loader'] = { name = 'hidden-loader', hidden = true, max_belt_stack_size = 4 },
      ['flat-loader'] = { name = 'flat-loader' },
    },
    loader = {
      ['loader'] = { name = 'loader', hidden = true },
    },
    ['storage-tank'] = {
      ['aai-turbo-loader-pipe'] = { name = 'aai-turbo-loader-pipe' },
    },
  }
end

local function by_name(list)
  local result = {}
  for _, prototype in ipairs(list) do
    result[prototype.name] = prototype
  end
  return result
end

describe('имена', function()
  it('копия несёт суффикс -shm-alt и сводится к исходному', function()
    assert_eq(variants.alt_name('aai-turbo-loader'), 'aai-turbo-loader-shm-alt')
    assert_eq(variants.base_name('aai-turbo-loader-shm-alt'), 'aai-turbo-loader')
    assert_eq(variants.base_name('aai-turbo-loader'), 'aai-turbo-loader')
    assert_true(variants.is_alt('aai-turbo-loader-shm-alt'))
  end)

  it('режим копии противоположен режиму по умолчанию', function()
    assert_true(variants.is_waiting('x', true))
    assert_false(variants.is_waiting('x-shm-alt', true))
    assert_true(variants.is_waiting('x-shm-alt', false))
  end)

  it('with_mode выбирает прототип нужного режима', function()
    assert_eq(variants.with_mode('x', true, true), 'x')
    assert_eq(variants.with_mode('x', false, true), 'x-shm-alt')
    assert_eq(variants.with_mode('x-shm-alt', true, true), 'x')
    assert_eq(variants.with_mode('x', true, false), 'x-shm-alt')
  end)
end)

describe('стак', function()
  it('всем лоадерам ставится максимум и настраиваемый размер', function()
    local r = raw()
    variants.apply_stacking(r, 4)
    assert_eq(r['loader-1x1']['flat-loader'].max_belt_stack_size, 4)
    assert_true(r['loader-1x1']['flat-loader'].adjustable_belt_stack_size)
    assert_eq(r.loader.loader.max_belt_stack_size, 4)
  end)
end)

describe('копии для переключателя', function()
  it('видимый лоадер со стопками получает копию с противоположным режимом', function()
    local r = raw()
    local created = by_name(variants.apply(r, true))
    assert_true(r['loader-1x1']['aai-turbo-loader'].wait_for_full_stack)
    local alt = created['aai-turbo-loader-shm-alt']
    assert_false(alt.wait_for_full_stack)
    assert_true(alt.hidden)
    assert_nil(alt.next_upgrade)
    assert_eq(alt.placeable_by, { item = 'aai-turbo-loader', count = 1 })
    assert_eq(alt.localised_name, { 'entity-name.aai-turbo-loader' })
  end)

  it('копия лоадера AAI с трубой получает копию трубы под своим именем', function()
    local created = by_name(variants.apply(raw(), true))
    assert_eq(created['aai-turbo-loader-shm-alt-pipe'].name, 'aai-turbo-loader-shm-alt-pipe')
  end)

  it('скрытые и без стопок — без копий', function()
    local created = by_name(variants.apply(raw(), true))
    assert_nil(created['hidden-loader-shm-alt'])
    assert_nil(created['flat-loader-shm-alt'])
    assert_nil(created['loader-shm-alt'])
  end)

  it('режим по умолчанию «Сразу» — исходный не ждёт, копия ждёт', function()
    local r = raw()
    local created = by_name(variants.apply(r, false))
    assert_false(r['loader-1x1']['aai-turbo-loader'].wait_for_full_stack)
    assert_true(created['aai-turbo-loader-shm-alt'].wait_for_full_stack)
  end)
end)
