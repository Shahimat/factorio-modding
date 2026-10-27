local tags = require('logic.tags')

describe('метки в имени группы', function()
  it('без метки и без группы — nil', function()
    assert_nil(tags.parse(nil))
    assert_nil(tags.parse(''))
    assert_nil(tags.parse('Iron plates'))
  end)

  it('[reserve] — свой запас, регистр и пробелы не важны', function()
    assert_eq(tags.parse('Fuel [reserve]'), { kind = 'reserve' })
    assert_eq(tags.parse('Fuel [ ReSeRvE ]'), { kind = 'reserve' })
  end)

  it('[cargo] без «куда» — ванильный груз', function()
    assert_eq(tags.parse('[cargo]'), { kind = 'cargo' })
  end)

  it('[cargo→…] и [cargo->…] — одна планета и список', function()
    assert_eq(tags.parse('Plates [cargo→aquilo]'), { kind = 'cargo', dests = { aquilo = true } })
    assert_eq(tags.parse('Ores [cargo -> vulcanus, aquilo]'),
      { kind = 'cargo', dests = { vulcanus = true, aquilo = true } })
  end)

  it('[cargo→] без планет — не метка', function()
    assert_nil(tags.parse('[cargo→]'))
  end)

  it('[depot], [depot:*] — любая орбита; [depot:…] — список', function()
    assert_eq(tags.parse('[depot]'), { kind = 'depot', anywhere = true })
    assert_eq(tags.parse('[depot:*]'), { kind = 'depot', anywhere = true })
    assert_eq(tags.parse('Plates [depot:nauvis,vulcanus]'),
      { kind = 'depot', orbits = { nauvis = true, vulcanus = true } })
  end)

  it('чужие скобки пропускаются, побеждает первая узнанная метка', function()
    assert_eq(tags.parse('[item=iron-plate] Plates [depot:nauvis] [reserve]'),
      { kind = 'depot', orbits = { nauvis = true } })
    assert_nil(tags.parse('[item=iron-plate] [virtual-signal=signal-A]'))
  end)

  it('груз открыт на точке назначения и всегда без «куда»', function()
    local tag = tags.parse('[cargo→aquilo]')
    assert_true(tags.cargo_open_at(tag, 'aquilo'))
    assert_false(tags.cargo_open_at(tag, 'nauvis'))
    assert_false(tags.cargo_open_at(tag, nil))
    assert_true(tags.cargo_open_at(tags.parse('[cargo]'), 'nauvis'))
  end)

  it('склад работает на своих орбитах, в пути — нигде', function()
    assert_true(tags.depot_active_at(tags.parse('[depot:nauvis]'), 'nauvis'))
    assert_false(tags.depot_active_at(tags.parse('[depot:nauvis]'), 'vulcanus'))
    assert_true(tags.depot_active_at(tags.parse('[depot]'), 'gleba'))
    assert_false(tags.depot_active_at(tags.parse('[depot]'), nil))
  end)
end)
