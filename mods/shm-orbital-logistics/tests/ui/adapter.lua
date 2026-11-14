-- Test player в simulation не получает стартовую кнопку обычным lifecycle.
-- Подготовка вызывает настоящий renderer в sandbox мода, не обработчики ввода.
local overview = require('runtime.overview_gui')
local adapter = {}

function adapter.register()
  remote.add_interface('shm-orbital-ui-tests', {
    prepare_player = function(player_index)
      local player = assert(game.get_player(player_index))
      storage.platforms = storage.platforms or {}
      storage.panel_block_collapsed = storage.panel_block_collapsed or {}
      overview.ensure_button(player)
      return player.gui.top[overview.BUTTON].get_mod()
    end,
  })
end

return adapter
