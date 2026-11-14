-- Factoriopedia служит нативным host для input и отрисовки simulation GUI.
local options = require("run-options")
local simulation = {
    checkboard = false,
    generate_map = true,
    init_update_count = 1,
    hide_factoriopedia_gradient = true,
    length = 60 * 600,
    mods = options.simulation_mods,
    game_view_settings = {
      show_controller_gui = true,
      show_minimap = false,
      show_quickbar = false,
      show_shortcut_bar = false
    },
    init = [[remote.call("shm-ui-test-engine", "start")]],
    update = [[remote.call("shm-ui-test-engine", "update")]]
}

data.raw["utility-constants"].default.main_menu_simulations = {}
local scene = table.deepcopy(data.raw.container["wooden-chest"])
scene.name = "shm-ui-test-scene"
scene.localised_name = "UI test scene"
scene.factoriopedia_simulation = simulation
data:extend{scene}

-- Только профиль стенда: расширяем host, не уменьшая GUI тестируемого мода.
if options.viewport then
  local styles = data.raw["gui-style"].default
  local contents = styles.factoriopedia_contents_scroll_pane
  contents.width = options.viewport.width + 40
  contents.height = options.viewport.height + 80
  contents.vertical_flow_style.width = options.viewport.width
  styles.entity_button_frame.width = options.viewport.width
  styles.entity_button_frame.height = options.viewport.height
  styles.wide_entity_button.width = options.viewport.width
  styles.wide_entity_button.height = options.viewport.height
end
