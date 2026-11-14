-- Первый сценарий. Драйвер не импортирует и не вызывает обработчик клика.
local scenario = {
  name = "counter",
  target = {type = "text-button", text = "CLICK-UI"}
}

function scenario.setup(player, options)
  remote.call("shm-ui-test-fixture", "open", player.index, not options.negative)
end

function scenario.checks(player)
  local state = remote.call("shm-ui-test-fixture", "state", player.index)
  return {
    {name = "click count", expected = 1, actual = state.clicks},
    {name = "GUI caption", expected = "Clicks: 1", actual = state.caption},
    {name = "native GUI event", expected = defines.events.on_gui_click, actual = state.event_name}
  }
end

return scenario
