local own_section = require('logic.own_section')

describe('своя секция', function()
  it('ключ и обратно, «*» — любое качество', function()
    assert_eq(own_section.key('iron-plate', 'rare'), 'iron-plate|rare')
    assert_eq(own_section.key('iron-plate', nil), 'iron-plate|*')
    assert_eq({ own_section.split('iron-plate|rare') }, { 'iron-plate', 'rare' })
    assert_eq({ own_section.split('iron-plate|*') }, { 'iron-plate' })
  end)

  it('фильтры: замки, затем транзит, по ключу', function()
    local result = { locks = { ['b|normal'] = true, ['a|normal'] = true }, transit = { ['c|normal'] = true }, release = {} }
    assert_eq(own_section.filters(result, 'nauvis'), {
      { key = 'a|normal', min = 0, request_from = 'all' },
      { key = 'b|normal', min = 0, request_from = 'all' },
      { key = 'c|normal', min = 0, request_from = 'platforms', import_from = 'nauvis' },
    })
  end)

  it('в пути транзита нет', function()
    local result = { locks = {}, transit = { ['c|normal'] = true }, release = {} }
    assert_eq(own_section.filters(result, nil), {})
  end)

  it('сравнение своей секции с записанной', function()
    local desired = { { key = 'a|normal', min = 0, request_from = 'all' } }
    assert_true(own_section.same({ { key = 'a|normal', request_from = 'all' } }, desired))
    assert_false(own_section.same({}, desired))
    assert_false(own_section.same({ { key = 'a|normal', min = 50, request_from = 'platforms', import_from = 'nauvis' } }, desired))
  end)
end)
