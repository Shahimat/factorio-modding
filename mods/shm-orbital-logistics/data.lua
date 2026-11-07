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

-- Рамка планеты, где платформа стоит сейчас: фон слота с оранжевой обводкой,
-- под иконкой места. Рисуется вместо штатного фона `slot_button`.
local function active_slot_sprite()
  return {
    type = 'sprite',
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
  default_sprite = active_slot_sprite(),
  hovered_sprite = active_slot_sprite(),
  clicked_sprite = active_slot_sprite(),
}
