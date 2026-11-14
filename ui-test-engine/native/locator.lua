-- Адаптер native locator для sprite-button без caption. Не меняет исходник,
-- sprite, tooltip, enabled или размер кнопки; нулевой label не перехватывает ввод.
local locator = {}
local sequence = 0

function locator.prepare(element)
  assert(element and element.valid, "Target GUI element is missing")
  sequence = sequence + 1
  local caption = "·" .. sequence
  local probe = element.add{type = "label", caption = caption, ignored_by_interaction = true}
  probe.style.width = 0
  probe.style.height = 0
  probe.style.font_color = {r = 1, g = 1, b = 1, a = 0}
  probe.style.horizontally_squashable = true
  probe.style.left_margin = math.max(1, math.floor(element.style.minimal_width / 2) - 4)
  probe.style.top_margin = math.max(1, math.floor(element.style.minimal_height / 2) - 4)
  return {probe = probe, query = {type = "label", text = caption}, name = element.name, owner = element.get_mod()}
end

function locator.position(target)
  local position = game.simulation.get_widget_position(target.query)
  assert(position, "Native locator did not find target: " .. (target.name or "widget"))
  return position
end

function locator.clear(target)
  if target.probe and target.probe.valid then target.probe.destroy() end
end

return locator
