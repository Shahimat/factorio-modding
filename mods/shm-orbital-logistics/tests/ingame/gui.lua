-- Панель у окна хаба и площадки, окно линий снабжения. Нужен живой игрок,
-- поэтому только в прогоне с графикой: тег `gui`,
-- `npm run test:ingame:gui -w shm-orbital-logistics`. Нажатия вызываются
-- обработчиками напрямую: поднять встроенное событие GUI скрипт не может.

local f = require('tests.ingame.fixture')
local panel = require('runtime.panel')
local lines_gui = require('runtime.lines_gui')
local lines = require('runtime.lines')
local picker = require('runtime.places_picker')

local function player()
  local p = game.players[1]
  assert(p and p.valid, 'в прогоне нет игрока — запускай с графикой')
  return p
end

local function find(root, name)
  if not root then
    return nil
  end
  if root.name == name then
    return root
  end
  for _, child in pairs(root.children) do
    local found = find(child, name)
    if found then
      return found
    end
  end
  return nil
end

local function click(element)
  local event = { element = element, player_index = player().index }
  if picker.on_click(event) then
    return
  end
  if not panel.on_click(event, lines_gui.open) then
    lines_gui.on_click(event)
  end
end

--- Добавить место в выбор `name`: как выбор в окне игры у кнопки «+».
local function pick(root, name, planet)
  local add = find(root, name .. '__add')
  assert(add, 'нет кнопки «+» в ' .. name)
  add.elem_value = planet
  assert(picker.on_elem_changed({ element = add, player_index = player().index }), 'выбор не обработан')
end

--- Задать одиночный выбор `name`.
local function choose(root, name, planet)
  local button = find(root, name .. '__choose')
  assert(button, 'нет кнопки выбора в ' .. name)
  button.elem_value = planet
  picker.on_elem_changed({ element = button, player_index = player().index })
end

local function open(entity)
  local p = player()
  -- Хаб живёт на поверхности платформы: открыть его окно можно из
  -- удалённого вида, как это делает игрок в Space Age.
  if p.surface ~= entity.surface or p.controller_type ~= defines.controllers.remote then
    p.set_controller({ type = defines.controllers.remote, surface = entity.surface, position = entity.position })
  end
  p.opened = entity
  assert(player().opened == entity, 'окно не открылось')
  return player().gui.relative[panel.NAME]
end

tags('gui')
describe('интерфейс', function()
  before_all(f.prepare_force)
  before_each(function()
    player().opened = nil
    f.clear()
  end)
  after_each(function()
    player().opened = nil
    if player().controller_type == defines.controllers.remote then
      player().exit_remote_view()
    end
    lines_gui.close(player())
    for _, line in ipairs(lines.list(player().force)) do
      lines.delete(player().force, line)
    end
    for _, group in pairs(player().force.get_logistic_groups()) do
      if string.sub(group, 1, 5) == 'Test ' or string.find(group, 'shm-test-', 1, true) then
        player().force.delete_logistic_group(group)
      end
    end
    f.clear()
  end)

  it('панель хаба ставит метку секции без группы и с группой', function()
    local _, hub = f.platform('a')
    f.request(hub, 300, { from = 'planet', import_from = f.PLANET })
    f.request(hub, 100, { group = 'Test plates', from = 'planet', import_from = f.PLANET })
    local frame = open(hub)
    assert(frame, 'панели нет')
    local sections = hub.get_logistic_sections()
    local plain_index, grouped_index
    for index = 1, sections.sections_count do
      local section = sections.get_section(index)
      if section.filters_count > 0 then
        if section.group == '' then plain_index = index else grouped_index = index end
      end
    end

    find(frame, 'shm_ol_purpose_' .. plain_index).selected_index = 2
    click(find(frame, 'shm_ol_apply_' .. plain_index))
    local group = sections.get_section(plain_index).group
    assert(string.find(group, '[reserve]', 1, true) and string.find(group, 'shm-test-a', 1, true), 'метка без группы: ' .. group)

    frame = player().gui.relative[panel.NAME]
    find(frame, 'shm_ol_purpose_' .. grouped_index).selected_index = 4
    pick(frame, 'shm_ol_places_' .. grouped_index, 'nauvis')
    click(find(frame, 'shm_ol_apply_' .. grouped_index))
    assert(sections.get_section(grouped_index).group == 'Test plates [depot:nauvis]', sections.get_section(grouped_index).group)

    frame = player().gui.relative[panel.NAME]
    find(frame, 'shm_ol_purpose_' .. grouped_index).selected_index = 1
    click(find(frame, 'shm_ol_apply_' .. grouped_index))
    assert(sections.get_section(grouped_index).group == 'Test plates', 'метка не снята')
  end)

  it('панель по умолчанию под окном и в ряд, настройка игрока переносит её вправо столбиком', function()
    local _, hub = f.platform('a')
    f.request(hub, 100, { group = 'Test fuel [reserve]', from = 'planet', import_from = f.PLANET })
    local frame = open(hub)
    assert(frame.anchor.position == defines.relative_gui_position.bottom, 'не под окном')
    assert(frame.direction == 'horizontal', 'не в ряд')
    player().mod_settings[panel.POSITION_SETTING] = { value = 'right' }
    panel.build(player(), hub)
    frame = player().gui.relative[panel.NAME]
    local ok = frame.anchor.position == defines.relative_gui_position.right and frame.direction == 'vertical'
    player().mod_settings[panel.POSITION_SETTING] = { value = 'bottom' }
    assert(ok, 'настройка положения не действует')
  end)

  it('панель подхватывает новую группу и помечает группу груза, выключенную модом', function()
    local platform, hub = f.platform('a', 'fulgora')
    f.request(hub, 5000, { group = 'Test collect [cargo→fulgora]', from = 'all' })
    remote.call('shm-orbital-logistics', 'pass')
    local frame = open(hub)
    local marked = false
    local function scan(element)
      if element.type == 'label' and type(element.caption) == 'table' and element.tooltip then
        marked = marked or (type(element.tooltip) == 'table' and element.tooltip[1] == 'shm-orbital-logistics.section-released')
      end
      for _, child in pairs(element.children) do
        scan(child)
      end
    end
    scan(frame)
    assert(marked, 'выключенная группа не помечена')
    local before = hub.get_logistic_sections().sections_count
    hub.get_logistic_sections().add_section('Test new group')
    after_ticks(70, function()
      frame = player().gui.relative[panel.NAME]
      assert(find(frame, 'shm_ol_apply_' .. (before + 1)), 'новая группа не появилась в панели')
      player().force.delete_logistic_group('Test new group')
      player().force.delete_logistic_group('Test collect [cargo→fulgora]')
      assert(platform.valid)
    end)
  end)

  --- Ключи локали строк «Отдача на этой орбите»: { [ключ] = число строк }.
  local function now_keys(frame)
    local found = {}
    local function scan(element)
      if element.type == 'label' and type(element.caption) == 'table' then
        local inner = element.caption[3]
        if type(inner) == 'table' and type(inner[1]) == 'string' then
          local key = string.match(inner[1], '^shm%-orbital%-logistics%.(now%-.+)$')
          if key then
            found[key] = (found[key] or 0) + 1
          end
        end
      end
      for _, child in pairs(element.children) do
        scan(child)
      end
    end
    scan(find(frame, 'shm_ol_now'))
    return found
  end

  it('«Отдача на этой орбите»: строка на группу с меткой, без строк для групп без метки, предупреждение про флаг', function()
    local _, hub = f.platform('a')
    hub.insert({ name = f.ITEM, count = 50 })
    f.request(hub, 100, { group = 'Test fuel [reserve]', from = 'planet', import_from = f.PLANET })
    f.request(hub, 100, { item = 'copper-plate', group = 'Test depot [depot:nauvis]', from = 'planet', import_from = f.PLANET })
    f.request(hub, 10, { item = 'steel-plate', group = 'Test plain', from = 'planet', import_from = f.PLANET })
    f.request(hub, 10, { item = 'stone', group = 'Test far [depot:vulcanus]', from = 'planet', import_from = f.PLANET })
    remote.call('shm-orbital-logistics', 'pass')
    local frame = open(hub)
    assert(find(frame, 'shm_ol_warning'), 'нет предупреждения про флаг')
    local keys = now_keys(frame)
    assert(keys['now-reserve'] == 1, 'нет строки запаса: ' .. serpent.line(keys))
    assert(keys['now-depot-here'] == 1, 'нет строки склада на своей орбите: ' .. serpent.line(keys))
    assert(keys['now-depot-held'] == 1, 'нет строки склада вне орбиты: ' .. serpent.line(keys))
    local total = 0
    for _, count in pairs(keys) do
      total = total + count
    end
    assert(total == 3, 'лишние строки (группа без метки?): ' .. serpent.line(keys))
    hub.providing_to_other_platforms = true
    player().opened = nil
    frame = open(hub)
    assert(not find(frame, 'shm_ol_warning'), 'предупреждение при включённом флаге')
  end)

  it('«Отдача на этой орбите»: исключение — склад добирает привезённый груз', function()
    local shuttle = select(2, f.platform('s'))
    shuttle.insert({ name = 'holmium-plate', count = 200 })
    shuttle.providing_to_other_platforms = true
    f.request(shuttle, 200, { item = 'holmium-plate', group = 'Test holmium [cargo→nauvis]', from = 'planet', import_from = 'fulgora' })
    local _, depot = f.platform('d')
    f.request(depot, 100, { item = 'holmium-plate', group = 'Test holmium depot [depot:nauvis]', from = 'planet', import_from = f.PLANET })
    remote.call('shm-orbital-logistics', 'pass')
    local frame = open(depot)
    local keys = now_keys(frame)
    assert(keys['now-ex-transit'] == 1, 'нет исключения транзита: ' .. serpent.line(keys))
    player().opened = nil
    frame = open(shuttle)
    keys = now_keys(frame)
    assert(keys['now-cargo-here'] == 1, 'груз на назначении не «отдаёт»: ' .. serpent.line(keys))
  end)

  it('окно линий: создать линию, подключить хаб и площадку из панели, задать шапку и роль', function()
    local p = player()
    lines_gui.open(p)
    local window = p.gui.screen[lines_gui.NAME]
    find(window, 'shm_ol_line_name').text = 'Test GUI line'
    click(find(window, 'shm_ol_line_create'))
    local line = lines.list(p.force)[1]
    assert(line and line.name == 'Test GUI line', 'линия не создана')

    local _, hub = f.platform('a')
    local frame = open(hub)
    click(find(frame, 'shm_ol_attach'))
    p.opened = nil
    local pad = f.pad()
    frame = open(pad)
    assert(frame, 'нет панели у площадки')
    click(find(frame, 'shm_ol_attach'))
    p.opened = nil
    assert(#line.participants == 2, 'участников ' .. #line.participants)

    window = p.gui.screen[lines_gui.NAME]
    local add = find(window, 'shm_ol_item_add')
    add.elem_value = { name = f.ITEM, quality = 'rare' }
    lines_gui.on_elem_changed({ element = add, player_index = p.index })
    window = p.gui.screen[lines_gui.NAME]
    find(window, 'shm_ol_count_1').text = '2000'
    find(window, 'shm_ol_role_1').selected_index = 2
    pick(window, 'shm_ol_pplaces_1', 'vulcanus')
    pick(window, 'shm_ol_pplaces_1', 'nauvis')
    assert(find(window, 'shm_ol_pplaces_1__vulcanus') and find(window, 'shm_ol_pplaces_1__nauvis'), 'места не добавлены')
    click(find(window, 'shm_ol_pplaces_1__vulcanus'))
    assert(find(window, 'shm_ol_pplaces_1__vulcanus') == nil, 'место не убрано нажатием')
    assert(find(window, 'shm_ol_import_1__choose').elem_value == 'nauvis', '«откуда» не взято по орбите хаба')
    choose(window, 'shm_ol_import_1', 'nauvis')
    find(window, 'shm_ol_mult_1').text = '5'
    find(window, 'shm_ol_mult_2').text = '0.5'
    click(find(window, 'shm_ol_line_apply'))

    local hub_group, hub_mult, pad_group, pad_mult
    for _, entry in ipairs({ { hub, 'hub' }, { pad, 'pad' } }) do
      local sections = entry[1].get_logistic_sections()
      for index = 1, sections.sections_count do
        local section = sections.get_section(index)
        if string.find(section.group, 'Test GUI line', 1, true) then
          if entry[2] == 'hub' then hub_group, hub_mult = section.group, section.multiplier else pad_group, pad_mult = section.group, section.multiplier end
        end
      end
    end
    assert(hub_group == 'Test GUI line · nauvis/platforms [depot:nauvis]', tostring(hub_group))
    assert(hub_mult == 5 and pad_group == 'Test GUI line · pad' and pad_mult == 0.5, 'площадка или множители')
    assert(line.items[1].count == 2000 and line.items[1].quality == 'rare', 'шапка')

    frame = open(hub)
    local sections = hub.get_logistic_sections()
    for index = 1, sections.sections_count do
      if sections.get_section(index).group == hub_group then
        assert(find(frame, 'shm_ol_apply_' .. index).enabled == false, 'секцию линии можно править из панели')
      end
    end
  end)
end)
