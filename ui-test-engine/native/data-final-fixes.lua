-- Factoriopedia служит нативным host для input и отрисовки simulation GUI.
local simulation = {
    checkboard = false,
    generate_map = true,
    init_update_count = 1,
    hide_factoriopedia_gradient = true,
    length = 60 * 600,
    mods = {"shm-ui-test-engine", "shm-ui-test-fixture"},
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
