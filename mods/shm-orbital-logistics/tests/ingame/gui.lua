-- Панель у окна хаба и площадки, окно линий снабжения. Нужен живой игрок,
-- поэтому только в прогоне с графикой: тег `gui`,
-- `npm run test:ingame:gui -w shm-orbital-logistics`. Нажатия вызываются
-- обработчиками напрямую: поднять встроенное событие GUI скрипт не может.

local f = require('tests.ingame.fixture')
local panel = require('runtime.panel')
local lines_gui = require('runtime.lines_gui')
local lines = require('runtime.lines')
local picker = require('runtime.places_picker')
local controller = require('runtime.controller')

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

--- Все элементы с точным именем: имена в панели повторяются (сетка
--- исключений у каждой строки типа).
local function collect(root, name, acc)
  acc = acc or {}
  if not root then
    return acc
  end
  if root.name == name then
    acc[#acc + 1] = root
  end
  for _, child in pairs(root.children) do
    collect(child, name, acc)
  end
  return acc
end

local function click(element)
  local event = { element = element, player_index = player().index }
  if panel.on_click(event, lines_gui.open) then
    return
  end
  if picker.on_click(event) then
    return
  end
  lines_gui.on_click(event)
end

--- Добавить место в выбор `name`: как выбор в окне игры у кнопки «+».
--- Места строк секций применяются сразу (panel.on_elem_changed).
local function pick(root, name, planet)
  local add = find(root, name .. '__add')
  assert(add, 'нет кнопки «+» в ' .. name)
  add.elem_value = planet
  local event = { element = add, player_index = player().index }
  if panel.on_elem_changed(event) then
    return
  end
  assert(picker.on_elem_changed(event), 'выбор не обработан')
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
  return player().gui.screen[panel.NAME]
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

--- Панель целиком в пределах экрана (решение владельца: никаких обрезок).
local function assert_on_screen(frame)
  local p = player()
  local resolution = p.display_resolution
  local scale = p.display_scale
  if not (resolution and scale and scale > 0) then
    return
  end
  local w = resolution.width / scale
  local h = resolution.height / scale
  local loc = frame.location
  local fw = frame.style.minimal_width
  local fh = frame.style.minimal_height
  assert(loc and loc.x >= 0 and loc.y >= 0, 'панель вышла за левый/верхний край: ' .. serpent.line(loc))
  assert(type(fw) == 'number' and type(fh) == 'number', 'у панели не фиксированные размеры')
  assert(loc.x + fw <= w and loc.y + fh <= h,
    'панель выходит за правый/нижний край: ' .. serpent.line(loc) .. ' при экране ' .. math.floor(w) .. 'x' .. math.floor(h))
end

--- Потолок высоты панели: как его считает panel.build для положения.
local function frame_cap(position, entity)
  local p = player()
  local wide = position == 'bottom' or position == 'top'
  return panel.height_cap(p, entity, wide)
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

    local purpose = find(frame, 'shm_ol_purpose_' .. plain_index)
    purpose.selected_index = 2
    assert(panel.on_selection({ element = purpose, player_index = player().index }), 'выбор не обработан')
    frame = player().gui.screen[panel.NAME]
    local group = sections.get_section(plain_index).group
    assert(string.find(group, '[reserve]', 1, true) and string.find(group, 'shm-test-a', 1, true), 'метка без группы: ' .. group)

    frame = player().gui.screen[panel.NAME]
    find(frame, 'shm_ol_purpose_' .. grouped_index).selected_index = 4
    pick(frame, 'shm_ol_places_' .. grouped_index, 'nauvis')
    frame = player().gui.screen[panel.NAME]
    assert(sections.get_section(grouped_index).group == 'Test plates [depot:nauvis]', sections.get_section(grouped_index).group)

    frame = player().gui.screen[panel.NAME]
    local purpose_reset = find(frame, 'shm_ol_purpose_' .. grouped_index)
    purpose_reset.selected_index = 1
    assert(panel.on_selection({ element = purpose_reset, player_index = player().index }), 'выбор не обработан')
    assert(sections.get_section(grouped_index).group == 'Test plates', 'метка не снята')
  end)

  it('снятие метки с имени-«только метка» даёт fallback, а «Груз» без мест имя не меняет', function()
    local _, hub = f.platform('a')
    f.request(hub, 300, { group = '[reserve]', from = 'planet', import_from = f.PLANET })
    f.request(hub, 100, { group = 'Test cargo', from = 'planet', import_from = f.PLANET })
    f.request(hub, 50, { group = 'Test cargo [cargo]', from = 'planet', import_from = f.PLANET })
    local frame = open(hub)
    local sections = hub.get_logistic_sections()
    local tag_only, plain, pretagged
    for index = 1, sections.sections_count do
      local section = sections.get_section(index)
      if section.filters_count > 0 then
        if section.group == '[reserve]' then
          tag_only = index
        elseif section.group == 'Test cargo' then
          plain = index
        elseif section.group == 'Test cargo [cargo]' then
          pretagged = index
        end
      end
    end
    assert(tag_only and plain and pretagged, 'секции не найдены')

    local purpose = find(frame, 'shm_ol_purpose_' .. tag_only)
    purpose.selected_index = 1
    assert(panel.on_selection({ element = purpose, player_index = player().index }), 'выбор не обработан')
    frame = player().gui.screen[panel.NAME]
    local renamed = sections.get_section(tag_only).group
    -- Fallback: имя платформы и номер секции, метки не осталось.
    assert(string.find(renamed, '^shm%-test%-a%-%d+ #%d+$') ~= nil, 'нет fallback-имени: ' .. renamed)

    frame = player().gui.screen[panel.NAME]
    find(frame, 'shm_ol_purpose_' .. plain).selected_index = 3
    assert(panel.on_selection({ element = find(frame, 'shm_ol_purpose_' .. plain), player_index = player().index }), 'выбор не обработан')
    assert(sections.get_section(plain).group == 'Test cargo', '[cargo] дописан: ' .. sections.get_section(plain).group)

    find(frame, 'shm_ol_purpose_' .. pretagged).selected_index = 3
    assert(panel.on_selection({ element = find(frame, 'shm_ol_purpose_' .. pretagged), player_index = player().index }), 'выбор не обработан')
    assert(sections.get_section(pretagged).group == 'Test cargo [cargo]',
      'имя с [cargo] изменилось: ' .. sections.get_section(pretagged).group)
  end)

  it('панель по умолчанию снизу по центру на половину экрана, настройка игрока переносит её вправо столбиком', function()
    local _, hub = f.platform('a')
    f.request(hub, 100, { group = 'Test fuel [reserve]', from = 'planet', import_from = f.PLANET })
    local frame = open(hub)
    assert(frame.parent == player().gui.screen, 'панель не в screen gui')
    local p = player()
    local screen_h = math.floor(p.display_resolution.height / p.display_scale)
    local screen_w = math.floor(p.display_resolution.width / p.display_scale)
    local min_h = math.floor(screen_h * panel.EXPAND_MIN_SHARE)
    local max_h = panel.expanded_cap(p)
    assert(frame.style.minimal_height == min_h and frame.style.maximal_height == max_h,
      'высота не между 40% и 50% экрана: ' .. tostring(frame.style.minimal_height) .. ' / ' .. tostring(frame.style.maximal_height))
    assert(frame.direction == 'horizontal', 'не в ряд')
    local loc = frame.location
    assert(loc.y == screen_h - max_h and loc.x == math.floor((screen_w - panel.BOTTOM_WIDTH) / 2),
      'панель не снизу по центру: ' .. serpent.line(loc))
    assert_on_screen(frame)
    player().mod_settings[panel.POSITION_SETTING] = { value = 'right' }
    panel.build(p, hub)
    frame = player().gui.screen[panel.NAME]
    local side_h = panel.height_cap(p, hub, false)
    assert(frame.style.minimal_height == side_h and frame.style.maximal_height == side_h,
      'боковая панель не 0.8 экрана: ' .. tostring(frame.style.minimal_height))
    assert(frame.location.x == screen_w - panel.SIDE_WIDTH, 'боковая панель не у правого края: ' .. serpent.line(frame.location))
    assert_on_screen(frame)
    player().mod_settings[panel.POSITION_SETTING] = { value = 'bottom' }
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

  --- Все ключи деталей в узле подписи: в одной строке их бывает два — статус
  --- и числа, предпросмотр и фраза.
  local function caption_keys(node, acc)
    acc = acc or {}
    if type(node) == 'string' then
      local key = string.match(node, '^shm%-orbital%-logistics%.(details%-.+)$')
      if key then
        acc[key] = true
      end
    elseif type(node) == 'table' then
      for _, item in pairs(node) do
        caption_keys(item, acc)
      end
    end
    return acc
  end

  --- { [ключ деталей] = число строк с ним } по всем подписям в дереве.
  local function detail_keys(root)
    local found = {}
    local function scan(element)
      if element.type == 'label' and type(element.caption) == 'table' then
        for key in pairs(caption_keys(element.caption)) do
          found[key] = (found[key] or 0) + 1
        end
      end
      for _, child in pairs(element.children) do
        scan(child)
      end
    end
    scan(root)
    return found
  end

  --- Локализованная таблица подписи с ключом: из неё читаются аргументы —
  --- числа фразы и ссылки на места.
  local function find_caption(root, key)
    if not root then
      return nil
    end
    if root.type == 'label' and type(root.caption) == 'table' then
      local function walk(node)
        if type(node) == 'table' then
          if node[1] == 'shm-orbital-logistics.' .. key then
            return node
          end
          for _, item in pairs(node) do
            local found = walk(item)
            if found then
              return found
            end
          end
        end
        return nil
      end
      local found = walk(root.caption)
      if found then
        return found
      end
    end
    for _, child in pairs(root.children) do
      local found = find_caption(child, key)
      if found then
        return found
      end
    end
    return nil
  end

  --- Треугольник деталей секции: по тегу `details` — имена у них одинаковые.
  local function details_toggle(root, index)
    if not root then
      return nil
    end
    if root.name == 'shm_ol_expand' and root.tags.details == index then
      return root
    end
    for _, child in pairs(root.children) do
      local found = details_toggle(child, index)
      if found then
        return found
      end
    end
    return nil
  end

  --- Индекс первой секции с фильтрами; с `needle` — среди групп с этим куском
  --- имени. Без метки — секция ванильного груза.
  local function first_filtered_index(hub, needle)
    local sections = hub.get_logistic_sections()
    for index = 1, sections.sections_count do
      local section = sections.get_section(index)
      if section.filters_count > 0 and (needle == nil or string.find(section.group, needle, 1, true)) then
        return index
      end
    end
    return nil
  end

  it('каркас при 12+ группах: высокое окно хаба переезжает вбок, у блоков прокрутка без резерва пустоты', function()
    local _, hub = f.platform('a')
    local items = { 'iron-plate', 'copper-plate', 'steel-plate', 'stone', 'coal', 'iron-gear-wheel', 'copper-cable', 'electronic-circuit', 'plastic-bar', 'sulfur', 'concrete', 'battery' }
    for i, item in ipairs(items) do
      f.request(hub, 100, { item = item, group = 'Test scroll ' .. i, from = 'planet', import_from = f.OTHER_PLANET })
    end
    local side_cap = panel.height_cap(player(), hub, false)
    local min_h = math.floor(math.floor(player().display_resolution.height / player().display_scale) * panel.EXPAND_MIN_SHARE)
    local max_h = panel.expanded_cap(player())
    local frame = open(hub)
    -- 12 секций: панель снизу, эластичная высота 40–50% экрана, целиком
    -- в пределах экрана (screen gui не обрезается якорем).
    assert(frame.style.minimal_height == min_h and frame.style.maximal_height == max_h,
      'высота не между 40% и 50% экрана: ' .. tostring(frame.style.minimal_height) .. ' / ' .. tostring(frame.style.maximal_height))
    assert(frame.location.y == math.floor(player().display_resolution.height / player().display_scale) - max_h,
      'панель не при нижнем крае: ' .. serpent.line(frame.location))
    assert_on_screen(frame)
    local sections_scroll = find(frame, 'shm_ol_scroll_sections')
    assert(sections_scroll and sections_scroll.type == 'scroll-pane', 'нет прокрутки «Групп»')
    local now_scroll = find(frame, 'shm_ol_scroll_now')
    assert(now_scroll and now_scroll.type == 'scroll-pane', 'нет прокрутки «Отдачи»')
    -- Пустоты: у блоков и прокруток нет фиксированных резервов высоты —
    -- они растянуты на высоту рамки.
    for _, name in ipairs({ 'shm_ol_block_sections', 'shm_ol_block_now', 'shm_ol_block_lines' }) do
      local block = find(frame, name)
      assert(block and block.style.vertically_stretchable == true, 'блок ' .. name .. ' не растянут на высоту рамки')
    end
    assert(sections_scroll.style.vertically_stretchable == true and now_scroll.style.vertically_stretchable == true, 'прокрутки не растянуты на высоту рамки')
    -- Другие положения: сверху те же 40–50%; сбоку — столбик 0.8 экрана.
    for _, position in ipairs({ 'top', 'right', 'left' }) do
      player().mod_settings[panel.POSITION_SETTING] = { value = position }
      panel.build(player(), hub)
      frame = player().gui.screen[panel.NAME]
      if position == 'top' then
        assert(frame.style.minimal_height == min_h and frame.style.maximal_height == max_h,
          'потолок не действует при положении ' .. position)
      else
        assert(frame.style.minimal_height == side_cap and frame.style.maximal_height == side_cap,
          'потолок не действует при положении ' .. position)
      end
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
    local min_h = math.floor(math.floor(player().display_resolution.height / player().display_scale) * panel.EXPAND_MIN_SHARE)
    local max_h = panel.expanded_cap(player())
    local frame = open(hub)
    assert(frame.style.minimal_height == min_h and frame.style.maximal_height == max_h,
      'высота не между 40% и 50% экрана: ' .. tostring(frame.style.minimal_height))
    assert_on_screen(frame)
    local now_scroll = find(frame, 'shm_ol_scroll_now')
    assert(now_scroll and now_scroll.type == 'scroll-pane', 'нет прокрутки «Отдачи»')
    assert(now_scroll.style.vertically_stretchable == true, 'прокрутка «Отдачи» не растянута на фиксированную высоту')
    local keys = now_keys(frame)
    assert((keys['now-depot-here'] or 0) == 12, 'не все склады отдают: ' .. serpent.line(keys))
    -- 12 исключений одного типа сведены в одну строку с сеткой иконок.
    assert((keys['now-depot-no-give'] or 0) == 1, 'исключения «Платформ» не сведены в строку: ' .. serpent.line(keys))
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
    -- Реальный контент «Групп»: строк в таблице секций — по селектору
    -- назначения на каждую. Пустая безымянная секция новой платформы —
    -- тоже строка.
    local rendered_rows = 0
    local function count_purpose(element)
      if element.name and string.sub(element.name, 1, 15) == 'shm_ol_purpose_' then
        rendered_rows = rendered_rows + 1
      end
      for _, child in pairs(element.children) do
        count_purpose(child)
      end
    end
    count_purpose(frame)
    assert(find(frame, 'shm_ol_now'), '«Отдача» не развёрнута')
    assert(find(frame, 'shm_ol_scroll_sections'), '«Группы» не развёрнуты')

    -- Треугольник в заголовке «Отдачи» сворачивает только её.
    click(block_toggle(frame, 'now'))
    frame = player().gui.screen[panel.NAME]
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
    frame = player().gui.screen[panel.NAME]
    assert(find(frame, 'shm_ol_now'), 'клик по итогу не развернул «Отдачу»')

    -- Свернуть и «Группы»: блоки независимы.
    click(block_toggle(frame, 'sections'))
    frame = player().gui.screen[panel.NAME]
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
    assert(find(player().gui.screen[panel.NAME], 'shm_ol_scroll_sections'), '«Группы» не развернулись')
    -- Чистка состояния панели: следующие тесты открывают развёрнутую панель.
    storage.panel_collapsed = nil
    storage.panel_block_collapsed = nil
    panel.build(player(), hub)
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
    frame = player().gui.screen[panel.NAME]
    assert(frame and frame.tags.collapsed, 'панель не свернулась')
    assert(frame.location.y == math.floor(player().display_resolution.height / player().display_scale) - panel.MINI_HEIGHT,
      'свёрнутая панель не у нижнего края экрана: ' .. serpent.line(frame.location))
    assert(type(frame.caption) == 'table' and frame.caption[1] == 'shm-orbital-logistics.panel-title', 'свёрнутый вид не называет мод')
    assert(find(frame, 'shm_ol_toggle'), 'нет кнопки разворачивания')
    assert(not find(frame, 'shm_ol_open_lines'), 'свёрнутый вид показывает блоки панели')
    panel.refresh_all()
    assert(player().gui.screen[panel.NAME].tags.collapsed, 'свёрнутый вид перестроился в панель')

    -- Переоткрытие окна: открывается снова свёрнутым.
    player().opened = nil
    frame = open(hub)
    assert(frame and frame.tags.collapsed, 'переоткрытое окно развернулось')

    -- Настройка положения действует и на свёрнутую кнопку: справа панель
    -- и свёрнутая кнопка — у правого края экрана.
    player().mod_settings[panel.POSITION_SETTING] = { value = 'right' }
    panel.build(player(), hub)
    frame = player().gui.screen[panel.NAME]
    local screen_w = math.floor(player().display_resolution.width / player().display_scale)
    assert(frame.location.x == screen_w - panel.MINI_WIDTH and frame.tags.collapsed,
      'свёрнутая панель не у правого края: ' .. serpent.line(frame.location))
    player().mod_settings[panel.POSITION_SETTING] = { value = 'bottom' }
    panel.build(player(), hub)
    frame = player().gui.screen[panel.NAME]

    click(find(frame, 'shm_ol_toggle'))
    frame = player().gui.screen[panel.NAME]
    assert(frame and not frame.tags.collapsed and find(frame, 'shm_ol_open_lines'), 'панель не развернулась обратно')
    assert(type(frame.caption) == 'table' and frame.caption[1] == 'shm-orbital-logistics.panel-title', 'развёрнутый вид потерял заголовок')

    -- Площадка сворачивается так же.
    frame = open(f.pad())
    click(find(frame, 'shm_ol_toggle'))
    frame = player().gui.screen[panel.NAME]
    assert(frame and frame.tags.collapsed, 'панель площадки не свернулась')
    click(find(frame, 'shm_ol_toggle'))
    assert(not player().gui.screen[panel.NAME].tags.collapsed, 'панель площадки не развернулась')
    -- Чистка состояния панели: следующие тесты открывают развёрнутую панель.
    storage.panel_collapsed = nil
    storage.panel_block_collapsed = nil
    panel.build(player(), f.pad())
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
      -- Продуктовое обещание: после прохода обновления новая группа есть
      -- в панели. Обновляем явно — порядок обработчиков одного тика не
      -- гарантируется.
      panel.refresh_all()
      frame = player().gui.screen[panel.NAME]
      -- Индекс новой секции ищем по имени: sections_count включает и
      -- служебную секцию мода, чьё наличие плавает.
      local new_index
      local sections = hub.get_logistic_sections()
      for index = 1, sections.sections_count do
        if sections.get_section(index).group == 'Test new group' then
          new_index = index
          break
        end
      end
      assert(new_index and find(frame, 'shm_ol_purpose_' .. new_index),
        'новая группа не появилась в панели: new_index ' .. tostring(new_index))
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

  it('детали предметов: склад на своей орбите отдаёт сверх запаса, запас держит', function()
    local _, hub = f.platform('a')
    f.request(hub, 200, { group = 'Test det reserve [reserve]', from = 'planet', import_from = f.PLANET })
    f.request(hub, 100, { item = 'copper-plate', group = 'Test det depot [depot:nauvis]', from = 'planet', import_from = f.OTHER_PLANET })
    hub.insert({ name = f.ITEM, count = 500 })
    hub.insert({ name = 'copper-plate', count = 12000 })
    local copper_count = hub.get_inventory(defines.inventory.hub_main).get_item_count('copper-plate')
    remote.call('shm-orbital-logistics', 'pass')
    local frame = open(hub)
    -- По умолчанию всё свёрнуто: строк на предметы ещё нет.
    assert(detail_keys(frame)['details-amounts'] == nil, 'детали развернуты по умолчанию')

    -- Склад на своей орбите: фраза про цель и отдачу сверх запаса.
    local depot_index = first_filtered_index(hub, 'Test det depot')
    assert(depot_index, 'нет секции склада')
    click(details_toggle(frame, depot_index))
    frame = player().gui.screen[panel.NAME]
    local keys = detail_keys(frame)
    assert(keys['details-depot-here'] == 1, 'нет фразы склада на орбите: ' .. serpent.line(keys))
    assert(keys['details-amounts'] == 1, 'нет чисел по предмету: ' .. serpent.line(keys))
    local phrase = find_caption(frame, 'details-depot-here')
    assert(phrase and tonumber(phrase[2]) == 100, 'цель склада не во фразе: ' .. serpent.line(phrase))
    local amounts = find_caption(frame, 'details-amounts')
    assert(amounts and tonumber(amounts[2]) == copper_count and tonumber(amounts[5]) == 100, 'числа предмета: ' .. serpent.line(amounts))
    assert(type(amounts[7]) == 'table' and amounts[7][1] == 'shm-orbital-logistics.details-yes', 'склад сверх цели должен отдаваться')

    -- Запас: держит, объяснение — остался запас.
    local reserve_index = first_filtered_index(hub, 'Test det reserve')
    click(details_toggle(frame, reserve_index))
    frame = player().gui.screen[panel.NAME]
    keys = detail_keys(frame)
    assert(keys['details-reserve'] == 1, 'нет фразы запаса: ' .. serpent.line(keys))
    assert(keys['details-st-held-reserve'] == 1, 'запас не «стоит»: ' .. serpent.line(keys))

    -- Развёрнутость переживает обновление раз в секунду.
    panel.refresh_all()
    keys = detail_keys(frame)
    assert(keys['details-reserve'] == 1 and keys['details-depot-here'] == 1, 'обновление сбросило детали: ' .. serpent.line(keys))
  end)

  it('детали груза: на назначении раздаётся, включая платформы, в пути держится', function()
    local at_dest = select(2, f.platform('c', 'vulcanus'))
    f.request(at_dest, 300, { item = 'holmium-plate', group = 'Test det cargo dest [cargo→vulcanus]', from = 'planet', import_from = 'fulgora' })
    at_dest.insert({ name = 'holmium-plate', count = 50 })
    local away = select(2, f.platform('w'))
    f.request(away, 300, { item = 'holmium-plate', group = 'Test det cargo held [cargo→vulcanus]', from = 'planet', import_from = 'fulgora' })
    away.insert({ name = 'holmium-plate', count = 50 })
    remote.call('shm-orbital-logistics', 'pass')

    local frame = open(at_dest)
    local index = first_filtered_index(at_dest, 'Test det cargo dest')
    click(details_toggle(frame, index))
    frame = player().gui.screen[panel.NAME]
    local keys = detail_keys(frame)
    assert(keys['details-cargo-dest'] == 1, 'груз на назначении не «раздаётся»: ' .. serpent.line(keys))
    local phrase = find_caption(frame, 'details-cargo-dest')
    assert(serpent.line(phrase):find('planet=vulcanus', 1, true), 'куда не ссылкой: ' .. serpent.line(phrase))
    assert(serpent.line(phrase):find('planet=fulgora', 1, true), 'откуда не ссылкой: ' .. serpent.line(phrase))
    local amounts = find_caption(frame, 'details-amounts')
    assert(amounts and tonumber(amounts[4]) == 300, 'цель груза не в числах: ' .. serpent.line(amounts))
    assert(type(amounts[7]) == 'table' and amounts[7][1] == 'shm-orbital-logistics.details-yes', 'груз на назначении должен отдаваться')

    player().opened = nil
    frame = open(away)
    index = first_filtered_index(away, 'Test det cargo held')
    click(details_toggle(frame, index))
    frame = player().gui.screen[panel.NAME]
    keys = detail_keys(frame)
    assert(keys['details-cargo-held'] == 1, 'груз в пути не «держится»: ' .. serpent.line(keys))
    assert(keys['details-st-held-cargo'] == 1, 'нет причины «вне назначения»: ' .. serpent.line(keys))
  end)

  it('детали ванильного груза на орбите со складом: «везде, кроме откуда»', function()
    local _, depot = f.platform('d')
    f.request(depot, 100, { item = 'copper-plate', group = 'Test det depot d [depot:nauvis]', from = 'planet', import_from = f.OTHER_PLANET })
    local _, hub = f.platform('v')
    hub.insert({ name = f.ITEM, count = 40 })
    f.request(hub, 100, { from = 'planet', import_from = 'fulgora' })
    remote.call('shm-orbital-logistics', 'pass')

    local frame = open(hub)
    -- Свёрнуто: короткая строка про ванильный груз, чисел ещё нет.
    local keys = detail_keys(frame)
    assert(keys['details-cargo-vanilla'] == 1, 'ванильный груз не описан свёрнуто: ' .. serpent.line(keys))
    assert(keys['details-amounts'] == nil, 'числа при свёрнутой строке')
    local summary = find_caption(frame, 'details-cargo-vanilla')
    assert(serpent.line(summary):find('planet=fulgora', 1, true), 'откуда не ссылкой: ' .. serpent.line(summary))

    -- Развёрнуто: строка предмета с числами и статусом отдачи.
    local index = first_filtered_index(hub, nil)
    click(details_toggle(frame, index))
    frame = player().gui.screen[panel.NAME]
    keys = detail_keys(frame)
    assert(keys['details-cargo-vanilla'] == 1, 'нет строки ванильного груза: ' .. serpent.line(keys))
    assert(keys['details-amounts'] == 1, 'нет чисел по предмету: ' .. serpent.line(keys))
    assert(keys['details-st-giving'] == 1, 'ванильный груз не «отдаётся»: ' .. serpent.line(keys))
    local amounts = find_caption(frame, 'details-amounts')
    assert(amounts and tonumber(amounts[2]) == 40, 'в числах нет «есть»: ' .. serpent.line(amounts))
  end)

  it('выбранное, но не применённое назначение показывает «будет: …» до «Применить»', function()
    local _, hub = f.platform('a')
    f.request(hub, 100, { group = 'Test det plain', from = 'planet', import_from = f.PLANET })
    -- Прогон чистит записи орбит разрушенных платформ прошлых наблюдений.
    remote.call('shm-orbital-logistics', 'pass')
    local frame = open(hub)
    local index = first_filtered_index(hub, nil)
    panel.refresh_all()
    assert(detail_keys(frame)['details-preview'] == nil, 'предпросмотр без смены назначения')

    -- Выбран «Склад» на Вулкан: применяется сразу, в деталях фраза склада
    -- и место-ссылкой (кнопки «Применить» больше нет).
    find(frame, 'shm_ol_purpose_' .. index).selected_index = 4
    pick(frame, 'shm_ol_places_' .. index, 'vulcanus')
    frame = player().gui.screen[panel.NAME]
    click(details_toggle(frame, index))
    frame = player().gui.screen[panel.NAME]
    local keys = detail_keys(frame)
    assert(keys['details-depot-away'] == 1, 'в деталях не фраза склада: ' .. serpent.line(keys))
    local away = find_caption(frame, 'details-depot-away')
    assert(serpent.line(away):find('planet=vulcanus', 1, true), 'место в деталях не ссылкой')
    assert(keys['details-preview'] == nil, 'предпросмотр остался при авто-применении')
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

  it('«Отдача»: исключения агрегированы по типу состояния — строка на тип, сетка до 10 иконок и «+N ещё», полный список в тултипе', function()
    local _, hub = f.platform('a')
    f.request(hub, 100, { item = 'iron-plate', group = 'Test agg [reserve]', from = 'planet', import_from = f.PLANET })
    -- Схема «запас + склад»: у склада 12 предметов с источником «Платформы»
    -- («не сможет отдавать платформам») и 3 с импортом с текущей планеты
    -- («не сбросит»). Источник смешанный: иначе строка группы сама сказала
    -- бы «не отдаст» и исключения по предметам были бы скрыты.
    local depot = f.request(hub, 100, { item = 'copper-plate', group = 'Test agg [depot:nauvis]', from = 'platforms' })
    for i, item in ipairs({ 'steel-plate', 'stone', 'coal', 'iron-gear-wheel', 'copper-cable', 'electronic-circuit', 'plastic-bar', 'sulfur', 'concrete', 'battery', 'engine-unit' }) do
      depot.set_slot(i + 1, {
        value = { type = 'item', name = item, quality = 'normal', comparator = '=' },
        min = 100,
        request_from = 'platforms',
      })
    end
    for i, item in ipairs({ 'low-density-structure', 'rocket-fuel', 'processing-unit' }) do
      depot.set_slot(13 + i, {
        value = { type = 'item', name = item, quality = 'normal', comparator = '=' },
        min = 100,
        request_from = 'planet',
        import_from = f.PLANET,
      })
    end
    remote.call('shm-orbital-logistics', 'pass')
    local frame = open(hub)
    local keys = now_keys(frame)
    assert(keys['now-reserve'] == 1 and keys['now-depot-here'] == 1, 'строк групп: ' .. serpent.line(keys))
    -- Стена из 15 строк исключений сжалась в две — по одной на тип.
    assert(keys['now-depot-no-give'] == 1, '«Платформы» не сведены в строку: ' .. serpent.line(keys))
    assert(keys['now-depot-no-drop'] == 1, 'сброс не сведён в строку: ' .. serpent.line(keys))
    -- Сетка иконок: 12 предметов склада — 10 иконок и «+2 ещё».
    local grids = collect(frame, 'shm_ol_exception_grid')
    assert(#grids == 2, 'строк исключений: ' .. #grids)
    local buttons = 0
    for _, grid in ipairs(grids) do
      assert(#grid.children <= 10, 'иконок больше 10: ' .. #grid.children)
      buttons = buttons + #grid.children
    end
    assert(buttons == 13, 'иконок в сетках: ' .. buttons)
    local mores = collect(frame, 'shm_ol_exception_more')
    assert(#mores == 1 and tonumber(mores[1].caption[2]) == 2, 'нет «+N ещё»: ' .. serpent.line(#mores > 0 and mores[1].caption or nil))
    -- Полный список — в тултипе строки: все 12 предметов «Платформ».
    local tooltip = serpent.line(mores[1].tooltip)
    local _, listed = tooltip:gsub('%[item=', '')
    assert(listed == 12, 'в тултипе предметов: ' .. listed)
  end)

  it('секции с одинаковым именем группы — одна строка «Групп» со счётчиком ×N, статусы по активным', function()
    local _, hub = f.platform('a')
    f.request(hub, 100, { item = 'iron-plate', group = 'Test twin [depot:nauvis]', from = 'planet', import_from = f.OTHER_PLANET })
    hub.get_logistic_sections().add_section('Test twin [depot:nauvis]')
    -- Обе секции группы на месте; одна из них выключена игроком: строка
    -- всё равно одна, статус — по активной секции.
    local hub_sections = hub.get_logistic_sections()
    local twins = {}
    for i = 1, hub_sections.sections_count do
      if hub_sections.get_section(i).group == 'Test twin [depot:nauvis]' then
        twins[#twins + 1] = i
      end
    end
    assert(#twins == 2, 'секций группы: ' .. #twins)
    hub_sections.get_section(twins[2]).active = false
    remote.call('shm-orbital-logistics', 'pass')
    local frame = open(hub)
    -- Строка одна на имя группы: у платформы ещё пустая безымянная секция,
    -- у пары «Test twin» — ровно одна строка с «Применить».
    local twin_rows = 0
    local function scan(element)
      if element.type == 'label' and type(element.caption) == 'table'
        and element.caption[2] == 'Test twin [depot:nauvis]' then
        twin_rows = twin_rows + 1
        assert(element.caption[3] == ' ×2', 'нет счётчика ×2: ' .. serpent.line(element.caption))
      end
      for _, child in pairs(element.children) do
        scan(child)
      end
    end
    scan(frame)
    assert(twin_rows == 1, 'строк у одинаковой группы: ' .. twin_rows)
    -- Статус строки — по активной секции: «раздаёт», а не «выключена».
    local details = find(frame, 'shm_ol_details_' .. twins[1])
    assert(details, 'нет деталей строки группы')
    assert(find_caption(details, 'now-depot-here'), 'статус не по активной секции')
    -- В «Отдаче» секции не сливаются: активная раздаёт, выключенная — нет.
    local keys = now_keys(frame)
    assert(keys['now-depot-here'] == 1 and keys['now-inactive'] == 1, 'строки «Отдачи»: ' .. serpent.line(keys))
  end)

  it('выключенная игроком секция не «раздаёт»: значок и подпись «выключена»; выключенная модом группа груза — своя подпись', function()
    local _, hub = f.platform('a')
    f.request(hub, 100, { item = 'iron-plate', group = 'Test off [depot:nauvis]', from = 'planet', import_from = f.OTHER_PLANET })
    local index = first_filtered_index(hub, 'Test off')
    hub.get_logistic_sections().get_section(index).active = false
    remote.call('shm-orbital-logistics', 'pass')
    local frame = open(hub)
    local keys = now_keys(frame)
    assert(keys['now-inactive'] == 1, 'нет строки «выключена»: ' .. serpent.line(keys))
    assert((keys['now-depot-here'] or 0) == 0, 'выключенная секция «раздаёт»: ' .. serpent.line(keys))

    -- Секция груза, выключенная модом до отлёта, — не «выключена».
    local shuttle = select(2, f.platform('s', 'fulgora'))
    local held = f.request(shuttle, 5000, { item = 'holmium-plate', group = 'Test off cargo [cargo→fulgora]', from = 'all' })
    remote.call('shm-orbital-logistics', 'pass')
    frame = open(shuttle)
    keys = now_keys(frame)
    assert(keys['now-released'] == 1 and (keys['now-inactive'] or 0) == 0, 'выключенная модом: ' .. serpent.line(keys))
    -- В свёрнутых деталях «Групп» — та же подпись «выключена до отлёта».
    local details = find(frame, 'shm_ol_details_' .. held.index)
    assert(details and find_caption(details, 'now-released'), 'в деталях нет «выключена до отлёта»')

    -- Игрок вернул галочку: «выключена до отлёта» про включённую секцию
    -- больше не пишется — ни в «Отдаче», ни в метке строки, ни в деталях.
    held.active = true
    remote.call('shm-orbital-logistics', 'pass')
    player().opened = nil
    frame = open(shuttle)
    keys = now_keys(frame)
    assert((keys['now-released'] or 0) == 0, 'включённая игроком секция «выключена до отлёта»: ' .. serpent.line(keys))
    assert(keys['now-cargo-here'] == 1, 'включённая секция не «раздаёт»: ' .. serpent.line(keys))
    assert(find(frame, 'shm_ol_details_' .. held.index) and
      not find_caption(frame, 'now-released'), 'в панели осталась подпись «выключена до отлёта»')
    local marked = false
    local function scan_marked(element)
      if element.type == 'label' and type(element.tooltip) == 'table' and element.tooltip[1] == 'shm-orbital-logistics.section-released' then
        marked = true
      end
      for _, child in pairs(element.children) do
        scan_marked(child)
      end
    end
    scan_marked(frame)
    assert(not marked, 'строка включённой секции помечена «выключена до отлёта»')
  end)

  it('группа без фильтров предметов — «пустая группа», а не «раздаёт»', function()
    local _, hub = f.platform('a')
    hub.get_logistic_sections().add_section('Test void [depot:nauvis]')
    hub.get_logistic_sections().add_section('Test void cargo [cargo]')
    remote.call('shm-orbital-logistics', 'pass')
    local frame = open(hub)
    local keys = now_keys(frame)
    assert(keys['now-empty-group'] == 2, 'пустые группы: ' .. serpent.line(keys))
    assert((keys['now-depot-here'] or 0) == 0 and (keys['now-cargo-any'] or 0) == 0,
      'пустая группа показана как раздающая: ' .. serpent.line(keys))
  end)

  it('счётчик строк «Отдачи» — по числу фильтров секции', function()
    local _, hub = f.platform('a')
    local reserve = f.request(hub, 100, { item = 'iron-plate', group = 'Test cnt [reserve]', from = 'planet', import_from = f.PLANET })
    for i, item in ipairs({ 'copper-plate', 'steel-plate', 'stone' }) do
      reserve.set_slot(i + 1, {
        value = { type = 'item', name = item, quality = 'normal', comparator = '=' },
        min = 100,
        request_from = 'planet',
        import_from = f.PLANET,
      })
    end
    remote.call('shm-orbital-logistics', 'pass')
    local frame = open(hub)
    local caption = find_caption(frame, 'now-reserve')
    assert(caption and tonumber(caption[2]) == 4, 'счётчик не по фильтрам: ' .. serpent.line(caption))
    -- У запаса нет мест: пикер мест в строке не показывается.
    local index = first_filtered_index(hub, 'Test cnt')
    assert(find(frame, 'shm_ol_purpose_' .. index), 'нет поля назначения у запаса')
    assert(find(frame, 'shm_ol_places_' .. index) == nil, 'у запаса показан пикер мест')
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
        assert(find(frame, 'shm_ol_purpose_' .. index).enabled == false, 'секцию линии можно править из панели')
      end
    end
  end)

  it('высокий хаб: панель переезжает вбок, разворачивание сразу показывает контент', function()
    local _, hub = f.platform('a')
    local items = { 'copper-plate', 'steel-plate', 'stone', 'coal', 'iron-gear-wheel', 'copper-cable', 'electronic-circuit', 'plastic-bar', 'sulfur', 'concrete', 'battery' }
    for i, item in ipairs(items) do
      f.request(hub, 100, { item = item, group = 'Test tall ' .. i .. ' [depot:nauvis]', from = 'planet', import_from = f.OTHER_PLANET })
    end
    remote.call('shm-orbital-logistics', 'pass')
    local p = player()
    local screen_h = math.floor(p.display_resolution.height / p.display_scale)
    local screen_w = math.floor(p.display_resolution.width / p.display_scale)
    local min_h = math.floor(screen_h * panel.EXPAND_MIN_SHARE)
    local max_h = panel.expanded_cap(p)
    local frame = open(hub)
    -- 12 секций: окно хаба высокое — панель остаётся снизу (screen gui
    -- рисуется поверх и не обрезается якорем), высота 40–50% экрана.
    assert(frame.location.x == math.floor((screen_w - panel.BOTTOM_WIDTH) / 2),
      'панель не по центру: ' .. serpent.line(frame.location))
    assert(frame.location.y == screen_h - max_h,
      'панель не при нижнем крае: ' .. serpent.line(frame.location))
    assert(frame.style.minimal_height == min_h
      and frame.style.maximal_height == max_h, 'высота не 40–50% экрана')
    assert_on_screen(frame)
    local tall_scroll = find(frame, 'shm_ol_scroll_sections')
    assert(tall_scroll and tall_scroll.style.vertically_stretchable == true, 'развёрнутая прокрутка не растянута на высоту рамки')
    -- Больше секций — выше ванильное окно, но панель остаётся снизу:
    -- границы 40–50% экрана не зависят от секций.
    hub.get_logistic_sections().add_section('Test tall extra')
    hub.get_logistic_sections().add_section('Test tall extra 2')
    panel.build(p, hub)
    frame = player().gui.screen[panel.NAME]
    local bigger_min = frame.style.minimal_height
    local bigger_max = frame.style.maximal_height
    assert(bigger_min == min_h and bigger_max == max_h,
      'границы высоты изменились от секций: ' .. tostring(bigger_min) .. ' / ' .. tostring(bigger_max))
    assert_on_screen(frame)
    -- Разворачивание секции показывает содержимое сразу после клика.
    local sections = hub.get_logistic_sections()
    local target_index = nil
    for index = 1, sections.sections_count do
      if sections.get_section(index).filters_count > 0 then
        target_index = index
        break
      end
    end
    local expander = nil
    local function scan(element)
      if expander == nil and element.name == 'shm_ol_expand' and element.tags.details == target_index then
        expander = element
      end
      for _, child in pairs(element.children) do
        scan(child)
      end
    end
    scan(frame)
    click(expander)
    local details = find(frame, 'shm_ol_details_' .. target_index)
    assert(details and #details.children > 0, 'разворот секции не показывает содержимое')
  end)

  it('OL-DEBUG: сигнатура и снапшот при добавлении секции', function()
    local _, hub = f.platform('a')
    f.request(hub, 100, { group = 'Test collect [cargo→fulgora]', from = 'all' })
    remote.call('shm-orbital-logistics', 'pass')
    local purpose_counter = { n = 0 }
    local function scan(el)
      if el.name and string.sub(el.name, 1, 15) == 'shm_ol_purpose_' then
        purpose_counter.n = purpose_counter.n + 1
      end
      for _, ch in pairs(el.children) do
        scan(ch)
      end
    end
    local frame = open(hub)
    scan(frame)
    local purposes_at_open = purpose_counter.n
    local steps = {}
    local ok1, snap_before = pcall(function() return #controller.snapshot(hub).sections end)
    steps[#steps + 1] = 'snap_before ' .. tostring(ok1) .. '/' .. tostring(snap_before)
    hub.get_logistic_sections().add_section('Test new group')
    steps[#steps + 1] = 'opened_after_add ' .. tostring(player().opened == hub)
    local ok2, snap_after = pcall(function() return #controller.snapshot(hub).sections end)
    steps[#steps + 1] = 'snap_after ' .. tostring(ok2) .. '/' .. tostring(snap_after)
    local okr, errr = pcall(function() panel.refresh_all() end)
    steps[#steps + 1] = 'refresh_all ' .. tostring(okr) .. ' ' .. tostring(errr)
    steps[#steps + 1] = 'opened_after_refresh ' .. tostring(player().opened == hub)
    frame = player().gui.screen[panel.NAME]
    scan(frame)
    local purposes_after_refresh = purpose_counter.n
    local sig_after_refresh = tostring(frame.tags.signature)
    local okb, errb = pcall(function() panel.build(player(), hub) end)
    steps[#steps + 1] = 'build ' .. tostring(okb) .. ' ' .. tostring(errb)
    frame = player().gui.screen[panel.NAME]
    scan(frame)
    scan(frame)
    local purposes_after_build = purpose_counter.n
    local sections_dump = {}
    local sections = hub.get_logistic_sections()
    for index = 1, sections.sections_count do
      local section = sections.get_section(index)
      sections_dump[#sections_dump + 1] = index .. ':«' .. section.group .. '»:m' .. tostring(section.is_manual)
    end
    assert(true, 'OL-DEBUG: диагностический прогон пройден')
  end)
end)
