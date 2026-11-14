-- Реальный мод загружается отдельно. Его модули и обработчики здесь не require.
local scenario = {
  name = "orbital",
  capture = {before = 240, after = 540},
  result_at = 420
}
local platform_index
local negative
local header_position
local route_elements

local function find(root, name)
  if not (root and root.valid) then return nil end
  if root.name == name then return root end
  for _, child in pairs(root.children) do
    local found = find(child, name)
    if found then return found end
  end
end

local function card(player)
  return assert(find(player.gui.screen.shm_ol_overview, "shm_ol_card_" .. platform_index), "Platform card is missing")
end

local function toggle(player)
  return assert(find(card(player), "shm_ol_card_toggle"), "Card toggle is missing")
end

local function header_center()
  return assert(game.simulation.get_widget_position{type = "text-button", text = "UI collapse probe"}, "Platform name button is not rendered")
end

local function list_scroll(player)
  local parent = card(player).parent
  while parent and parent.type ~= "scroll-pane" do parent = parent.parent end
  return assert(parent, "Platform list scroll-pane is missing")
end

local function route_parts(player)
  local parts = {planets = {}, arrows = {}}
  local function walk(root)
    for _, child in ipairs(root.children) do
      if child.tags.route_stop then parts.planets[#parts.planets + 1] = child end
      if child.tags.route_leg then parts.arrows[#parts.arrows + 1] = child end
      walk(child)
    end
  end
  walk(assert(find(card(player), "shm_ol_route")))
  return parts
end

local function route_checks(player)
  local parts = route_parts(player)
  local sprites, styles, arrows, same = {}, {}, {}, true
  for index, planet in ipairs(parts.planets) do
    sprites[#sprites + 1] = planet.sprite
    styles[#styles + 1] = planet.style.name
    if planet ~= route_elements.planets[index] then same = false end
  end
  for index, arrow in ipairs(parts.arrows) do
    arrows[#arrows + 1] = arrow.sprite
    if arrow ~= route_elements.arrows[index] then same = false end
  end
  return {
    {name = "complete schedule stays in record order", expected = "space-location/nauvis,space-location/vulcanus,space-location/fulgora", actual = table.concat(sprites, ",")},
    {name = "schedule includes its closing circular arrow", expected = "shm-ol-route-arrow,shm-ol-route-arrow,shm-ol-route-loop", actual = table.concat(arrows, ",")},
    {name = "only the occupied planet is highlighted", expected = "shm_ol_route_planet_active,slot_button,slot_button", actual = table.concat(styles, ",")},
    {name = "native clicks and refresh preserve route elements", expected = true, actual = same}
  }
end

local function with_route_checks(checks, player)
  for _, check in ipairs(route_checks(player)) do checks[#checks + 1] = check end
  return checks
end

function scenario.setup(player, options)
  negative = options.negative
  local owner = remote.call("shm-orbital-ui-tests", "prepare_player", player.index)
  assert(owner == "shm-orbital-logistics", "Setup did not create the production GUI button")
  player.force.research_all_technologies()
  local platform = assert(player.force.create_space_platform{
    name = "UI collapse probe", planet = "nauvis", starter_pack = "space-platform-starter-pack"
  })
  platform.apply_starter_pack()
  platform.schedule = {current = 1, records = {
    {station = "nauvis", wait_conditions = {{type = "time", ticks = 600}}},
    {station = "vulcanus", wait_conditions = {{type = "time", ticks = 600}}},
    {station = "fulgora", wait_conditions = {{type = "time", ticks = 600}}}
  }}
  platform.paused = true
  platform_index = platform.index
  local hub = assert(platform.hub)
  hub.request_missing_construction_materials = false
  hub.providing_to_other_platforms = false
  local section = hub.get_logistic_sections().add_section("UI reserve [reserve]")
  section.set_slot(1, {
    value = {type = "item", name = "iron-plate", quality = "normal", comparator = "="},
    min = 100, request_from = "planet", import_from = "nauvis"
  })
  hub.insert{name = "iron-plate", count = 50}
  remote.call("shm-orbital-logistics", "pass")
end

scenario.actions = {
  {id = "open", locate_at = 30, click_at = 45, element = function(player)
    return assert(find(player.gui.top, "shm_ol_overview_button"), "Overview button is missing")
  end},
  {id = "expand", locate_at = 75, click_at = 90, element = function(player)
    header_position = header_center()
    route_elements = route_parts(player)
    return toggle(player)
  end},
  {id = "collapse", locate_at = 300, click_at = 330, element = function(player)
    local button = toggle(player)
    if negative then button.enabled = false end
    return button
  end}
}

function scenario.frame(player)
  local frame = assert(player.gui.screen.shm_ol_overview)
  local location = frame.location
  return {x = location.x, y = location.y, width = frame.style.minimal_width, height = frame.style.minimal_height}
end

function scenario.reference_title(player)
  local frame = assert(player.gui.screen.shm_ol_overview)
  local title = frame.children[1].children[1]
  assert(title.type == "label" and title.get_mod() == "shm-orbital-logistics", "Production title is missing")
  return {caption = title.caption, style = title.style.name}
end

function scenario.before(player)
  local item = card(player)
  local button = assert(find(player.gui.top, "shm_ol_overview_button"))
  local scroll = list_scroll(player)
  local position = header_center()
  return with_route_checks({
    {name = "overview button uses shared mod-gui frame", expected = "mod_gui_inner_frame", actual = button.parent.name},
    {name = "overview button style", expected = "shm_ol_mod_button", actual = button.style.name},
    {name = "overview button width", expected = 37, actual = button.style.minimal_width},
    {name = "overview button height", expected = 37, actual = button.style.minimal_height},
    {name = "legacy top-level button removed", expected = true, actual = player.gui.top.shm_ol_overview_button == nil},
    {name = "platform list has no activation frame", expected = "naked_scroll_pane", actual = scroll.style.name},
    {name = "platform list forbids horizontal scrolling", expected = "never", actual = scroll.horizontal_scroll_policy},
    {name = "platform list reserves its vertical gutter", expected = "auto-and-reserve-space", actual = scroll.vertical_scroll_policy},
    {name = "scroll activation does not add left padding", expected = 0, actual = scroll.style.extra_left_padding_when_activated or false},
    {name = "scroll activation does not add right padding", expected = 0, actual = scroll.style.extra_right_padding_when_activated or false},
    {name = "platform header x stays fixed on expand", expected = header_position.x, actual = position.x},
    {name = "platform header y stays fixed on expand", expected = header_position.y, actual = position.y},
    {name = "expanded card before click", expected = true, actual = item.tags.expanded == true},
    {name = "content before click", expected = true, actual = find(item, "shm_ol_content") ~= nil},
    {name = "production GUI owner before click", expected = "shm-orbital-logistics", actual = item.get_mod()}
  }, player)
end

function scenario.checks(player, observed)
  local item = card(player)
  local position = header_center()
  local names = {}
  local all_owned = true
  for _, event in ipairs(observed) do
    names[#names + 1] = event.name
    if event.owner ~= "shm-orbital-logistics" then all_owned = false end
  end
  return with_route_checks({
    {name = "production mod loaded", expected = true, actual = script.active_mods["shm-orbital-logistics"] ~= nil},
    {name = "production GUI owner", expected = "shm-orbital-logistics", actual = item.get_mod()},
    {name = "overview still visible", expected = true, actual = player.gui.screen.shm_ol_overview.visible},
    {name = "platform header x stays fixed on collapse", expected = header_position.x, actual = position.x},
    {name = "platform header y stays fixed on collapse", expected = header_position.y, actual = position.y},
    {name = "card collapsed", expected = false, actual = item.tags.expanded == true},
    {name = "card content removed", expected = false, actual = find(item, "shm_ol_content") ~= nil},
    {name = "expand tooltip restored", expected = "shm-orbital-logistics.expand", actual = toggle(player).tooltip[1]},
    {name = "native GUI targets", expected = "shm_ol_overview_button,shm_ol_card_toggle,shm_ol_card_toggle", actual = table.concat(names, ",")},
    {name = "native GUI events belong to production mod", expected = true, actual = all_owned}
  }, player)
end

return scenario
