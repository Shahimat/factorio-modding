-- require допустим только при загрузке control.lua, не внутри callbacks.
local options = require("run-options")
local scenario = require("scenario")
local locator = require("locator")
local player
local age = 0
local finished = false
local host_age = 0
local host_failed = false
local observed = {}
local targets = {}
local capture_at = scenario.capture or {before = 120, after = 420}
local actions = scenario.actions or {{locate_at = 120, click_at = 150, query = scenario.target}}

script.on_event(defines.events.on_gui_click, function(event)
  local element = event.element
  if element and element.valid then
    observed[#observed + 1] = {name = element.name, owner = element.get_mod(), tick = event.tick}
  end
end)

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
    emit{type = "error", source = source, message = tostring(err) .. " [native events: " .. helpers.table_to_json(observed) .. "]"}
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
      elseif host_age == capture_at.before then
        capture("before")
      elseif host_age == capture_at.after then
        capture("after")
      elseif host_age == capture_at.after + 1 then
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
      if options.viewport then
        for index, point in ipairs(options.markers) do
          local marker = player.gui.screen.add{type = "label", caption = "+", ignored_by_interaction = true}
          marker.location = point
          marker.style.font_color = index == 1 and {1, 0, 1} or {0, 1, 1}
        end
      end
      emit{type = "started", scenario = scenario.name}
    end)
  end,
  update = function()
    if finished then return end
    safely("simulation", function()
      age = age + 1
      for index, action in ipairs(actions) do
        if age == action.locate_at then
          targets[index] = action.element and locator.prepare(action.element(player)) or {query = action.query}
        elseif age == action.locate_at + 1 then
          local position = locator.position(targets[index])
          assert(game.simulation.move_cursor{position = position, speed = 1000}, "Cursor did not reach target")
          emit{type = "located", step = action.id, position = position}
        elseif age == action.click_at then
          game.simulation.mouse_click()
          emit{type = "input", action = "mouse_click", step = action.id}
        elseif age == action.click_at + 5 then
          game.simulation.move_cursor{position = {1000, 1000}, speed = 10000}
          locator.clear(targets[index])
        end
      end
      if age == 180 and scenario.before then
        if scenario.reference_title then
          local title = scenario.reference_title(player)
          local reference = player.gui.screen.add{type = "frame", style = "inside_shallow_frame_with_padding"}
          reference.location = {x = options.reference.x, y = options.reference.y}
          reference.style.width = options.reference.width
          reference.style.height = options.reference.height
          reference.add{type = "label", caption = title.caption, style = title.style}
        end
        emit{type = "checkpoint", checks = scenario.before(player), frame = scenario.frame(player)}
      elseif age == (scenario.result_at or 240) then
        emit{type = "result", checks = scenario.checks(player, observed), frame = scenario.frame and scenario.frame(player)}
        finished = true
      end
    end)
  end
})
