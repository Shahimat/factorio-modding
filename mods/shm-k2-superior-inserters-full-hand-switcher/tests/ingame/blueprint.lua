-- Режим в чертеже: снятие и постройка по нему. Тот же механизм у
-- CTRL + C / CTRL + V — копирование идёт через чертёж в курсоре.

local f = require('tests.ingame.fixture')

describe('чертёж', function()
  before_each(f.clear)
  after_each(f.clear)

  it('сохраняет режим каждого манипулятора и строит его обратно', function()
    f.create(f.SUP, { 0.5, 0.5 })
    f.create(f.SUP_INSTANT, { 2.5, 0.5 })
    local inventory = game.create_inventory(1)
    local blueprint = inventory[1]
    blueprint.set_stack('blueprint')
    blueprint.create_blueprint({
      surface = f.surface(),
      force = 'player',
      area = { { 0, 0 }, { 3, 1 } },
    })

    local names = {}
    for _, entity in pairs(blueprint.get_blueprint_entities() or {}) do
      names[entity.name] = (names[entity.name] or 0) + 1
    end
    assert(names[f.SUP] == 1 and names[f.SUP_INSTANT] == 1, 'в чертеже: ' .. serpent.line(names))

    local ghosts = blueprint.build_blueprint({
      surface = f.surface(),
      force = 'player',
      position = { 10, 10 },
      build_mode = defines.build_mode.forced,
    })
    local built = {}
    for _, ghost in pairs(ghosts) do
      local _, entity = ghost.revive()
      assert(entity, 'призрак не ожил')
      built[entity.name] = (built[entity.name] or 0) + 1
    end
    assert(built[f.SUP] == 1 and built[f.SUP_INSTANT] == 1, 'построено: ' .. serpent.line(built))
    inventory.destroy()
  end)
end)
