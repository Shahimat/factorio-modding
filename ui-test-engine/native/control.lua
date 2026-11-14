-- require допустим только при загрузке control.lua, не внутри callbacks.
local options = require("run-options")
local scenario = require("scenario")
local player
local age = 0
local finished = false
local host_age = 0
local host_failed = false

local function emit(event)
  event.protocol = 1
  event.run_id = options.run_id
  event.tick = game.tick
  log("SHM_UI_TEST " .. helpers.table_to_json(event))
end

local function safely(source, callback)
  local ok, err = pcall(callback)
  if not ok then
    finished = true
    host_failed = true
    emit{type = "error", source = source, message = tostring(err)}
  end
end

local function capture(role)
  -- Снимок делает OUTER game: capture из simulation не включает её GUI.
  game.take_screenshot{
    player = player,
    path = "ui-test/" .. role .. ".png",
    show_gui = true,
    show_entity_info = false,
    anti_alias = false,
    force_render = true,
    daytime = 0,
    hide_clouds = true
  }
  game.set_wait_for_screenshots_to_finish()
  emit{type = "capture", role = role}
end

remote.add_interface("shm-ui-test-engine", {
  host_start = function(player_index)
    safely("host", function()
      assert(not game.simulation, "Screenshot host must be an ordinary game")
      player = game.get_player(player_index)
      player.surface.daytime = 0
      player.surface.freeze_daytime = true
      player.hide_locked_prototypes_in_factoriopedia = false
    end)
  end,
  host_update = function()
    if not player or host_failed then return end
    safely("host", function()
      host_age = host_age + 1
      if host_age == 30 then
        player.open_factoriopedia_gui(prototypes.entity["shm-ui-test-scene"])
      elseif host_age == 120 then
        capture("before")
      elseif host_age == 420 then
        capture("after")
      elseif host_age == 421 then
        -- Новый тик после ожидания screenshot writer, не преждевременный итог.
        emit{type = "complete"}
      end
    end)
  end,
  start = function()
    safely("simulation", function()
      local simulation = game.simulation
      assert(simulation, "Input driver requires a native simulation")
      player = simulation.create_test_player{name = "UI test"}
      simulation.camera_player = player
      simulation.camera_position = {0, 0}
      simulation.camera_zoom = 1
      simulation.hide_cursor = true
      game.tick_paused = false
      player.surface.daytime = 0
      player.surface.freeze_daytime = true
      scenario.setup(player, options)
      emit{type = "started", scenario = scenario.name}
    end)
  end,
  update = function()
    if finished then return end
    safely("simulation", function()
      age = age + 1
      if age == 120 then
        local position = game.simulation.get_widget_position(scenario.target)
        assert(position, "Native locator did not find the target widget")
        assert(game.simulation.move_cursor{position = position, speed = 1000}, "Cursor did not reach target")
        emit{type = "located", position = position}
      elseif age == 150 then
        game.simulation.mouse_click()
        emit{type = "input", action = "mouse_click"}
      elseif age == 180 then
        game.simulation.move_cursor{position = {1000, 1000}, speed = 10000}
      elseif age == 240 then
        emit{type = "result", checks = scenario.checks(player)}
        finished = true
      end
    end)
  end
})
