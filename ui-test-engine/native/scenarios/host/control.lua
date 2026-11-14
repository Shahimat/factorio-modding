script.on_event(defines.events.on_player_created, function(event)
  remote.call("shm-ui-test-engine", "host_start", event.player_index)
end)

script.on_event(defines.events.on_tick, function()
  remote.call("shm-ui-test-engine", "host_update")
end)
