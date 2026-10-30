local lines = require('logic.lines')

local LINE = {
  name = 'Aquilo supply',
  items = {
    { name = 'iron-plate', quality = 'legendary', count = 2000 },
    { name = 'copper-plate', count = 0 },
    { name = nil, count = 5 },
    { name = 'steel-plate', count = 100 },
  },
}

describe('линии снабжения', function()
  it('имя группы: линия, источники, метка роли', function()
    assert_eq(lines.group_name('Aquilo supply', { role = 'depot', places = 'nauvis', import_from = 'nauvis', request_from = 'planet' }),
      'Aquilo supply · nauvis/planet [depot:nauvis]')
    assert_eq(lines.group_name('Aquilo supply', { role = 'cargo', places = 'aquilo', import_from = 'nauvis', request_from = 'platforms' }),
      'Aquilo supply · nauvis/platforms [cargo→aquilo]')
    assert_eq(lines.group_name('Aquilo supply', { role = 'receive', import_from = 'aquilo', request_from = 'platforms' }),
      'Aquilo supply · aquilo/platforms')
    assert_eq(lines.group_name('Aquilo supply', { role = 'depot', places = '', request_from = 'all' }),
      'Aquilo supply · any/all [depot]')
    assert_eq(lines.group_name('Aquilo supply', { kind = 'pad', role = 'receive' }), 'Aquilo supply · pad')
  end)

  it('одинаковые роль и источники — одна группа, разные — разные', function()
    local a = { role = 'cargo', places = 'aquilo', import_from = 'nauvis', request_from = 'platforms', multiplier = 1 }
    local b = { role = 'cargo', places = 'aquilo', import_from = 'nauvis', request_from = 'platforms', multiplier = 2 }
    local c = { role = 'cargo', places = 'aquilo', import_from = 'vulcanus', request_from = 'platforms' }
    assert_eq(lines.group_name('L', a), lines.group_name('L', b))
    assert_false(lines.group_name('L', a) == lines.group_name('L', c))
  end)

  it('группа принадлежит линии по префиксу', function()
    assert_true(lines.owns('Aquilo supply', 'Aquilo supply · pad'))
    assert_false(lines.owns('Aquilo', 'Aquilo supply · pad'))
    assert_false(lines.owns('Aquilo supply', nil))
  end)

  it('фильтры по шапке: пустые и нулевые строки пропускаются, у площадки без источников', function()
    local hub = { role = 'depot', places = 'nauvis', import_from = 'nauvis', request_from = 'planet' }
    assert_eq(lines.filters(LINE, hub), {
      { name = 'iron-plate', quality = 'legendary', min = 2000, import_from = 'nauvis', request_from = 'planet' },
      { name = 'steel-plate', quality = 'normal', min = 100, import_from = 'nauvis', request_from = 'planet' },
    })
    assert_eq(lines.filters(LINE, { kind = 'pad', role = 'receive' }), {
      { name = 'iron-plate', quality = 'legendary', min = 2000 },
      { name = 'steel-plate', quality = 'normal', min = 100 },
    })
  end)

  it('множитель из поля', function()
    assert_eq(lines.multiplier('5'), 5)
    assert_eq(lines.multiplier('0.5'), 0.5)
    assert_nil(lines.multiplier('0'))
    assert_nil(lines.multiplier('x'))
  end)

  it('метка роли: у получателя нет', function()
    assert_nil(lines.tag_of({ role = 'receive' }))
    assert_eq(lines.tag_of({ role = 'reserve' }), { kind = 'reserve' })
  end)
end)
