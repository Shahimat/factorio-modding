local button_name = "shm-ui-test-counter"
local status_name = "shm-ui-test-status"

remote.add_interface("shm-ui-test-fixture", {
  open = function(player_index, enabled)
    local player = game.get_player(player_index)
    storage.clicks = storage.clicks or {}
    storage.last_event = storage.last_event or {}
    storage.clicks[player_index] = 0
    local frame = player.gui.screen.add{
      type = "frame", name = status_name,
      direction = "vertical"
    }
    frame.location = {8, 4}
    frame.style.width = 280
    frame.style.padding = 4
    local marker = frame.add{type = "label", caption = "UI-PROBE"}
    marker.style.font_color = {1, 0, 1}
    local label = frame.add{type = "label", name = "counter", caption = "Clicks: 0"}
    label.style.font = "heading-1"
    label.style.font_color = {1, 0.2, 0.2}
    local button = player.gui.screen.add{
      type = "button", name = button_name, caption = "CLICK-UI",
      enabled = enabled
    }
    button.location = {8, 76}
    button.style.width = 280
    button.style.height = 32
    button.style.font_color = {0, 1, 1}
    button.style.hovered_font_color = {0, 1, 1}
    button.style.disabled_font_color = {0, 1, 1}
  end,
  state = function(player_index)
    local player = game.get_player(player_index)
    return {
      clicks = storage.clicks[player_index],
      caption = player.gui.screen[status_name].counter.caption,
      event_name = storage.last_event[player_index] and storage.last_event[player_index].name or "none"
    }
  end
})

-- Единственный путь изменения счётчика — настоящее событие GUI движка.
script.on_event(defines.events.on_gui_click, function(event)
  if not (event.element and event.element.valid and event.element.name == button_name) then return end
  local count = storage.clicks[event.player_index] + 1
  storage.clicks[event.player_index] = count
  storage.last_event[event.player_index] = {
    name = event.name, tick = event.tick, button = event.button,
    cursor_display_location = event.cursor_display_location
  }
  local label = game.get_player(event.player_index).gui.screen[status_name].counter
  label.caption = "Clicks: " .. count
  label.style.font_color = {0.2, 1, 0.2}
end)
