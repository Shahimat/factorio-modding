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

--- Треугольник сворачивания блока: по тегу `block` — имена у них одинаковые.
local function block_toggle(root, key)
  if not root then
    return nil
  end
  if root.name == 'shm_ol_block_toggle' and root.tags.block == key then
    return root
  end
  for _, child in pairs(root.children) do
    local found = block_toggle(child, key)
    if found then
      return found
    end
  end
  return nil
end

--- Потолок высоты панели: та же доля, что и в panel.lua.
local function height_cap()
  local p = player()
  return math.floor(p.display_resolution.height / p.display_scale * panel.HEIGHT_SHARE)
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
    -- Свёрнутость — состояние игрока: сбросить, чтобы падение одного
    -- наблюдения не свернуло панели в следующих.
    storage.panel_collapsed = {}
    storage.panel_block_collapsed = {}
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

  it('каркас при 12+ группах: панель не выше потолка рабочей области, у блоков прокрутка, потолок и при нижнем и верхнем положении', function()
    local _, hub = f.platform('a')
    local items = { 'iron-plate', 'copper-plate', 'steel-plate', 'stone', 'coal', 'iron-gear-wheel', 'copper-cable', 'electronic-circuit', 'plastic-bar', 'sulfur', 'concrete', 'battery' }
    for i, item in ipairs(items) do
      f.request(hub, 100, { item = item, group = 'Test scroll ' .. i, from = 'planet', import_from = f.OTHER_PLANET })
    end
    local cap = height_cap()
    local frame = open(hub)
    assert(frame.style.maximal_height == cap, 'потолок высоты не выставлен: ' .. tostring(frame.style.maximal_height))
    local sections_scroll = find(frame, 'shm_ol_scroll_sections')
    assert(sections_scroll and sections_scroll.type == 'scroll-pane', 'нет прокрутки «Групп»')
    local now_scroll = find(frame, 'shm_ol_scroll_now')
    assert(now_scroll and now_scroll.type == 'scroll-pane', 'нет прокрутки «Отдачи»')
    assert(sections_scroll.style.maximal_height <= cap and now_scroll.style.maximal_height <= cap, 'прокрутка выше потолка')
    -- Нижнее по умолчанию проверено; верхнее и боковое ограничены так же.
    for _, position in ipairs({ 'top', 'right' }) do
      player().mod_settings[panel.POSITION_SETTING] = { value = position }
      panel.build(player(), hub)
      frame = player().gui.relative[panel.NAME]
      assert(frame.style.maximal_height == cap, 'потолок не действует при положении ' .. position)
    end
    player().mod_settings[panel.POSITION_SETTING] = { value = 'bottom' }
  end)

  it('«Отдача» при 12 складах с исключениями по источникам: блок не выталкивает панель за потолок', function()
    local _, hub = f.platform('a')
    local items = { 'copper-plate', 'steel-plate', 'stone', 'coal', 'iron-gear-wheel', 'copper-cable', 'electronic-circuit', 'plastic-bar', 'sulfur', 'concrete', 'battery', 'engine-unit' }
    for i, item in ipairs(items) do
      -- Секция с ловушкой и без: «Платформы» у первого предмета, «Планета»
      -- у второго — секция отдаёт, но предмет с «Платформами» в исключениях.
      local section = f.request(hub, 100, { item = item, group = 'Test traps ' .. i .. ' [depot:nauvis]', from = 'platforms' })
      section.set_slot(2, {
        value = { type = 'item', name = f.ITEM, quality = 'normal', comparator = '=' },
        min = 100,
        request_from = 'planet',
        import_from = f.OTHER_PLANET,
      })
    end
    remote.call('shm-orbital-logistics', 'pass')
    local cap = height_cap()
    local frame = open(hub)
    assert(frame.style.maximal_height == cap, 'потолок высоты не выставлен')
    local now_scroll = find(frame, 'shm_ol_scroll_now')
    assert(now_scroll and now_scroll.type == 'scroll-pane', 'нет прокрутки «Отдачи»')
    assert(now_scroll.style.maximal_height <= cap, 'прокрутка «Отдачи» выше потолка')
    local keys = now_keys(frame)
    assert((keys['now-depot-here'] or 0) == 12, 'не все склады отдают: ' .. serpent.line(keys))
    assert((keys['now-depot-no-give'] or 0) == 12, 'нет исключений по «Платформам»: ' .. serpent.line(keys))
  end)

  it('блоки сворачиваются по отдельности: итог по реальному содержимому, клик по итогу разворачивает, состояние на игрока', function()
    local _, hub = f.platform('a')
    f.request(hub, 100, { group = 'Test fuel [reserve]', from = 'planet', import_from = f.PLANET })
    local depot = f.request(hub, 100, { item = 'iron-plate', group = 'Test depot [depot:nauvis]', from = 'platforms' })
    depot.set_slot(2, {
      value = { type = 'item', name = 'copper-plate', quality = 'normal', comparator = '=' },
      min = 100,
      request_from = 'planet',
      import_from = f.OTHER_PLANET,
    })
    local frame = open(hub)
    -- Снимок секций при открытии: пустые секции в «Группах» — контент блока,
    -- итог обязан считать их тоже.
    local function groups_list()
      local list = {}
      local sections = hub.get_logistic_sections()
      for index = 1, sections.sections_count do
        local section = sections.get_section(index)
        list[#list + 1] = index .. ':' .. tostring(section.is_manual) .. ':«' .. section.group .. '»:' .. section.filters_count
      end
      return list
    end
    local at_open = groups_list()
    -- Реальный контент «Групп»: строк в таблице секций — по кнопке «Применить»
    -- на каждую. Пустая безымянная секция новой платформы — тоже строка.
    local rendered_rows = 0
    local function count_apply(element)
      if element.name and string.sub(element.name, 1, 13) == 'shm_ol_apply_' then
        rendered_rows = rendered_rows + 1
      end
      for _, child in pairs(element.children) do
        count_apply(child)
      end
    end
    count_apply(frame)
    assert(find(frame, 'shm_ol_now'), '«Отдача» не развёрнута')
    assert(find(frame, 'shm_ol_scroll_sections'), '«Группы» не развёрнуты')

    -- Треугольник в заголовке «Отдачи» сворачивает только её.
    click(block_toggle(frame, 'now'))
    frame = player().gui.relative[panel.NAME]
    assert(find(frame, 'shm_ol_now') == nil, '«Отдача» не свернулась')
    local summary = find(frame, 'shm_ol_block_summary')
    assert(summary and summary.tags.block == 'now', 'нет строки-итога')
    -- Итог — по реальному содержимому: 2 группы, 1 исключение («Платформы»).
    -- Аргументы локализованной строки читаются обратно строками.
    assert(type(summary.caption) == 'table'
      and summary.caption[1] == 'shm-orbital-logistics.collapsed-now'
      and tonumber(summary.caption[2]) == 2 and tonumber(summary.caption[3]) == 1,
      'итог «Отдачи» не по содержимому: ' .. serpent.line(summary.caption))
    assert(find(frame, 'shm_ol_scroll_sections'), 'сворачивание «Отдачи» задело «Группы»')

    -- Клик по строке-итогу разворачивает обратно.
    click(find(frame, 'shm_ol_block_summary'))
    frame = player().gui.relative[panel.NAME]
    assert(find(frame, 'shm_ol_now'), 'клик по итогу не развернул «Отдачу»')

    -- Свернуть и «Группы»: блоки независимы.
    click(block_toggle(frame, 'sections'))
    frame = player().gui.relative[panel.NAME]
    assert(find(frame, 'shm_ol_scroll_sections') == nil, '«Группы» не свернулись')
    assert(find(frame, 'shm_ol_now'), 'сворачивание «Групп» задело «Отдачу»')
    -- Итог «Групп» — реальный контент блока: сколько строк рендерилось
    -- до сворачивания, столько в итоге.
    local sections_summary = find(frame, 'shm_ol_block_summary')
    assert(sections_summary and sections_summary.tags.block == 'sections'
      and type(sections_summary.caption) == 'table'
      and sections_summary.caption[1] == 'shm-orbital-logistics.collapsed-sections'
      and tonumber(sections_summary.caption[2]) == rendered_rows,
      'итог «Групп»: ' .. serpent.line(sections_summary and sections_summary.caption)
        .. ', строк при разворачивании: ' .. rendered_rows
        .. ', при открытии: ' .. serpent.line(at_open)
        .. ', при проверке: ' .. serpent.line(groups_list()))

    -- Переоткрытие окна: состояния блоков — на игрока.
    player().opened = nil
    frame = open(hub)
    assert(find(frame, 'shm_ol_scroll_sections') == nil, '«Группы» развернулись при переоткрытии')
    assert(find(frame, 'shm_ol_now'), '«Отдача» изменилась при переоткрытии')

    -- И развернуть обратно.
    click(block_toggle(frame, 'sections'))
    assert(find(player().gui.relative[panel.NAME], 'shm_ol_scroll_sections'), '«Группы» не развернулись')
  end)

  it('пустой блок линий — одна кнопка «Линии снабжения…» без заголовка и «пока нет»; с линией — полный блок', function()
    local _, hub = f.platform('a')
    local frame = open(hub)
    assert(find(frame, 'shm_ol_open_lines'), 'нет кнопки линий')
    assert(find(frame, 'shm_ol_header_lines') == nil, 'пустой блок линий получил заголовок')
    assert(find(frame, 'shm_ol_scroll_lines') == nil, 'пустой блок линий получил прокрутку')
    local none = nil
    local function scan(element)
      if element.type == 'label' and type(element.caption) == 'table' and element.caption[1] == 'shm-orbital-logistics.lines-none' then
        none = element
      end
      for _, child in pairs(element.children) do
        scan(child)
      end
    end
    scan(frame)
    assert(none == nil, 'подпись «пока нет» осталась')
    frame = open(f.pad())
    assert(find(frame, 'shm_ol_open_lines'), 'нет кнопки линий у площадки')
    assert(find(frame, 'shm_ol_header_lines') == nil, 'заголовок линий у пустой площадки')

    -- Появилась линия — блок полный: заголовок, прокрутка и подключение.
    lines_gui.open(player())
    local window = player().gui.screen[lines_gui.NAME]
    find(window, 'shm_ol_line_name').text = 'Test empty block line'
    click(find(window, 'shm_ol_line_create'))
    frame = open(hub)
    assert(find(frame, 'shm_ol_header_lines'), 'нет заголовка блока линий')
    assert(find(frame, 'shm_ol_scroll_lines'), 'нет прокрутки блока линий')
    assert(find(frame, 'shm_ol_attach_line'), 'нет подключения линии')
  end)

  it('панель сворачивается в мини-окошко с названием мода на том же краю и разворачивается, состояние переживает переоткрытие окна', function()
    local _, hub = f.platform('a')
    f.request(hub, 100, { group = 'Test fuel [reserve]', from = 'planet', import_from = f.PLANET })
    local frame = open(hub)
    assert(find(frame, 'shm_ol_toggle'), 'нет кнопки сворачивания')
    click(find(frame, 'shm_ol_toggle'))
    frame = player().gui.relative[panel.NAME]
    assert(frame and frame.tags.collapsed, 'панель не свернулась')
    assert(frame.anchor.position == defines.relative_gui_position.bottom, 'кнопка не на том же краю')
    assert(type(frame.caption) == 'table' and frame.caption[1] == 'shm-orbital-logistics.panel-title', 'свёрнутый вид не называет мод')
    assert(find(frame, 'shm_ol_toggle'), 'нет кнопки разворачивания')
    assert(not find(frame, 'shm_ol_open_lines'), 'свёрнутый вид показывает блоки панели')
    panel.refresh_all()
    assert(player().gui.relative[panel.NAME].tags.collapsed, 'свёрнутый вид перестроился в панель')

    -- Переоткрытие окна: открывается снова свёрнутым.
    player().opened = nil
    frame = open(hub)
    assert(frame and frame.tags.collapsed, 'переоткрытое окно развернулось')

    -- Настройка положения действует и на свёрнутую кнопку. Смена настройки
    -- сама перестраивает панель, поэтому ссылку на фрейм обновляем.
    player().mod_settings[panel.POSITION_SETTING] = { value = 'right' }
    frame = player().gui.relative[panel.NAME]
    local ok = frame.anchor.position == defines.relative_gui_position.right and frame.tags.collapsed
    player().mod_settings[panel.POSITION_SETTING] = { value = 'bottom' }
    frame = player().gui.relative[panel.NAME]
    assert(ok, 'настройка положения не действует на кнопку')

    click(find(frame, 'shm_ol_toggle'))
    frame = player().gui.relative[panel.NAME]
    assert(frame and not frame.tags.collapsed and find(frame, 'shm_ol_open_lines'), 'панель не развернулась обратно')
    assert(type(frame.caption) == 'table' and frame.caption[1] == 'shm-orbital-logistics.panel-title', 'развёрнутый вид потерял заголовок')

    -- Площадка сворачивается так же.
    frame = open(f.pad())
    click(find(frame, 'shm_ol_toggle'))
    frame = player().gui.relative[panel.NAME]
    assert(frame and frame.tags.collapsed, 'панель площадки не свернулась')
    click(find(frame, 'shm_ol_toggle'))
    assert(not player().gui.relative[panel.NAME].tags.collapsed, 'панель площадки не развернулась')
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

  it('«Отдача на этой орбите»: строка на группу с меткой, без строк для групп без метки, предупреждение про флаг', function()
    local _, hub = f.platform('a')
    hub.insert({ name = f.ITEM, count = 50 })
    f.request(hub, 100, { group = 'Test fuel [reserve]', from = 'planet', import_from = f.PLANET })
    -- Склад с импортом с другой планеты: источник не задевает ловушки,
    -- о которых предупреждает панель (см. тест ниже).
    f.request(hub, 100, { item = 'copper-plate', group = 'Test depot [depot:nauvis]', from = 'planet', import_from = f.OTHER_PLANET })
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

  it('предупреждения об источниках склада: «Платформы» не отдаёт, импорт с текущей планеты не сбрасывает', function()
    local _, give_hub = f.platform('a')
    f.request(give_hub, 100, { group = 'Test depot [depot:nauvis]', from = 'platforms' })
    local _, drop_hub = f.platform('b')
    f.request(drop_hub, 100, { group = 'Test depot two [depot:nauvis]', from = 'planet', import_from = f.PLANET })
    remote.call('shm-orbital-logistics', 'pass')
    local frame = open(give_hub)
    assert(find(frame, 'shm_ol_warning_depot_source'), 'нет предупреждения про источник «Платформы»')
    assert(find(frame, 'shm_ol_warning_depot_drop') == nil, 'предупреждение про сброс без импорта с текущей планеты')
    local keys = now_keys(frame)
    -- Все предметы склада с источником «Платформы»: строка группы сама
    -- говорит «не сможет отдавать платформам», в исключениях повтора нет.
    assert(keys['now-depot-no-give'] == 1, 'нет строки «не сможет отдавать платформам»: ' .. serpent.line(keys))
    player().opened = nil
    frame = open(drop_hub)
    assert(find(frame, 'shm_ol_warning_depot_drop'), 'нет предупреждения про сброс на текущую планету')
    assert(find(frame, 'shm_ol_warning_depot_source') == nil, 'предупреждение про «Платформы» у источника «Планета»')
    keys = now_keys(frame)
    assert(keys['now-depot-here'] == 1, 'склад с «Планетой» должен отдавать платформам: ' .. serpent.line(keys))
    assert(keys['now-depot-no-drop'] == 1, 'нет исключения «не сбросит на эту планету»: ' .. serpent.line(keys))
  end)

  it('окно линий: роль «Склад» с ловушкой источника получает предупреждение', function()
    local p = player()
    lines_gui.open(p)
    local window = p.gui.screen[lines_gui.NAME]
    find(window, 'shm_ol_line_name').text = 'Test depot line'
    click(find(window, 'shm_ol_line_create'))
    local _, hub = f.platform('a')
    local frame = open(hub)
    click(find(frame, 'shm_ol_attach'))
    p.opened = nil
    -- При подключении источник по умолчанию «Платформы»: у роли «Склад» —
    -- предупреждение о том, что платформам склад не отдаст.
    window = p.gui.screen[lines_gui.NAME]
    find(window, 'shm_ol_role_1').selected_index = 2
    click(find(window, 'shm_ol_line_apply'))
    window = p.gui.screen[lines_gui.NAME]
    assert(find(window, 'shm_ol_lines_warning_source'), 'нет предупреждения про источник «Платформы» у роли «Склад»')
    -- Источник «Планета» с импортом с текущей планеты: предупреждение о сбросе.
    find(window, 'shm_ol_source_1').selected_index = 1
    click(find(window, 'shm_ol_line_apply'))
    window = p.gui.screen[lines_gui.NAME]
    assert(find(window, 'shm_ol_lines_warning_drop'), 'нет предупреждения про сброс на текущую планету')
    assert(find(window, 'shm_ol_lines_warning_source') == nil, 'предупреждение про «Платформы» осталось у источника «Планета»')
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
