-- Выбор мест без ввода имён и без ряда всех планет: мест у модов планет может
-- быть очень много. Множественный выбор — выбранные иконки (нажатие убирает)
-- и кнопка «+» со стандартным окном выбора игры с поиском. Одиночный — одна
-- такая кнопка, пустая значит «любое место». Выбор хранится в `tags`
-- контейнера и читается по «Применить».

local picker = {}

local function sorted(set)
  local names = {}
  for name in pairs(set or {}) do
    names[#names + 1] = name
  end
  table.sort(names)
  return names
end

local function render(grid)
  grid.clear()
  local opts = grid.tags
  if opts.single then
    local value = opts.selected[1]
    grid.add({
      type = 'choose-elem-button',
      name = grid.name .. '__choose',
      elem_type = 'space-location',
      ['space-location'] = value,
      enabled = opts.enabled,
      tooltip = opts.tooltip,
      tags = { picker_add = true },
    }).style.size = 28
    return
  end
  for _, name in ipairs(opts.selected) do
    local prototype = prototypes.space_location[name]
    local button = grid.add({
      type = 'sprite-button',
      name = grid.name .. '__' .. name,
      sprite = prototype and ('space-location/' .. name) or 'utility/questionmark',
      tooltip = { '', prototype and prototype.localised_name or name, '\n', { 'shm-orbital-logistics.picker-remove' } },
      enabled = opts.enabled,
      style = 'slot_sized_button',
      tags = { picker_remove = name },
    })
    button.style.size = 28
  end
  grid.add({
    type = 'choose-elem-button',
    name = grid.name .. '__add',
    elem_type = 'space-location',
    enabled = opts.enabled,
    tooltip = opts.tooltip,
    tags = { picker_add = true },
  }).style.size = 28
end

--- Выбор мест под именем `name`. `single` — не больше одного места.
function picker.add(parent, name, _, selected, opts)
  opts = opts or {}
  local flow = parent.add({
    type = 'flow',
    name = name,
    direction = 'horizontal',
    tags = {
      picker = true,
      single = opts.single == true,
      enabled = opts.enabled ~= false,
      tooltip = opts.tooltip,
      selected = sorted(selected),
    },
  })
  flow.style.horizontal_spacing = 0
  render(flow)
  return flow
end

--- Выбранные места множеством; nil, если ничего не выбрано.
function picker.read(flow)
  if not (flow and flow.valid and flow.tags.picker) then
    return nil
  end
  local list = flow.tags.selected
  if flow.tags.single then
    local button = flow.children[1]
    local value = button and button.elem_value
    list = value and { value } or {}
  end
  local set = nil
  for _, name in ipairs(list) do
    set = set or {}
    set[name] = true
  end
  return set
end

--- Множество мест строкой через запятую — как его понимают метки.
function picker.text(set)
  return table.concat(sorted(set), ',')
end

--- Строка через запятую в множество.
function picker.set(text)
  local set = nil
  for raw in string.gmatch(text or '', '[^,%s]+') do
    set = set or {}
    set[raw] = true
  end
  return set
end

local function update(flow, selected)
  local tags = flow.tags
  tags.selected = selected
  flow.tags = tags
  render(flow)
end

--- Нажатие на выбранное место — убрать его. Возвращает true, если нажатие его.
function picker.on_click(event)
  local element = event.element
  if not (element and element.valid and element.tags.picker_remove) then
    return false
  end
  local flow = element.parent
  local selected = {}
  for _, name in ipairs(flow.tags.selected) do
    if name ~= element.tags.picker_remove then
      selected[#selected + 1] = name
    end
  end
  update(flow, selected)
  return true
end

--- Место выбрано в окне игры. В множественном выборе — добавить и очистить
--- кнопку «+»; в одиночном значение остаётся в самой кнопке.
function picker.on_elem_changed(event)
  local element = event.element
  if not (element and element.valid and element.tags.picker_add) then
    return false
  end
  local flow = element.parent
  if flow.tags.single then
    return true
  end
  local value = element.elem_value
  if value then
    local set = {}
    for _, name in ipairs(flow.tags.selected) do
      set[name] = true
    end
    set[value] = true
    update(flow, sorted(set))
  end
  return true
end

return picker
