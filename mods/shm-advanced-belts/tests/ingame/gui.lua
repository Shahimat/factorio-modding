-- Панель у окна лоадера и его призрака, достройка призрака при открытом
-- окне, клавиша по призраку. Нужен живой игрок, поэтому только в прогоне с
-- графикой: тег `gui`, `npm run test:ingame:gui -w <мод>`.

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

local function panel_state(p)
  local window = p.gui.relative[switch.WINDOW]
  return window and window.children[1][switch.SWITCH].switch_state
end

tags('gui')
describe('интерфейс', function()
  before_each(function()
    f.clear()
    player().opened = nil
  end)

  after_each(function()
    player().opened = nil
    player().clear_cursor()
    f.clear()
  end)

  it('окно лоадера и его призрака получает панель с положением по режиму', function()
    if not f.aai() then
      return
    end
    local p = player()
    p.opened = f.create(f.loader('superior'), near(0))
    assert(panel_state(p) == 'right', 'у лоадера панель не в «Полная стопка»')
    p.opened = f.create('entity-ghost', near(2), { inner_name = f.loader('superior') .. '-shm-alt' })
    local window = p.gui.relative[switch.WINDOW]
    assert(window and window.anchor.ghost_mode == 'both', 'панель скрыта у призраков')
    assert(panel_state(p) == 'left', 'у призрака панель не в «Сразу»')
  end)

  it('щелчок переключателя на призраке меняет его вариант, окно остаётся открытым', function()
    if not f.aai() then
      return
    end
    local p = player()
    p.opened = f.create('entity-ghost', near(0), { inner_name = f.loader('superior') })
    local element = p.gui.relative[switch.WINDOW].children[1][switch.SWITCH]
    element.switch_state = 'left'
    local replacement = switch.on_switch_changed(p, element)
    assert(replacement and replacement.ghost_name == f.loader('superior') .. '-shm-alt', 'режим призрака не сменился')
    assert(p.opened == replacement, 'окно не открыто на новом призраке')
    assert(panel_state(p) == 'left', 'панель не показывает новый режим')
  end)

  it('достройка призрака при открытом окне обновляет панель', function()
    if not f.aai() then
      return
    end
    local p = player()
    local ghost = f.create('entity-ghost', near(0), { inner_name = f.loader('superior') })
    p.opened = ghost
    local stale = p.gui.relative[switch.WINDOW]
    local _, built = ghost.revive({ raise_revive = true })
    assert(built and p.opened == built, 'окно не перешло на построенный лоадер')
    local window = p.gui.relative[switch.WINDOW]
    assert(window and window ~= stale, 'панель не пересоздана')
  end)

  it('постройка из руки поверх призрака «Сразу» даёт «Сразу», окно и панель на нём', function()
    if not f.aai() then
      return
    end
    local p = player()
    local base = f.loader('superior')
    local ghost = f.create('entity-ghost', near(0), { inner_name = base .. '-shm-alt' })
    p.opened = ghost
    p.cursor_stack.set_stack({ name = base, count = 1 })
    p.build_from_cursor({ position = ghost.position })
    p.clear_cursor()
    local found = f.surface().find_entities_filtered({ position = near(0), type = 'loader-1x1' })
    assert(#found == 1 and found[1].name == base .. '-shm-alt', 'режим призрака потерян: ' .. (found[1] and found[1].name or 'ничего'))
    assert(p.opened == found[1], 'окно не открыто на построенном')
    assert(panel_state(p) == 'left', 'панель не показывает «Сразу»')
    if f.aai_mode() == 'lubricated' then
      local pipes = f.surface().find_entities_filtered({ position = { found[1].position.x, found[1].position.y + 1 / 32 }, type = 'storage-tank' })
      assert(#pipes == 1 and pipes[1].name == found[1].name .. '-pipe', 'трубы на месте: ' .. #pipes)
    end
  end)

  it('клавиша переключает призрак под курсором и на расстоянии', function()
    if not f.aai() then
      return
    end
    local p = player()
    p.selected = f.create('entity-ghost', { p.position.x + 30.5, p.position.y + 0.5 }, { inner_name = f.loader('superior') })
    if p.selected then
      local replacement = switch.toggle_selected(p)
      assert(replacement and replacement.ghost_name == f.loader('superior') .. '-shm-alt', 'призрак не переключился')
    end
  end)
end)
