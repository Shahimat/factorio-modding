-- Переключение режима полной стопки: замена лоадера, перенос настроек и
-- лубриканта AAI, клавиша, вставка настроек, чертёж.

local f = require('tests.ingame.fixture')
local switch = require('runtime.switch')

local RED = defines.wire_connector_id.circuit_red

local function pipes_at(position)
  local found = {}
  for _, entity in pairs(f.surface().find_entities_filtered({ position = { position.x, position.y + 1 / 32 }, type = 'storage-tank' })) do
    found[#found + 1] = entity
  end
  return found
end

describe('переключение', function()
  before_each(f.clear)
  after_each(f.clear)

  it('меняет прототип туда и обратно, старый лоадер исчезает', function()
    if not f.aai() then
      return
    end
    local base = f.loader('superior')
    local old = f.create(base, { 0.5, 0.5 }, { direction = defines.direction.east })
    local alt = switch.switch_to(old, false)
    assert(alt and alt.valid and alt.name == base .. '-shm-alt', 'не стал копией')
    assert(not old.valid, 'старый остался')
    local back = switch.switch_to(alt, true)
    assert(back and back.name == base, 'не вернулся')
    local loaders = f.surface().find_entities_filtered({ position = { 0.5, 0.5 }, type = 'loader-1x1' })
    assert(#loaders == 1, 'лоадеров на месте: ' .. #loaders)
  end)

  it('тот же режим — та же сущность', function()
    if not f.aai() then
      return
    end
    local entity = f.create(f.loader('superior'), { 0.5, 0.5 })
    assert(switch.switch_to(entity, true) == entity, 'заменён без нужды')
  end)

  it('сохраняет направление, тип, фильтры, стопку, провода, условие, здоровье и качество', function()
    if not f.aai() then
      return
    end
    local quality = prototypes.quality['uncommon'] and 'uncommon' or 'normal'
    local entity = f.create(f.loader('superior'), { 0.5, 0.5 }, {
      direction = defines.direction.south,
      type = 'input',
      quality = quality,
    })
    local combinator = f.create('constant-combinator', { 2.5, 0.5 })
    entity.loader_filter_mode = 'whitelist'
    entity.set_filter(1, { name = 'iron-plate' })
    entity.loader_belt_stack_size_override = 2
    entity.health = entity.max_health / 2
    entity.get_wire_connector(RED, true).connect_to(combinator.get_wire_connector(RED, true))
    local behavior = entity.get_or_create_control_behavior() --[[@as LuaLoaderControlBehavior]]
    behavior.circuit_enable_disable = true
    behavior.circuit_condition = { first_signal = { type = 'item', name = 'iron-plate' }, comparator = '>', constant = 5 }

    local new = switch.switch_to(entity, false)
    assert(new and new.name == f.loader('superior') .. '-shm-alt', 'замена не удалась')
    assert(new.direction == defines.direction.south, 'направление')
    assert(new.loader_type == 'input', 'тип: ' .. new.loader_type)
    assert(new.quality.name == quality, 'качество')
    assert(new.loader_filter_mode == 'whitelist', 'режим фильтра')
    assert(new.get_filter(1) and new.get_filter(1).name == 'iron-plate', 'фильтр')
    assert(new.loader_belt_stack_size_override == 2, 'стопка: ' .. new.loader_belt_stack_size_override)
    assert(math.abs(new.health - new.max_health / 2) < 0.01, 'здоровье')
    local connector = new.get_wire_connector(RED, false)
    assert(connector and connector.connection_count == 1, 'провод потерян')
    local new_behavior = new.get_control_behavior() --[[@as LuaLoaderControlBehavior]]
    assert(new_behavior and new_behavior.circuit_enable_disable, 'условие сети потеряно')
  end)

  it('лоадер AAI работает после переключения, лубрикант не теряется, лишних труб нет', function()
    if f.aai_mode() ~= 'lubricated' then
      return
    end
    local chest, loader = f.loader_line(f.loader('superior'), 0)
    local before = f.lubricate(loader).get_fluid(1).amount
    local new = switch.switch_to(loader, false)
    assert(new, 'замена не удалась')
    local pipes = pipes_at(new.position)
    assert(#pipes == 1 and pipes[1].name == new.name .. '-pipe', 'трубы на месте: ' .. #pipes)
    local after = pipes[1].get_fluid(1)
    assert(after and after.amount >= before - 1, ('лубрикант: было %s, стало %s'):format(before, after and after.amount))
    chest.insert({ name = 'iron-plate', count = 50 })
    after_ticks(180, function()
      assert(chest.get_inventory(defines.inventory.chest).get_item_count('iron-plate') < 50, 'лоадер стоит')
    end)
  end)

  it('призрак меняет вариант, сохраняя направление, тип, фильтры, стопку, провода, условие и метки', function()
    if not f.aai() then
      return
    end
    local quality = prototypes.quality['uncommon'] and 'uncommon' or 'normal'
    local ghost = f.create('entity-ghost', { 0.5, 0.5 }, {
      inner_name = f.loader('superior'),
      direction = defines.direction.south,
      type = 'input',
      quality = quality,
    })
    local combinator = f.create('constant-combinator', { 2.5, 0.5 })
    ghost.loader_filter_mode = 'whitelist'
    ghost.set_filter(1, { name = 'iron-plate' })
    ghost.loader_belt_stack_size_override = 2
    ghost.tags = { mark = 7 }
    ghost.get_wire_connector(RED, true).connect_to(combinator.get_wire_connector(RED, true))
    local behavior = ghost.get_or_create_control_behavior() --[[@as LuaLoaderControlBehavior]]
    behavior.circuit_enable_disable = true

    local new = switch.switch_to(ghost, false)
    assert(new and new.type == 'entity-ghost' and new.ghost_name == f.loader('superior') .. '-shm-alt', 'призрак не стал копией')
    assert(not ghost.valid, 'старый призрак остался')
    assert(#f.surface().find_entities_filtered({ position = { 0.5, 0.5 }, type = 'entity-ghost' }) == 1, 'на месте не один призрак')
    assert(new.direction == defines.direction.south, 'направление')
    assert(new.loader_type == 'input', 'тип: ' .. new.loader_type)
    assert(new.quality.name == quality, 'качество')
    assert(new.loader_filter_mode == 'whitelist', 'режим фильтра')
    assert(new.get_filter(1) and new.get_filter(1).name == 'iron-plate', 'фильтр')
    assert(new.loader_belt_stack_size_override == 2, 'стопка')
    assert(new.tags and new.tags.mark == 7, 'метки')
    local connector = new.get_wire_connector(RED, false)
    assert(connector and connector.connection_count == 1, 'провод потерян')
    local new_behavior = new.get_control_behavior() --[[@as LuaLoaderControlBehavior]]
    assert(new_behavior and new_behavior.circuit_enable_disable, 'условие сети потеряно')

    local back = switch.switch_to(new, true)
    assert(back and back.ghost_name == f.loader('superior'), 'призрак не вернулся')
  end)

  it('клавиша: призрак и свой лоадер — переключать, чужой лоадер — мимо', function()
    if not f.aai() then
      return
    end
    local ghost = f.create('entity-ghost', { 0.5, 0.5 }, { inner_name = f.loader('superior') })
    assert(switch.classify(ghost, game.forces.player) == 'switch', 'призрак не переключается')
    local enemy = f.create(f.loader('superior'), { 4.5, 0.5 }, { force = 'enemy' })
    assert(switch.classify(enemy, game.forces.player) == 'ignore', 'чужой лоадер переключается')
    local mine = f.create(f.loader('superior'), { 8.5, 0.5 })
    assert(switch.classify(mine, game.forces.player) == 'switch', 'свой лоадер не переключается')
  end)

  it('вставка настроек переносит режим источника', function()
    if not f.aai() then
      return
    end
    local source = f.create(f.loader('superior') .. '-shm-alt', { 0.5, 0.5 })
    local destination = f.create(f.loader('hyper'), { 4.5, 0.5 })
    local result = switch.paste(source, destination)
    assert(result and result.name == f.loader('hyper') .. '-shm-alt', 'режим не перенесён')
    local ghost = f.create('entity-ghost', { 8.5, 0.5 }, { inner_name = f.loader('hyper') })
    local pasted = switch.paste(source, ghost)
    assert(pasted and pasted.ghost_name == f.loader('hyper') .. '-shm-alt', 'режим не перенесён на призрак')
  end)
end)

describe('чертёж', function()
  before_each(f.clear)
  after_each(f.clear)

  it('сохраняет режим каждого лоадера и строит его обратно', function()
    if not f.aai() then
      return
    end
    local base = f.loader('superior')
    f.create(base, { 0.5, 0.5 })
    f.create(base .. '-shm-alt', { 2.5, 0.5 })
    local inventory = game.create_inventory(1)
    local blueprint = inventory[1]
    blueprint.set_stack('blueprint')
    blueprint.create_blueprint({ surface = f.surface(), force = 'player', area = { { 0, 0 }, { 3, 1 } } })
    local ghosts = blueprint.build_blueprint({
      surface = f.surface(),
      force = 'player',
      position = { 10, 10 },
      build_mode = defines.build_mode.forced,
    })
    local built = {}
    for _, ghost in pairs(ghosts) do
      if ghost.ghost_type == 'loader-1x1' then
        local _, entity = ghost.revive()
        assert(entity, 'призрак не ожил')
        built[entity.name] = (built[entity.name] or 0) + 1
      end
    end
    inventory.destroy()
    assert(built[base] == 1 and built[base .. '-shm-alt'] == 1, 'построено: ' .. serpent.line(built))
  end)
end)
