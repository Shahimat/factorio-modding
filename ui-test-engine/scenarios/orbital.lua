-- Реальный мод загружается отдельно. Его модули и обработчики здесь не require.
local scenario = {
  name = "orbital",
  capture = {before = 240, after = 540},
  result_at = 420
}
local platform_index
local negative

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

function scenario.setup(player, options)
  negative = options.negative
  local owner = remote.call("shm-orbital-ui-tests", "prepare_player", player.index)
  assert(owner == "shm-orbital-logistics", "Setup did not create the production GUI button")
  player.force.research_all_technologies()
  local platform = assert(player.force.create_space_platform{
    name = "UI collapse probe", planet = "nauvis", starter_pack = "space-platform-starter-pack"
  })
  platform.apply_starter_pack()
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
    return assert(player.gui.top.shm_ol_overview_button, "Overview button is missing")
  end},
  {id = "expand", locate_at = 75, click_at = 90, element = toggle},
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
  return {
    {name = "expanded card before click", expected = true, actual = item.tags.expanded == true},
    {name = "content before click", expected = true, actual = find(item, "shm_ol_content") ~= nil},
    {name = "production GUI owner before click", expected = "shm-orbital-logistics", actual = item.get_mod()}
  }
end

function scenario.checks(player, observed)
  local item = card(player)
  local names = {}
  local all_owned = true
  for _, event in ipairs(observed) do
    names[#names + 1] = event.name
    if event.owner ~= "shm-orbital-logistics" then all_owned = false end
  end
  return {
    {name = "production mod loaded", expected = true, actual = script.active_mods["shm-orbital-logistics"] ~= nil},
    {name = "production GUI owner", expected = "shm-orbital-logistics", actual = item.get_mod()},
    {name = "overview still visible", expected = true, actual = player.gui.screen.shm_ol_overview.visible},
    {name = "card collapsed", expected = false, actual = item.tags.expanded == true},
    {name = "card content removed", expected = false, actual = find(item, "shm_ol_content") ~= nil},
    {name = "expand tooltip restored", expected = "shm-orbital-logistics.expand", actual = toggle(player).tooltip[1]},
    {name = "native GUI targets", expected = "shm_ol_overview_button,shm_ol_card_toggle,shm_ol_card_toggle", actual = table.concat(names, ",")},
    {name = "native GUI events belong to production mod", expected = true, actual = all_owned}
  }
end

return scenario
