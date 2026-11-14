-- «Советы и подсказки»: свой раздел с одной страницей — описание мода целиком
-- и картинка пути платформы от Наувиса до Вулкана. Открыта сразу.

data:extend({
  {
    type = 'tips-and-tricks-item-category',
    name = 'shm-orbital-logistics',
    order = 'z-[shm-orbital-logistics]',
  },
  {
    type = 'tips-and-tricks-item',
    name = 'shm-orbital-logistics',
    category = 'shm-orbital-logistics',
    order = 'a',
    is_title = true,
    starting_status = 'unlocked',
    image = '__shm-orbital-logistics__/graphics/tips-route.png',
  },
})

-- Спрайты окна обзора платформ: значок кнопки окна — картинка мода
-- (thumbnail), стрелки перегонов маршрута — обычная и активная, для
-- перегона, которым платформа летит сейчас.
local function mod_sprite(name, filename, width, height)
  return {
    type = 'sprite',
    name = name,
    filename = '__shm-orbital-logistics__/graphics/' .. filename,
    priority = 'extra-high-no-scale',
    width = width,
    height = height,
  }
end

data:extend({
  mod_sprite('shm-ol-gui-button', 'gui-button.png', 64, 64),
  mod_sprite('shm-ol-route-arrow', 'route-arrow.png', 20, 10),
  mod_sprite('shm-ol-route-arrow-active', 'route-arrow-active.png', 20, 10),
})

-- Замыкание расписания — круговая стрелка Wube, а не ещё одна планета.
-- Обычная и активная используют одну маску, поэтому меняется только цвет.
for _, active in ipairs({ false, true }) do
  local sprite = table.deepcopy(data.raw['utility-sprites'].default.reset_white)
  sprite.type = 'sprite'
  sprite.name = active and 'shm-ol-route-loop-active' or 'shm-ol-route-loop'
  sprite.scale = 1
  sprite.tint = active and { 1, 0.65, 0.3 } or { 0.72, 0.72, 0.72 }
  data:extend({ sprite })
end

-- Кнопка меню в общей рамке mod-gui, как у Helmod: те же размеры и
-- ванильные графические наборы, но собственный значок и никакой зависимости.
data.raw['gui-style'].default['shm_ol_mod_button'] = {
  type = 'button_style',
  parent = 'button',
  horizontal_align = 'center',
  default_graphical_set = { base = { position = { 0, 0 }, corner_size = 8 } },
  hovered_graphical_set = { base = { position = { 34, 17 }, corner_size = 8 } },
  clicked_graphical_set = { base = { position = { 51, 17 }, corner_size = 8 } },
  disabled_graphical_set = { base = { position = { 386, 17 }, corner_size = 8 } },
}

-- Рамка планеты, где платформа стоит сейчас: фон слота с оранжевой обводкой,
-- под иконкой места. Рисуется вместо штатного фона `slot_button`.
local function active_slot_sprite()
  return {
    filename = '__shm-orbital-logistics__/graphics/route-slot-active.png',
    priority = 'extra-high-no-scale',
    width = 32,
    height = 32,
    scale = 1,
  }
end

data.raw['gui-style'].default['shm_ol_route_planet_active'] = {
  type = 'button_style',
  parent = 'slot_button',
  default_graphical_set = { base = active_slot_sprite() },
  hovered_graphical_set = { base = active_slot_sprite() },
  clicked_graphical_set = { base = active_slot_sprite() },
}
