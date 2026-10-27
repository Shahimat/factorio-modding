-- Панель у окна манипулятора, клавиша по сущности под курсором и вставка
-- настроек игроком. Нужен живой игрок, поэтому только в прогоне с графикой:
-- тег `gui`, `npm run test:ingame:gui -w <мод>`.

local f = require('tests.ingame.fixture')
local switch = require('runtime.switch')

local function player()
  local p = game.players[1]
  assert(p and p.valid, 'в прогоне нет игрока — запускай с графикой')
  return p
end

--- Клетка рядом с игроком, в пределах досягаемости.
local function near(dx)
  local position = player().position
  return { math.floor(position.x) + dx + 0.5, math.floor(position.y) + 2.5 }
end

tags('gui')
describe('интерфейс', function()
  before_each(function()
    f.clear()
    player().opened = nil
  end)

  after_each(function()
    player().opened = nil
    f.clear()
  end)

  it('окно манипулятора семьи получает панель с положением по режиму', function()
    local p = player()
    p.opened = f.create(f.SUP, near(0))
    local window = p.gui.relative[switch.WINDOW]
    assert(window, 'панели нет')
    local cidl = p.gui.relative['cidl_window']
    if cidl then
      assert(cidl.index < window.index, 'панель не под панелью Change Inserter Drop Lane')
    end
    local element = window.children[1][switch.SWITCH]
    assert(element and element.switch_state == 'right', 'переключатель не в «Полная рука»')

    p.opened = f.create(f.SUP_INSTANT, near(2))
    element = p.gui.relative[switch.WINDOW].children[1][switch.SWITCH]
    assert(element.switch_state == 'left', 'переключатель не в «Сразу»')
  end)

  it('окно призрака семьи получает панель, видимую и у призрака', function()
    local p = player()
    p.opened = f.create('entity-ghost', near(0), { inner_name = f.SUP_INSTANT })
    local window = p.gui.relative[switch.WINDOW]
    assert(window, 'панели нет')
    assert(window.anchor.ghost_mode == 'both', 'панель скрыта у призраков')
    assert(window.children[1][switch.SWITCH].switch_state == 'left', 'переключатель не в «Сразу»')
  end)

  it('щелчок переключателя на призраке меняет его вариант, окно остаётся открытым', function()
    local p = player()
    p.opened = f.create('entity-ghost', near(0), { inner_name = f.SUP })
    local element = p.gui.relative[switch.WINDOW].children[1][switch.SWITCH]
    element.switch_state = 'left'
    local replacement = switch.on_switch_changed(p, element)
    assert(replacement and replacement.ghost_name == f.SUP_INSTANT, 'режим призрака не сменился')
    assert(p.opened == replacement, 'окно не открыто на новом призраке')
    assert(p.gui.relative[switch.WINDOW].children[1][switch.SWITCH].switch_state == 'left', 'панель не показывает новый режим')
  end)

  it('достройка призрака при открытом окне обновляет панель', function()
    local p = player()
    local ghost = f.create('entity-ghost', near(0), { inner_name = f.SUP })
    p.opened = ghost
    local stale = p.gui.relative[switch.WINDOW]
    local _, built = ghost.revive({ raise_revive = true })
    assert(built and p.opened == built, 'окно не перешло на построенный манипулятор')
    local window = p.gui.relative[switch.WINDOW]
    assert(window and window ~= stale, 'панель не пересоздана')

    local other = f.create('entity-ghost', near(2), { inner_name = f.SUP })
    p.opened = other
    stale = p.gui.relative[switch.WINDOW]
    p.cursor_stack.set_stack({ name = f.SUP, count = 1 })
    p.build_from_cursor({ position = other.position })
    p.clear_cursor()
    assert(p.opened and p.opened.valid and p.opened.name == f.SUP, 'игрок не достроил призрак')
    window = p.gui.relative[switch.WINDOW]
    assert(window and window ~= stale, 'панель не пересоздана после постройки игроком')
  end)

  it('постройка из руки поверх призрака «Сразу» даёт «Сразу», окно и панель на нём', function()
    local p = player()
    local ghost = f.create('entity-ghost', near(0), { inner_name = f.SUP_INSTANT })
    p.opened = ghost
    p.cursor_stack.set_stack({ name = f.SUP, count = 1 })
    p.build_from_cursor({ position = ghost.position })
    p.clear_cursor()
    local found = f.surface().find_entities_filtered({ position = near(0), type = 'inserter' })
    assert(#found == 1 and found[1].name == f.SUP_INSTANT, 'режим призрака потерян: ' .. (found[1] and found[1].name or 'ничего'))
    assert(p.opened == found[1], 'окно не открыто на построенном')
    local window = p.gui.relative[switch.WINDOW]
    assert(window and window.children[1][switch.SWITCH].switch_state == 'left', 'панель не показывает «Сразу»')
  end)

  it('окно чужого манипулятора панели не получает', function()
    local p = player()
    p.opened = f.create(f.SUP, near(0))
    p.opened = f.create('bulk-inserter', near(2))
    assert(p.gui.relative[switch.WINDOW] == nil, 'панель осталась у чужого манипулятора')
  end)

  it('щелчок переключателя меняет режим, окно остаётся открытым на новой сущности', function()
    local p = player()
    p.opened = f.create(f.SUP, near(0))
    local element = p.gui.relative[switch.WINDOW].children[1][switch.SWITCH]
    element.switch_state = 'left'
    local replacement = switch.on_switch_changed(p, element)
    assert(replacement and replacement.name == f.SUP_INSTANT, 'режим не сменился')
    assert(p.opened == replacement, 'окно не открыто на новой сущности')
    local fresh = p.gui.relative[switch.WINDOW].children[1][switch.SWITCH]
    assert(fresh.switch_state == 'left', 'панель не показывает новый режим')
  end)

  it('клавиша переключает манипулятор под курсором', function()
    local p = player()
    p.selected = f.create(f.SUP, near(0))
    local replacement = switch.toggle_selected(p)
    assert(replacement and replacement.name == f.SUP_INSTANT, 'не переключился')
  end)

  it('клавиша переключает призрак под курсором и на расстоянии', function()
    local p = player()
    p.selected = f.create('entity-ghost', { p.position.x + 30.5, p.position.y + 0.5 }, { inner_name = f.SUP })
    if p.selected then
      local replacement = switch.toggle_selected(p)
      assert(replacement and replacement.ghost_name == f.SUP_INSTANT, 'призрак не переключился')
    end
  end)

  it('клавиша не трогает чужой и недосягаемый манипулятор', function()
    local p = player()

    local bulk = f.create('bulk-inserter', near(2))
    p.selected = bulk
    assert(switch.toggle_selected(p) == nil and bulk.valid, 'чужой манипулятор переключён')

    local far = f.create(f.SUP, { p.position.x + 30.5, p.position.y + 0.5 })
    p.selected = far
    if p.selected == far then
      assert(switch.toggle_selected(p) == nil and far.valid and far.name == f.SUP, 'недосягаемый переключён')
    end
  end)

  it('вставка настроек игроком переносит режим через событие', function()
    local p = player()
    local source = f.create(f.SUP_INSTANT, near(0))
    local destination = f.create(f.SUP, near(2))
    destination.copy_settings(source, p)
    local found = f.surface().find_entities_filtered({ position = near(2), type = 'inserter' })
    assert(#found == 1 and found[1].name == f.SUP_INSTANT, 'режим не перенесён событием вставки')
  end)
end)
