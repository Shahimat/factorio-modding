-- Окно обзора платформ, окно линий снабжения. Нужен живой игрок, поэтому
-- только в прогоне с графикой: тег `gui`,
-- `npm run test:ingame:gui -w shm-orbital-logistics`. Нажатия вызываются
-- обработчиками напрямую: поднять встроенное событие GUI скрипт не может.

local f = require('tests.ingame.fixture')
local overview = require('runtime.overview_gui')
local lines_gui = require('runtime.lines_gui')
local lines = require('runtime.lines')
local picker = require('runtime.places_picker')
local controller = require('runtime.controller')
local mod_gui = require('mod-gui')
local demo_commands = require('tests.demo.commands')

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
  if overview.on_click(event) then
    return
  end
  if picker.on_click(event) then
    return
  end
  lines_gui.on_click(event)
end

--- Окно обзора с карточками живых платформ.
local function window()
  return player().gui.screen[overview.NAME]
end

local function open_window()
  local frame = overview.open(player())
  assert(frame, 'окно обзора не открылось')
  return frame
end

--- Карточка платформы в окне обзора.
local function card_of(platform)
  return find(window(), 'shm_ol_card_' .. platform.index)
end

--- Развёрнутая карточка: открыть окно при необходимости и развернуть
--- карточку платформы, если ещё свёрнута.
local function open_card(platform)
  local frame = window() or open_window()
  local card = card_of(platform)
  assert(card, 'карточки платформы нет в окне')
  if find(card, 'shm_ol_content') == nil then
    click(find(card, 'shm_ol_card_toggle'))
    card = card_of(platform)
    assert(find(card, 'shm_ol_content'), 'карточка не развернулась')
  end
  return card
end

--- Добавить место в выбор строки секции: как выбор в окне игры у кнопки «+».
--- Места строк секций применяются сразу (overview.on_elem_changed).
local function pick(card, name, planet)
  local add = find(card, name .. '__add')
  assert(add, 'нет кнопки «+» в ' .. name)
  add.elem_value = planet
  local event = { element = add, player_index = player().index }
  assert(overview.on_elem_changed(event), 'выбор не обработан')
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

--- Ключи локали строк «Отдача на этой орбите»: { [ключ] = число строк }.
local function now_keys(card)
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
  scan(find(card, 'shm_ol_now'))
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

--- Кнопки мест маршрута и стрелки между ними из потока маршрута карточки.
local function route_parts(card)
  local route = find(card, 'shm_ol_route')
  assert(route, 'потока маршрута нет в карточке')
  local planets = {}
  local arrows = {}
  local function scan(root)
    for _, child in ipairs(root.children) do
      if child.tags.route_stop then
        planets[#planets + 1] = child
      elseif child.tags.route_leg then
        arrows[#arrows + 1] = child
      end
      scan(child)
    end
  end
  scan(route)
  return planets, arrows
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
    -- Открытие платформы из вида персонажа входит в удалённый вид: выйти,
    -- чтобы следующие наблюдения начинались с обычного контроллера.
    if player().controller_type == defines.controllers.remote then
      player().exit_remote_view()
    end
    overview.close(player())
    lines_gui.close(player())
    -- Свёрнутость блоков — состояние игрока: сбросить, чтобы падение одного
    -- наблюдения не свернуло блоки в следующих.
    storage.panel_block_collapsed = {}
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

  it('кнопка окна есть в левом верхнем углу, клик открывает и закрывает окно', function()
    local button = mod_gui.get_button_flow(player())[overview.BUTTON]
    assert(button, 'кнопки окна нет в mod-gui')
    local frame = open_window()
    assert(frame.parent == player().gui.screen, 'окно не в screen gui')
    click(button)
    assert(window() == nil, 'клик по кнопке не закрыл открытое окно')
    click(button)
    assert(window(), 'клик по кнопке не открыл окно')
    click(find(window(), 'shm_ol_overview_close'))
    assert(window() == nil, 'крестик не закрыл окно')
  end)

  it('кнопка переносится в общую рамку, чинит старые размеры и не трогает соседей', function()
    local p = player()
    local flow = mod_gui.get_button_flow(p)
    local button = flow[overview.BUTTON]
    if button then button.destroy() end
    local neighbor = flow.add({ type = 'button', name = 'shm-test-neighbor', caption = 'neighbor' })
    local legacy = p.gui.top.add({ type = 'sprite-button', name = overview.BUTTON, style = 'slot_button' })
    overview.refresh_all()
    button = flow[overview.BUTTON]
    assert(not legacy.valid and p.gui.top[overview.BUTTON] == nil, 'старая отдельная кнопка осталась')
    assert(button and button.get_mod() == 'shm-orbital-logistics', 'нет собственной кнопки в общей рамке')
    button.style = 'slot_button'
    button.style.size = 12
    assert(overview.ensure_button(p) == button, 'исправление создало другую кнопку')
    assert(overview.ensure_button(p) == button, 'повторный вызов создал дубль')
    assert(button.style.name == 'shm_ol_mod_button', 'не тот стиль меню')
    assert(button.style.minimal_width == 37 and button.style.minimal_height == 37, 'размеры не как у Helmod')
    assert(button.style.top_padding == -2 and button.style.left_padding == -2, 'отступы уменьшают иконку')
    assert(button.sprite == 'shm-ol-gui-button', 'значок мода потерян')
    assert(button.tooltip[1] == 'shm-orbital-logistics.overview-open', 'подсказка потеряна')
    assert(neighbor.valid and neighbor.parent == flow, 'соседняя кнопка затронута')
    neighbor.destroy()
  end)

  it('обычный игрок не может удалить демо-сеть ни отдельной, ни общей командой', function()
    local p = player()
    storage.shm_demo_network = storage.shm_demo_network or {}
    local previous, admin = storage.shm_demo_network[p.force.index], p.admin
    local marker = { platforms = {}, groups = {}, cells = {}, pods = {}, rockets = {} }
    storage.shm_demo_network[p.force.index] = marker
    p.admin = false
    local ok, err = pcall(function()
      for _, parameter in ipairs({ 'network-clear', 'clear' }) do
        demo_commands.handle({ player_index = p.index, parameter = parameter, tick = game.tick })
        assert(storage.shm_demo_network[p.force.index] == marker, 'admin-защита обойдена через ' .. parameter)
      end
    end)
    p.admin = admin
    storage.shm_demo_network[p.force.index] = previous
    assert(ok, err)
  end)

  it('карточки по умолчанию свёрнуты, разворот показывает настройки, переоткрытие окна всё сворачивает', function()
    local platform, hub = f.platform('a')
    f.request(hub, 100, { group = 'Test fuel [reserve]', from = 'planet', import_from = f.PLANET })
    local frame = open_window()
    local card = card_of(platform)
    assert(card, 'карточки нет')
    assert(find(card, 'shm_ol_content') == nil, 'карточка развернулась сама')
    click(find(card, 'shm_ol_card_toggle'))
    card = card_of(platform)
    assert(find(card, 'shm_ol_block_sections'), 'нет блока секций')
    assert(find(card, 'shm_ol_block_now'), 'нет блока «Отдача»')
    assert(find(card, 'shm_ol_purpose_1_1') or find(card, 'shm_ol_expand'), 'нет строк секций')
    -- Сворачивание убирает контент.
    click(find(card, 'shm_ol_card_toggle'))
    card = card_of(platform)
    assert(find(card, 'shm_ol_content') == nil, 'карточка не свернулась')
    -- Переоткрытие окна: карточки снова свёрнуты.
    overview.close(player())
    frame = open_window()
    card = card_of(platform)
    assert(find(card, 'shm_ol_content') == nil, 'переоткрытое окно открыло карточку развёрнутой')
  end)

  it('раскрытие карточки сохраняет геометрию окна и не добавляет padding или горизонтальный scroll', function()
    local first, hub = f.platform('layout-first')
    f.request(hub, 100, { group = 'Test layout reserve [reserve]', from = 'planet', import_from = f.PLANET })
    f.request(hub, 2000, { group = 'Test layout export [depot:nauvis]', from = 'planet', import_from = f.PLANET })
    f.request(hub, 600, { item = 'holmium-plate', group = 'Test layout imports [depot:nauvis]', from = 'platforms', import_from = f.PLANET })
    for index = 2, 10 do f.platform('layout-' .. index) end
    local frame = open_window()
    local location
    local width, height = frame.style.minimal_width, frame.style.minimal_height

    local function check_scroll(element)
      if element.type == 'scroll-pane' then
        assert(element.style.name == 'naked_scroll_pane', 'при активации появляется внутренняя рамка: ' .. element.name)
        assert(element.horizontal_scroll_policy == 'never', 'горизонтальный overflow разрешён: ' .. element.name)
        assert(element.vertical_scroll_policy == 'auto-and-reserve-space', 'ширина меняется при появлении вертикального scroll: ' .. element.name)
        for _, side in ipairs({ 'top', 'right', 'bottom', 'left' }) do
          assert(element.style['extra_' .. side .. '_padding_when_activated'] == 0, 'scroll добавляет padding: ' .. element.name .. '/' .. side)
        end
      end
      for _, child in pairs(element.children) do check_scroll(child) end
    end

    local function check_geometry()
      assert(window() == frame and frame.location.x == location.x and frame.location.y == location.y, 'окно сдвинулось или перестроилось')
      assert(frame.style.minimal_width == width and frame.style.minimal_height == height, 'размеры окна изменились')
      check_scroll(frame)
    end

    local function screenshot(name, next_step)
      game.take_screenshot({ player = player(), show_gui = true, force_render = true, path = 'orbital-layout/' .. name .. '.png' })
      game.set_wait_for_screenshots_to_finish()
      after_ticks(1, next_step or function() end)
    end

    after_ticks(2, function()
      -- force_auto_center применяется движком при раскладке, не внутри open.
      location = frame.location
      screenshot('collapsed', function()
        click(find(card_of(first), 'shm_ol_card_toggle'))
        after_ticks(2, function()
          check_geometry()
          screenshot('expanded', function()
            local card = card_of(first)
            local sections = find(card, 'shm_ol_block_sections')
            local now = find(card, 'shm_ol_block_now')
            local section_width, now_width = sections.style.minimal_width, now.style.minimal_width
            click(details_toggle(card, first_filtered_index(hub)))
            overview.refresh_all()
            assert(sections.valid and now.valid and sections.style.minimal_width == section_width and now.style.minimal_width == now_width,
              'раскрытие деталей или обновление сдвинуло колонки')
            local details = details_toggle(card, first_filtered_index(hub))
            assert(details.tags.expanded, 'детали не раскрылись')
            click(block_toggle(card, 'now'))
            assert(sections.valid and now.valid and details.valid and details.tags.expanded, 'переключение соседнего блока пересоздало поля или сбросило детали')
            click(find(now, 'shm_ol_block_summary'))
            assert(sections.valid and now.valid and details.valid and details.tags.expanded, 'разворот соседнего блока сбросил детали')
            check_geometry()
            click(find(card_of(first), 'shm_ol_card_toggle'))
            after_ticks(2, function()
              check_geometry()
              local state = frame.tags
              state.layout_version = nil
              frame.tags = state
              local scroll = find(frame, 'shm_ol_overview_scroll')
              scroll.horizontal_scroll_policy = 'auto'
              scroll.vertical_scroll_policy = 'auto'
              scroll.style.extra_padding_when_activated = 4
              overview.refresh_all()
              check_geometry()
              screenshot('collapsed-again')
            end)
          end)
        end)
      end)
    end)
  end)

  it('клик по имени карточки открывает окно хаба платформы', function()
    local platform, hub = f.platform('a')
    open_window()
    local card = card_of(platform)
    click(find(card, 'shm_ol_card_open'))
    assert(player().opened == hub, 'имя карточки не открыло окно хаба')
    player().opened = nil
    click(find(card_of(platform), 'shm_ol_card_icon'))
    assert(player().opened == hub, 'значок карточки не открыл окно хаба')
    player().opened = nil
  end)

  it('узкие колонки переносят выбор мест и ограничивают длинные подписи своей шириной', function()
    local platform, hub = f.platform('layout-widths')
    f.request(hub, 2000, {
      group = 'Test layout long depot name [depot:nauvis,vulcanus,fulgora,gleba,aquilo]',
      from = 'platforms', import_from = f.PLANET,
    })
    local frame = open_window()
    local widths, index = { 560, 760, 1200 }, 0
    local function next_width()
      index = index + 1
      local width = widths[index]
      if not width then return end
      frame.style.width = width
      frame.force_auto_center()
      overview.fill_cards(player(), frame)
      local card = open_card(platform)
      local places = find(card, 'shm_ol_places_' .. platform.index .. '_' .. first_filtered_index(hub, 'Test layout'))
      assert(places and places.type == 'table' and #places.children == 6, 'выбор мест не перенёс все пять планет и «+»')
      local sections = find(card, 'shm_ol_block_sections')
      assert(places.style.maximal_width <= sections.style.maximal_width - 16, 'пикер шире колонки')
      local warnings = find(card, 'shm_ol_warnings')
      for _, label in pairs(warnings.children) do
        assert(label.style.maximal_width <= warnings.style.maximal_width, 'предупреждение шире колонки')
      end
      click(details_toggle(card, first_filtered_index(hub, 'Test layout')))
      after_ticks(2, function()
        game.take_screenshot({ player = player(), show_gui = true, force_render = true, path = 'orbital-layout/width-' .. width .. '.png' })
        game.set_wait_for_screenshots_to_finish()
        after_ticks(1, next_width)
      end)
    end
    next_width()
  end)

  it('строки исключений разного размера не складывают максимумы ширины из разных строк', function()
    local platform, hub = f.platform('layout-exceptions')
    f.request(hub, 100, { group = 'Test layout one [depot:nauvis]', from = 'planet', import_from = f.PLANET })
    local mixed = f.request(hub, 100, { item = 'copper-plate', group = 'Test layout many [depot:nauvis]', from = 'all', import_from = f.PLANET })
    for index, item in ipairs({ 'steel-plate', 'stone', 'coal' }) do
      mixed.set_slot(index + 1, { value = { type = 'item', name = item, quality = 'normal' }, min = 100, request_from = 'all', import_from = f.PLANET })
    end
    mixed.set_slot(5, { value = { type = 'item', name = 'sulfur', quality = 'normal' }, min = 100, request_from = 'planet', import_from = f.OTHER_PLANET })
    controller.pass()
    local frame = open_window()
    for _, width in ipairs({ 760, 1200 }) do
      frame.style.width = width
      overview.fill_cards(player(), frame)
      local card = open_card(platform)
      local now = find(card, 'shm_ol_now')
      local grid = find(now, 'shm_ol_exception_grid')
      assert(grid, 'исключения не созданы')
      local list = grid.parent.parent
      assert(#list.children == 4, 'нужны два разных типа исключений')
      local one, many = list.children[1], list.children[3]
      assert(#one.children[1].children ~= #many.children[1].children, 'строки должны содержать разное число иконок')
      assert(one.style.minimal_width == many.style.minimal_width, 'таблица получила разные бюджеты одной колонки')
      for index = 1, #list.children, 2 do
        local icons, status = list.children[index], list.children[index + 1]
        assert(icons.style.minimal_width + status.style.minimal_width + list.style.horizontal_spacing == now.style.minimal_width,
          'общая таблица исключений шире колонки')
      end
    end
  end)

  it('маршрут: полное расписание с повторами, замыкающая стрелка и одно текущее место без перестроения', function()
    local platform, hub = f.platform('a')
    local stops = { 'nauvis', 'vulcanus', 'nauvis', 'fulgora' }
    local records = {}
    for _, name in ipairs(stops) do records[#records + 1] = { station = name, wait_conditions = { { type = 'time', ticks = 60 } } } end
    platform.schedule = { current = 1, records = records }
    platform.paused = true
    open_window()
    local card = card_of(platform)
    local planets, arrows = route_parts(card)
    assert(#planets == #stops and #arrows == #stops, 'полный цикл расписания не собрался')
    assert(arrows[#stops].sprite == 'shm-ol-route-loop', 'нет замыкающей круговой стрелки')
    assert(arrows[#stops].style.minimal_width == arrows[1].style.minimal_width
      and arrows[#stops].style.stretch_image_to_widget_size and not arrows[#stops].resize_to_sprite,
      'видимый размер возврата снова уменьшен масштабом utility-спрайта')
    for current, name in ipairs(stops) do
      platform.space_location = name
      platform.schedule = { current = current, records = records }
      platform.paused = true
      overview.refresh_all()
      local refreshed_planets, refreshed_arrows = route_parts(card)
      for index, expected in ipairs(stops) do
        assert(refreshed_planets[index] == planets[index] and refreshed_arrows[index] == arrows[index], 'изменение подсветки пересоздало цепочку')
        assert(planets[index].sprite == 'space-location/' .. expected, 'маршрут сменил порядок')
        assert((planets[index].style.name == 'shm_ol_route_planet_active') == (index == current), 'выделено неверное посещение планеты')
        assert(not string.find(arrows[index].sprite, '-active', 1, true), 'на стоянке выделена стрелка')
      end
    end
    -- Платформа без расписания: цепочка из одной планеты — текущее место,
    -- в рамке (решение владельца: цепочка видна всегда).
    platform.schedule = nil
    overview.refresh_all()
    card = card_of(platform)
    local alone, no_arrows = route_parts(card)
    assert(#alone == 1 and #no_arrows == 0, 'без расписания маршрут не сжался до места')
    assert(alone[1].sprite == 'space-location/fulgora' and alone[1].style.name == 'shm_ol_route_planet_active', 'место без расписания не в рамке')
    assert(hub and hub.valid)
  end)

  it('маршрут: настоящие рейсы в обе стороны выделяют правильные стрелки и замыкание при повторных остановках', function()
    local platform = f.platform('route-flights')
    f.equip_shuttle(platform)
    local stops = { 'nauvis', 'vulcanus', 'nauvis', 'vulcanus' }
    local records = {}
    for _, name in ipairs(stops) do records[#records + 1] = { station = name, wait_conditions = { { type = 'time', ticks = 120 } } } end
    platform.schedule = { current = 2, records = records }
    platform.paused = true
    local frame = open_window()
    local card = card_of(platform)
    local planets, arrows = route_parts(card)
    local legs, visits, captures = {}, {}, {}
    local pending, last_leg = false, nil
    local expected_leg = { [1] = 4, [2] = 1, [3] = 2, [4] = 3 }
    after_ticks(2, function() platform.paused = false end)
    f.watch(15000, function()
      if pending then return false end
      for _, asteroid in pairs(platform.surface.find_entities_filtered({ type = 'asteroid' })) do asteroid.destroy() end
      local location, schedule = platform.space_location, platform.schedule
      overview.refresh_all()
      local actual_planets, actual_arrows = route_parts(card)
      for index, name in ipairs(stops) do
        assert(actual_planets[index] == planets[index] and actual_arrows[index] == arrows[index], 'рейс пересоздал элементы маршрута')
        assert(planets[index].sprite == 'space-location/' .. name, 'рейс переставил остановки')
      end
      local key
      if location then
        -- Ожидание — из известной последовательности реальных рейсов,
        -- не из production tags.active_stop, который сам проверяется.
        local active = last_leg and (last_leg % #stops + 1) or 1
        assert(stops[active] == location.name, 'платформа прибыла не на ожидаемую планету')
        for index, planet in ipairs(planets) do
          assert((planet.style.name == 'shm_ol_route_planet_active') == (index == active), 'неверно выделено повторное посещение планеты')
        end
        visits[active] = true
        key = 'stop-' .. active
        for _, arrow in ipairs(arrows) do assert(not string.find(arrow.sprite, '-active', 1, true), 'на стоянке горит стрелка') end
      else
        local leg = expected_leg[schedule.current]
        assert(leg, 'неизвестное назначение в пути')
        legs[leg], last_leg = true, leg
        key = 'leg-' .. leg
        for index, arrow in ipairs(arrows) do
          assert((string.find(arrow.sprite, '-active', 1, true) ~= nil) == (index == leg), 'в пути выделено неверное плечо')
          assert(planets[index].style.name == 'slot_button', 'в пути выделена планета')
        end
      end
      if not captures[key] then
        captures[key] = true
        log('[OL-ROUTE-PROOF] ' .. helpers.table_to_json({ key = key, current = schedule.current,
          location = location and location.name, last = platform.last_visited_space_location and platform.last_visited_space_location.name,
          connection = platform.space_connection and platform.space_connection.name, state = platform.state, distance = platform.distance }))
        -- На время снимка останавливаем физическое движение, не вызывая GUI-обработчик.
        pending = true
        platform.paused = true
        if not location then platform.speed = 0 end
        after_ticks(2, function()
          game.take_screenshot({ player = player(), show_gui = true, force_render = true, path = 'orbital-route/' .. key .. '.png' })
          game.set_wait_for_screenshots_to_finish()
          after_ticks(1, function() pending = false; platform.paused = false end)
        end)
        return false
      end
      if not location then platform.speed = 100 end
      return last_leg == 4 and location and location.name == 'nauvis'
    end, function(_, reached)
      assert(reached, 'не дождались замыкания настоящего цикла')
      for index = 1, 4 do assert(legs[index] and visits[index], 'не пройдены все повторные остановки и плечи') end
      assert(frame == window() and frame.style.minimal_width == frame.style.maximal_width, 'маршрут изменил окно')
    end)
  end)

  it('маршрут: короткая стоянка не теряет историю между секундными обновлениями', function()
    local platform = f.platform('route-short-stop')
    f.equip_shuttle(platform)
    platform.schedule = { current = 2, records = {
      { station = 'nauvis', wait_conditions = { { type = 'time', ticks = 1 } } },
      { station = 'vulcanus', wait_conditions = { { type = 'time', ticks = 1 } } },
    } }
    platform.paused = true
    open_window()
    local card = card_of(platform)
    local planets, arrows = route_parts(card)
    local route = find(card, 'shm_ol_route')
    local fast_tick
    -- Согласуем прилёт с фазой 60-тактового обновления: быстро пролететь
    -- остаток прямого плеча сразу после refresh. Стоянка и начало возврата
    -- пройдут до следующего refresh, history должна прийти от реальных событий.
    platform.paused = false
    f.watch(5000, function()
      for _, asteroid in pairs(platform.surface.find_entities_filtered({ type = 'asteroid' })) do asteroid.destroy() end
      local location, schedule = platform.space_location, platform.schedule
      if not location and schedule.current == 2 then
        if platform.distance < 0.9 or fast_tick then
          platform.speed = 100
        elseif game.tick % 60 == 1 then
          fast_tick = game.tick
          platform.speed = 100
        else
          platform.speed = 0
        end
      elseif not location and schedule.current == 1 then
        assert(fast_tick and math.floor(game.tick / 60) == math.floor(fast_tick / 60), 'стоянка не поместилась между refresh')
        assert(platform.last_visited_space_location.name == 'vulcanus', 'обратный рейс не из Вулкана')
        assert(route.tags.departure == 2, 'короткая стоянка оставила старый departure')
        assert(arrows[2].valid and arrows[2].sprite == 'shm-ol-route-loop-active', 'замыкающая стрелка не обновилась на событии')
        assert(planets[1].style.name == 'slot_button' and planets[2].style.name == 'slot_button', 'после отлёта осталась выделена планета')
        return true
      end
      return false
    end, function(_, reached)
      assert(reached, 'не проверен короткий заход между секундными обновлениями: ' .. helpers.table_to_json({
        state = platform.state, current = platform.schedule.current, distance = platform.distance,
        location = platform.space_location and platform.space_location.name, fast_tick = fast_tick,
      }))
    end)
  end)

  it('маршрут: ручной пропуск остановки не подсвечивает несуществующий перегон', function()
    local platform = f.platform('route-skip')
    f.equip_shuttle(platform)
    platform.schedule = { current = 1, records = {
      { station = 'nauvis', wait_conditions = { { type = 'time', ticks = 120 } } },
      { station = 'vulcanus', wait_conditions = { { type = 'time', ticks = 120 } } },
      { station = 'fulgora', wait_conditions = { { type = 'time', ticks = 120 } } },
    } }
    platform.paused = true
    open_window()
    platform.get_schedule().go_to_station(3)
    f.watch(1500, function() return platform.space_location == nil end, function(_, reached)
      assert(reached, 'ручной рейс не начался')
      overview.refresh_all()
      local planets, arrows = route_parts(card_of(platform))
      for index, arrow in ipairs(arrows) do
        assert(not string.find(arrow.sprite, '-active', 1, true), 'пропущенная остановка показана источником рейса')
        assert(planets[index].style.name == 'slot_button', 'в пути выделена планета')
      end
    end)
  end)

  it('маршрут: штатный перелёт через промежуточную планету сохраняет активное плечо', function()
    local platform = f.platform('route-via')
    f.equip_shuttle(platform)
    platform.schedule = { current = 2, records = {
      { station = 'nauvis', wait_conditions = { { type = 'time', ticks = 120 } } },
      { station = 'aquilo', wait_conditions = { { type = 'time', ticks = 120 } } },
    } }
    platform.paused = true
    open_window()
    local planets, arrows = route_parts(card_of(platform))
    local intermediate = false
    platform.paused = false
    f.watch(15000, function()
      for _, asteroid in pairs(platform.surface.find_entities_filtered({ type = 'asteroid' })) do asteroid.destroy() end
      local location = platform.space_location
      overview.refresh_all()
      if not location then
        local last = platform.last_visited_space_location
        if last and last.name ~= 'nauvis' then intermediate = true end
        assert(arrows[1].valid and arrows[1].sprite == 'shm-ol-route-arrow-active', 'промежуточная связь погасила штатное плечо')
        assert(planets[1].style.name == 'slot_button' and planets[2].style.name == 'slot_button', 'в пути выделена планета')
        platform.speed = 100
      end
      return location and location.name == 'aquilo'
    end, function(_, reached)
      assert(reached and intermediate, 'не пройдено многозвенное плечо до Аквило')
    end)
  end)

  it('маршрут: длинное расписание переносится в заголовке узкой карточки без потери остановок', function()
    local platform = f.platform('route-wrap')
    local records = {}
    for _ = 1, 4 do
      for _, name in ipairs({ 'nauvis', 'vulcanus', 'fulgora', 'gleba', 'aquilo' }) do
        records[#records + 1] = { station = name, wait_conditions = { { type = 'time', ticks = 60 } } }
      end
    end
    platform.schedule = { current = 1, records = records }
    platform.paused = true
    local frame = open_window()
    frame.style.width = 560
    overview.fill_cards(player(), frame)
    local planets, arrows = route_parts(card_of(platform))
    assert(#planets == 20 and #arrows == 20, 'длинное расписание обрезано')
    local route = find(card_of(platform), 'shm_ol_route')
    local grid = route.children[1]
    assert(grid.column_count == 3, 'узкий маршрут не перенёс остановки')
    assert(grid.children[1].style.minimal_width * grid.column_count + grid.style.horizontal_spacing * (grid.column_count - 1) <= route.style.minimal_width,
      'маршрут шире своего остатка заголовка')
  end)

  it('карточка ставит метку секции без группы и с группой', function()
    local platform, hub = f.platform('a')
    f.request(hub, 300, { from = 'planet', import_from = f.PLANET })
    f.request(hub, 100, { group = 'Test plates', from = 'planet', import_from = f.PLANET })
    local card = open_card(platform)
    local sections = hub.get_logistic_sections()
    local plain_index, grouped_index
    for index = 1, sections.sections_count do
      local section = sections.get_section(index)
      if section.filters_count > 0 then
        if section.group == '' then plain_index = index else grouped_index = index end
      end
    end
    local plat = platform.index

    local purpose = find(card, 'shm_ol_purpose_' .. plat .. '_' .. plain_index)
    purpose.selected_index = 2
    assert(overview.on_selection({ element = purpose, player_index = player().index }), 'выбор не обработан')
    card = open_card(platform)
    local group = sections.get_section(plain_index).group
    assert(string.find(group, '[reserve]', 1, true) and string.find(group, 'shm-test-a', 1, true), 'метка без группы: ' .. group)

    find(card, 'shm_ol_purpose_' .. plat .. '_' .. grouped_index).selected_index = 4
    pick(card_of(platform), 'shm_ol_places_' .. plat .. '_' .. grouped_index, 'nauvis')
    assert(sections.get_section(grouped_index).group == 'Test plates [depot:nauvis]', sections.get_section(grouped_index).group)

    card = open_card(platform)
    local purpose_reset = find(card, 'shm_ol_purpose_' .. plat .. '_' .. grouped_index)
    purpose_reset.selected_index = 1
    assert(overview.on_selection({ element = purpose_reset, player_index = player().index }), 'выбор не обработан')
    assert(sections.get_section(grouped_index).group == 'Test plates', 'метка не снята')
  end)

  it('снятие метки с имени-«только метка» даёт fallback, а «Груз» без мест имя не меняет', function()
    local platform, hub = f.platform('a')
    f.request(hub, 300, { group = '[reserve]', from = 'planet', import_from = f.PLANET })
    f.request(hub, 100, { group = 'Test cargo', from = 'planet', import_from = f.PLANET })
    f.request(hub, 50, { group = 'Test cargo [cargo]', from = 'planet', import_from = f.PLANET })
    local card = open_card(platform)
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
    local plat = platform.index

    local purpose = find(card, 'shm_ol_purpose_' .. plat .. '_' .. tag_only)
    purpose.selected_index = 1
    assert(overview.on_selection({ element = purpose, player_index = player().index }), 'выбор не обработан')
    card = open_card(platform)
    local renamed = sections.get_section(tag_only).group
    -- Fallback: имя платформы и номер секции, метки не осталось.
    assert(string.find(renamed, '^shm%-test%-a%-%d+ #%d+$') ~= nil, 'нет fallback-имени: ' .. renamed)

    find(card, 'shm_ol_purpose_' .. plat .. '_' .. plain).selected_index = 3
    assert(overview.on_selection({ element = find(card_of(platform), 'shm_ol_purpose_' .. plat .. '_' .. plain), player_index = player().index }), 'выбор не обработан')
    assert(sections.get_section(plain).group == 'Test cargo', '[cargo] дописан: ' .. sections.get_section(plain).group)

    card = open_card(platform)
    find(card, 'shm_ol_purpose_' .. plat .. '_' .. pretagged).selected_index = 3
    assert(overview.on_selection({ element = find(card_of(platform), 'shm_ol_purpose_' .. plat .. '_' .. pretagged), player_index = player().index }), 'выбор не обработан')
    assert(sections.get_section(pretagged).group == 'Test cargo [cargo]',
      'имя с [cargo] изменилось: ' .. sections.get_section(pretagged).group)
  end)

  it('блоки внутри карточки сворачиваются по отдельности: итог по реальному содержимому, состояние на игрока', function()
    local platform, hub = f.platform('a')
    f.request(hub, 100, { group = 'Test fuel [reserve]', from = 'planet', import_from = f.PLANET })
    local depot = f.request(hub, 100, { item = 'iron-plate', group = 'Test depot [depot:nauvis]', from = 'platforms' })
    depot.set_slot(2, {
      value = { type = 'item', name = 'copper-plate', quality = 'normal', comparator = '=' },
      min = 100,
      request_from = 'planet',
      import_from = f.OTHER_PLANET,
    })
    local card = open_card(platform)
    assert(find(card, 'shm_ol_now'), '«Отдача» не развёрнута')
    assert(find(card, 'shm_ol_block_sections'), '«Группы» не развёрнуты')

    -- Треугольник в заголовке «Отдачи» сворачивает только её.
    click(block_toggle(card, 'now'))
    card = open_card(platform)
    assert(find(card, 'shm_ol_now') == nil, '«Отдача» не свернулась')
    local summary = find(card, 'shm_ol_block_summary')
    assert(summary and summary.tags.block == 'now', 'нет строки-итога')
    -- Итог — по реальному содержимому: 2 группы, 1 исключение («Платформы»).
    assert(type(summary.caption) == 'table'
      and summary.caption[1] == 'shm-orbital-logistics.collapsed-now'
      and tonumber(summary.caption[2]) == 2 and tonumber(summary.caption[3]) == 1,
      'итог «Отдачи» не по содержимому: ' .. serpent.line(summary.caption))
    assert(find(card, 'shm_ol_block_sections'), 'сворачивание «Отдачи» задело «Группы»')

    -- Клик по строке-итогу разворачивает обратно.
    click(find(card, 'shm_ol_block_summary'))
    card = open_card(platform)
    assert(find(card, 'shm_ol_now'), 'клик по итогу не развернул «Отдачу»')

    -- Свернуть «Группы»: блоки независимы. Итог — по строкам секций.
    click(block_toggle(card, 'sections'))
    card = open_card(platform)
    assert(find(card, 'shm_ol_block_sections') and find(card, 'shm_ol_now'), 'свернулись не те блоки')
    local sections_summary = find(card, 'shm_ol_block_summary')
    assert(sections_summary and sections_summary.tags.block == 'sections', 'итог «Групп» не появился')

    -- Состояние блоков — на игрока: переоткрытие окна сохраняет свёрнутые
    -- блоки — «Группы» остались свёрнутыми, «Отдача» осталась развёрнутой.
    overview.close(player())
    card = open_card(platform)
    assert(find(card, 'shm_ol_now'), '«Отдача» изменилась при переоткрытии окна')
    assert(find(card, 'shm_ol_expand') == nil, '«Группы» развернулись при переоткрытии окна')
    -- И развернуть «Группы» обратно.
    click(block_toggle(card_of(platform), 'sections'))
    assert(find(open_card(platform), 'shm_ol_expand'), '«Группы» не развернулись')
  end)

  it('«Отдача на этой орбите»: строка на группу с меткой, без строк для групп без метки, предупреждение про флаг', function()
    local platform, hub = f.platform('a')
    hub.insert({ name = f.ITEM, count = 50 })
    f.request(hub, 100, { group = 'Test fuel [reserve]', from = 'planet', import_from = f.PLANET })
    -- Склад с импортом с другой планеты: источник не задевает ловушки,
    -- о которых предупреждает карточка (см. тест ниже).
    f.request(hub, 100, { item = 'copper-plate', group = 'Test depot [depot:nauvis]', from = 'planet', import_from = f.OTHER_PLANET })
    f.request(hub, 10, { item = 'steel-plate', group = 'Test plain', from = 'planet', import_from = f.PLANET })
    f.request(hub, 10, { item = 'stone', group = 'Test far [depot:vulcanus]', from = 'planet', import_from = f.PLANET })
    remote.call('shm-orbital-logistics', 'pass')
    local card = open_card(platform)
    assert(find(card, 'shm_ol_warning'), 'нет предупреждения про флаг')
    local keys = now_keys(card)
    assert(keys['now-reserve'] == 1, 'нет строки запаса: ' .. serpent.line(keys))
    assert(keys['now-depot-here'] == 1, 'нет строки склада на своей орбите: ' .. serpent.line(keys))
    assert(keys['now-depot-held'] == 1, 'нет строки склада вне орбиты: ' .. serpent.line(keys))
    local total = 0
    for _, count in pairs(keys) do
      total = total + count
    end
    assert(total == 3, 'лишние строки (группа без метки?): ' .. serpent.line(keys))
    hub.providing_to_other_platforms = true
    overview.refresh_all()
    card = open_card(platform)
    assert(not find(card, 'shm_ol_warning'), 'предупреждение при включённом флаге')
  end)

  it('«Отдача на этой орбите»: исключение — склад добирает привезённый груз', function()
    local shuttle = select(2, f.platform('s'))
    shuttle.insert({ name = 'holmium-plate', count = 200 })
    shuttle.providing_to_other_platforms = true
    f.request(shuttle, 200, { item = 'holmium-plate', group = 'Test holmium [cargo→nauvis]', from = 'planet', import_from = 'fulgora' })
    local depot_platform, depot = f.platform('d')
    f.request(depot, 100, { item = 'holmium-plate', group = 'Test holmium depot [depot:nauvis]', from = 'planet', import_from = f.PLANET })
    remote.call('shm-orbital-logistics', 'pass')
    local card = open_card(depot_platform)
    local keys = now_keys(card)
    assert(keys['now-ex-transit'] == 1, 'нет исключения транзита: ' .. serpent.line(keys))
    click(find(card_of(depot_platform), 'shm_ol_card_toggle'))
    card = open_card(shuttle)
    keys = now_keys(card)
    assert(keys['now-cargo-here'] == 1, 'груз на назначении не «отдаёт»: ' .. serpent.line(keys))
  end)

  it('детали предметов: склад на своей орбите отдаёт сверх запаса, запас держит', function()
    local platform, hub = f.platform('a')
    f.request(hub, 200, { group = 'Test det reserve [reserve]', from = 'planet', import_from = f.PLANET })
    f.request(hub, 100, { item = 'copper-plate', group = 'Test det depot [depot:nauvis]', from = 'planet', import_from = f.OTHER_PLANET })
    hub.insert({ name = f.ITEM, count = 500 })
    hub.insert({ name = 'copper-plate', count = 12000 })
    local copper_count = hub.get_inventory(defines.inventory.hub_main).get_item_count('copper-plate')
    remote.call('shm-orbital-logistics', 'pass')
    local card = open_card(platform)
    -- По умолчанию всё свёрнуто: строк на предметы ещё нет.
    assert(detail_keys(card)['details-amounts'] == nil, 'детали развернуты по умолчанию')

    -- Склад на своей орбите: фраза про цель и отдачу сверх запаса.
    local depot_index = first_filtered_index(hub, 'Test det depot')
    assert(depot_index, 'нет секции склада')
    click(details_toggle(card, depot_index))
    card = card_of(platform)
    local keys = detail_keys(card)
    assert(keys['details-depot-here'] == 1, 'нет фразы склада на орбите: ' .. serpent.line(keys))
    assert(keys['details-amounts'] == 1, 'нет чисел по предмету: ' .. serpent.line(keys))
    local phrase = find_caption(card, 'details-depot-here')
    assert(phrase and tonumber(phrase[2]) == 100, 'цель склада не во фразе: ' .. serpent.line(phrase))
    local amounts = find_caption(card, 'details-amounts')
    assert(amounts and tonumber(amounts[2]) == copper_count and tonumber(amounts[5]) == 100, 'числа предмета: ' .. serpent.line(amounts))
    assert(type(amounts[7]) == 'table' and amounts[7][1] == 'shm-orbital-logistics.details-yes', 'склад сверх цели должен отдаваться')

    -- Запас: держит, объяснение — остался запас.
    local reserve_index = first_filtered_index(hub, 'Test det reserve')
    click(details_toggle(card, reserve_index))
    card = card_of(platform)
    keys = detail_keys(card)
    assert(keys['details-reserve'] == 1, 'нет фразы запаса: ' .. serpent.line(keys))
    assert(keys['details-st-held-reserve'] == 1, 'запас не «стоит»: ' .. serpent.line(keys))

    -- Развёрнутость переживает обновление раз в секунду.
    overview.refresh_all()
    keys = detail_keys(card_of(platform))
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

    local card = open_card(at_dest)
    local index = first_filtered_index(at_dest, 'Test det cargo dest')
    click(details_toggle(card, index))
    card = card_of(at_dest)
    local keys = detail_keys(card)
    assert(keys['details-cargo-dest'] == 1, 'груз на назначении не «раздаётся»: ' .. serpent.line(keys))
    local phrase = find_caption(card, 'details-cargo-dest')
    assert(serpent.line(phrase):find('planet=vulcanus', 1, true), 'куда не ссылкой: ' .. serpent.line(phrase))
    assert(serpent.line(phrase):find('planet=fulgora', 1, true), 'откуда не ссылкой: ' .. serpent.line(phrase))
    local amounts = find_caption(card, 'details-amounts')
    assert(amounts and tonumber(amounts[4]) == 300, 'цель груза не в числах: ' .. serpent.line(amounts))
    assert(type(amounts[7]) == 'table' and amounts[7][1] == 'shm-orbital-logistics.details-yes', 'груз на назначении должен отдаваться')

    click(find(card_of(at_dest), 'shm_ol_card_toggle'))
    card = open_card(away)
    index = first_filtered_index(away, 'Test det cargo held')
    click(details_toggle(card, index))
    card = card_of(away)
    keys = detail_keys(card)
    assert(keys['details-cargo-held'] == 1, 'груз в пути не «держится»: ' .. serpent.line(keys))
    assert(keys['details-st-held-cargo'] == 1, 'нет причины «вне назначения»: ' .. serpent.line(keys))
  end)

  it('детали ванильного груза на орбите со складом: «везде, кроме откуда»', function()
    local depot_platform, depot = f.platform('d')
    f.request(depot, 100, { item = 'copper-plate', group = 'Test det depot d [depot:nauvis]', from = 'planet', import_from = f.OTHER_PLANET })
    local platform, hub = f.platform('v')
    hub.insert({ name = f.ITEM, count = 40 })
    f.request(hub, 100, { from = 'planet', import_from = 'fulgora' })
    remote.call('shm-orbital-logistics', 'pass')

    local card = open_card(platform)
    -- Свёрнуто: короткая строка про ванильный груз, чисел ещё нет.
    local keys = detail_keys(card)
    assert(keys['details-cargo-vanilla'] == 1, 'ванильный груз не описан свёрнуто: ' .. serpent.line(keys))
    assert(keys['details-amounts'] == nil, 'числа при свёрнутой строке')
    local summary = find_caption(card, 'details-cargo-vanilla')
    assert(serpent.line(summary):find('planet=fulgora', 1, true), 'откуда не ссылкой: ' .. serpent.line(summary))

    -- Развёрнуто: строка предмета с числами и статусом отдачи.
    local index = first_filtered_index(hub, nil)
    click(details_toggle(card, index))
    card = card_of(platform)
    keys = detail_keys(card)
    assert(keys['details-cargo-vanilla'] == 1, 'нет строки ванильного груза: ' .. serpent.line(keys))
    assert(keys['details-amounts'] == 1, 'нет чисел по предмету: ' .. serpent.line(keys))
    assert(keys['details-st-giving'] == 1, 'ванильный груз не «отдаётся»: ' .. serpent.line(keys))
    local amounts = find_caption(card, 'details-amounts')
    assert(amounts and tonumber(amounts[2]) == 40, 'в числах нет «есть»: ' .. serpent.line(amounts))
  end)

  it('выбранное назначение применяется сразу: в деталях фраза склада, предпросмотра нет', function()
    local platform, hub = f.platform('a')
    f.request(hub, 100, { group = 'Test det plain', from = 'planet', import_from = f.PLANET })
    -- Прогон чистит записи орбит разрушенных платформ прошлых наблюдений.
    remote.call('shm-orbital-logistics', 'pass')
    local card = open_card(platform)
    local index = first_filtered_index(hub, nil)
    overview.refresh_all()
    assert(detail_keys(card_of(platform))['details-preview'] == nil, 'предпросмотр без смены назначения')

    -- Выбран «Склад» на Вулкан: применяется сразу, в деталях фраза склада
    -- и место-ссылкой.
    find(card, 'shm_ol_purpose_' .. platform.index .. '_' .. index).selected_index = 4
    pick(card_of(platform), 'shm_ol_places_' .. platform.index .. '_' .. index, 'vulcanus')
    card = card_of(platform)
    click(details_toggle(card, index))
    card = card_of(platform)
    local keys = detail_keys(card)
    assert(keys['details-depot-away'] == 1, 'в деталях не фраза склада: ' .. serpent.line(keys))
    local away = find_caption(card, 'details-depot-away')
    assert(serpent.line(away):find('planet=vulcanus', 1, true), 'место в деталях не ссылкой')
    assert(keys['details-preview'] == nil, 'предпросмотр остался при авто-применении')
  end)

  it('предупреждения об источниках склада: «Платформы» не отдаёт, импорт с текущей планеты не сбрасывает', function()
    local give_platform, give_hub = f.platform('a')
    f.request(give_hub, 100, { group = 'Test depot [depot:nauvis]', from = 'platforms' })
    local drop_platform, drop_hub = f.platform('b')
    f.request(drop_hub, 100, { group = 'Test depot two [depot:nauvis]', from = 'planet', import_from = f.PLANET })
    remote.call('shm-orbital-logistics', 'pass')
    local card = open_card(give_platform)
    assert(find(card, 'shm_ol_warning_depot_source'), 'нет предупреждения про источник «Платформы»')
    assert(find(card, 'shm_ol_warning_depot_drop') == nil, 'предупреждение про сброс без импорта с текущей планеты')
    local keys = now_keys(card)
    -- Все предметы склада с источником «Платформы»: строка группы сама
    -- говорит «не сможет отдавать платформам», в исключениях повтора нет.
    assert(keys['now-depot-no-give'] == 1, 'нет строки «не сможет отдавать платформам»: ' .. serpent.line(keys))
    click(find(card_of(give_platform), 'shm_ol_card_toggle'))
    card = open_card(drop_platform)
    assert(find(card, 'shm_ol_warning_depot_drop'), 'нет предупреждения про сброс на текущую планету')
    assert(find(card, 'shm_ol_warning_depot_source') == nil, 'предупреждение про «Платформы» у источника «Планета»')
    keys = now_keys(card)
    assert(keys['now-depot-here'] == 1, 'склад с «Планетой» должен отдавать платформам: ' .. serpent.line(keys))
    assert(keys['now-depot-no-drop'] == 1, 'нет исключения «не сбросит на эту планету»: ' .. serpent.line(keys))
  end)

  it('«Отдача»: исключения агрегированы по типу состояния — строка на тип, сетка до 10 иконок и «+N ещё»', function()
    local platform, hub = f.platform('a')
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
    local card = open_card(platform)
    local keys = now_keys(card)
    assert(keys['now-reserve'] == 1 and keys['now-depot-here'] == 1, 'строк групп: ' .. serpent.line(keys))
    -- Стена из 15 строк исключений сжалась в две — по одной на тип.
    assert(keys['now-depot-no-give'] == 1, '«Платформы» не сведены в строку: ' .. serpent.line(keys))
    assert(keys['now-depot-no-drop'] == 1, 'сброс не сведён в строку: ' .. serpent.line(keys))
    -- Сетка первой строки: 10 иконок и «+2 ещё» с полным списком в тултипе.
    local more = find(card, 'shm_ol_exception_more')
    assert(more, 'нет подписи «+N ещё»')
    assert(type(more.tooltip) == 'table', 'полного списка предметов в тултипе нет')
    local grids = 0
    for _, child in ipairs(find(card, 'shm_ol_now').children) do
      if child.name == 'shm_ol_exception_grid' then
        grids = grids + 1
      end
    end
    assert(grids >= 1, 'нет сетки иконок исключений')
  end)

  it('линии: пустой блок — кнопка окна; подключение из карточки делает хаб участником', function()
    local platform, hub = f.platform('a')
    local card = open_card(platform)
    assert(find(card, 'shm_ol_open_lines'), 'нет кнопки линий')
    assert(find(card, 'shm_ol_header_lines') == nil, 'пустой блок линий получил заголовок')

    -- Появилась линия — блок полный: заголовок и подключение.
    lines_gui.open(player())
    local window = player().gui.screen[lines_gui.NAME]
    find(window, 'shm_ol_line_name').text = 'Test card line'
    click(find(window, 'shm_ol_line_create'))
    lines_gui.close(player())
    -- Создание линии в окне линий перестраивает блок «Линии» обновлением.
    overview.refresh_all()
    card = open_card(platform)
    assert(find(card, 'shm_ol_header_lines'), 'нет заголовка блока линий')
    assert(find(card, 'shm_ol_attach_line'), 'нет подключения линии')
    click(find(card, 'shm_ol_attach'))
    local member = lines.of_entity(player().force, hub)
    assert(#member == 1 and member[1].line.name == 'Test card line', 'хаб не подключился к линии')
    -- Кнопка подключения открыла окно линий на подключённой линии.
    assert(player().gui.screen[lines_gui.NAME], 'окно линий не открылось')
    lines_gui.close(player())
  end)

  it('окно линий подключает участников без панели: хаб из списка и площадку со скролла планет', function()
    local platform, hub = f.platform('a')
    local pad = f.pad()
    lines_gui.open(player())
    local window = player().gui.screen[lines_gui.NAME]
    find(window, 'shm_ol_line_name').text = 'Test attach line'
    click(find(window, 'shm_ol_line_create'))
    window = player().gui.screen[lines_gui.NAME]
    -- Кандидаты: хаб платформы и площадка. Подключаем первого в списке.
    local dropdown = find(window, 'shm_ol_attach_entity')
    assert(dropdown, 'нет строки подключения участников')
    assert(#dropdown.items >= 2, 'в списке подключения нет хаба и площадки')
    click(find(window, 'shm_ol_line_attach'))
    assert(#lines.of_entity(player().force, hub) == 1, 'хаб не подключился')
    -- Площадка: она единственный оставшийся кандидат.
    window = player().gui.screen[lines_gui.NAME]
    dropdown = find(window, 'shm_ol_attach_entity')
    assert(dropdown and #dropdown.items == 1, 'после подключения хаба в списке не только площадка')
    click(find(window, 'shm_ol_line_attach'))
    local members = lines.list(player().force)[1].participants
    assert(#members == 2, 'площадка не подключилась: ' .. tostring(#members))
    assert(members[2] and members[2].kind == 'pad', 'второй участник не площадка')
    assert(pad and pad.valid)
  end)

  it('окно обзора подхватывает новую группу секций после прохода контроллера', function()
    local platform, hub = f.platform('a', 'fulgora')
    f.request(hub, 5000, { group = 'Test collect [cargo→fulgora]', from = 'all' })
    remote.call('shm-orbital-logistics', 'pass')
    local card = open_card(platform)
    local marked = false
    local function scan(element)
      if element.type == 'label' and type(element.caption) == 'table' and element.tooltip then
        marked = marked or (type(element.tooltip) == 'table' and element.tooltip[1] == 'shm-orbital-logistics.section-released')
      end
      for _, child in pairs(element.children) do
        scan(child)
      end
    end
    scan(card)
    assert(marked, 'выключенная группа не помечена')
    hub.get_logistic_sections().add_section('Test new group')
    after_ticks(70, function()
      -- Продуктовое обещание: после прохода обновления новая группа есть
      -- в карточке. Обновляем явно — порядок обработчиков одного тика не
      -- гарантируется.
      overview.refresh_all()
      card = open_card(platform)
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
      assert(new_index and find(card, 'shm_ol_purpose_' .. platform.index .. '_' .. new_index),
        'новая группа не появилась в карточке: new_index ' .. tostring(new_index))
      player().force.delete_logistic_group('Test new group')
      player().force.delete_logistic_group('Test collect [cargo→fulgora]')
      assert(platform.valid)
    end)
  end)
end)
