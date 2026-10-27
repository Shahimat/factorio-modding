-- Замена сущности при переключении: что переносится, что нет, разбор
-- клавиши и вставки настроек, разборка варианта «Сразу».

local f = require('tests.ingame.fixture')
local switch = require('runtime.switch')

local RED = defines.wire_connector_id.circuit_red

describe('переключение', function()
  before_each(function()
    f.clear()
    f.power()
    f.widen_hands()
  end)

  after_each(function()
    f.clear()
    f.reset_force()
  end)

  it('меняет прототип туда и обратно, старая сущность исчезает', function()
    local old = f.create(f.SUP, { 0.5, 0.5 })
    local instant = switch.switch_to(old, false)
    assert(instant and instant.valid and instant.name == f.SUP_INSTANT, 'не стал -instant')
    assert(not old.valid, 'старая сущность осталась')
    local back = switch.switch_to(instant, true)
    assert(back and back.name == f.SUP, 'не вернулся в исходный')
    local found = f.surface().find_entities_filtered({ position = { 0.5, 0.5 }, type = 'inserter' })
    assert(#found == 1, 'на месте манипуляторов: ' .. #found)
  end)

  it('тот же режим — та же сущность, без замены', function()
    local entity = f.create(f.SUP, { 0.5, 0.5 })
    assert(switch.switch_to(entity, true) == entity, 'сущность заменена без нужды')
  end)

  it('длинный переключается внутри своей семьи', function()
    local long = f.create(f.LONG, { 0.5, 0.5 })
    local instant = switch.switch_to(long, false)
    assert(instant and instant.name == 'shm-' .. f.LONG .. '-instant', 'длинный стал ' .. tostring(instant and instant.name))
  end)

  it('сохраняет настройки, провода, условие, полосу, здоровье, руку, направление и качество', function()
    local quality = prototypes.quality['uncommon'] and 'uncommon' or 'normal'
    local entity = f.create(f.SUP, { 0.5, 0.5 }, { direction = defines.direction.east, quality = quality })
    local combinator = f.create('constant-combinator', { 0.5, 2.5 })

    entity.use_filters = true
    entity.inserter_filter_mode = 'blacklist'
    entity.set_filter(1, { name = 'iron-plate' })
    entity.set_filter(2, { name = 'copper-plate' })
    entity.inserter_spoil_priority = 'spoiled-first'
    entity.inserter_stack_size_override = 3
    entity.pickup_from_left_lane = false
    local drop = { x = entity.drop_position.x, y = entity.drop_position.y + 0.2 }
    entity.drop_position = drop
    entity.health = entity.max_health / 2
    entity.held_stack.set_stack({ name = 'iron-gear-wheel', count = 2 })
    entity.get_wire_connector(RED, true).connect_to(combinator.get_wire_connector(RED, true))
    local behavior = entity.get_or_create_control_behavior() --[[@as LuaInserterControlBehavior]]
    behavior.circuit_enable_disable = true
    behavior.circuit_condition = {
      first_signal = { type = 'item', name = 'iron-plate' },
      comparator = '>',
      constant = 5,
    }

    local new = switch.switch_to(entity, false)
    assert(new and new.name == f.SUP_INSTANT, 'замена не удалась')

    assert(new.direction == defines.direction.east, 'направление потеряно')
    assert(new.quality.name == quality, 'качество потеряно: ' .. new.quality.name)
    assert(new.use_filters == true, 'фильтры выключились')
    assert(new.inserter_filter_mode == 'blacklist', 'режим фильтра потерян')
    assert(new.get_filter(1).name == 'iron-plate' and new.get_filter(2).name == 'copper-plate', 'фильтры потеряны')
    assert(new.inserter_spoil_priority == 'spoiled-first', 'приоритет порченого потерян')
    assert(new.inserter_stack_size_override == 3, 'размер стака потерян')
    assert(new.pickup_from_left_lane == false, 'выбор полосы захвата потерян')
    assert(math.abs(new.drop_position.y - drop.y) < 0.01, 'точка выкладки потеряна')
    assert(math.abs(new.health - new.max_health / 2) < 0.01, 'здоровье потеряно: ' .. new.health)
    assert(new.held_stack.valid_for_read and new.held_stack.name == 'iron-gear-wheel' and new.held_stack.count == 2, 'рука потеряна')
    assert(new.get_wire_connector(RED, true).is_connected_to(combinator.get_wire_connector(RED, true)), 'провод потерян')
    local cb = new.get_control_behavior() --[[@as LuaInserterControlBehavior?]]
    assert(cb and cb.circuit_enable_disable == true, 'включение по сети потеряно')
    local condition = cb.circuit_condition
    assert(condition and condition.constant == 5 and condition.comparator == '>' and condition.first_signal.name == 'iron-plate', 'условие сети потеряно')
  end)

  it('призрак меняет вариант, сохраняя настройки, провода, условие, метки и план доставки', function()
    local quality = prototypes.quality['uncommon'] and 'uncommon' or 'normal'
    local ghost = f.create('entity-ghost', { 0.5, 0.5 }, { inner_name = f.SUP, direction = defines.direction.east, quality = quality })
    local combinator = f.create('constant-combinator', { 0.5, 2.5 })

    ghost.use_filters = true
    ghost.inserter_filter_mode = 'blacklist'
    ghost.set_filter(1, { name = 'iron-plate' })
    ghost.inserter_spoil_priority = 'spoiled-first'
    ghost.inserter_stack_size_override = 3
    ghost.pickup_from_left_lane = false
    local drop = { x = ghost.drop_position.x, y = ghost.drop_position.y + 0.2 }
    ghost.drop_position = drop
    ghost.tags = { mark = 7 }
    ghost.insert_plan = { { id = { name = 'iron-plate' }, items = { in_inventory = { { inventory = defines.inventory.chest, stack = 0, count = 1 } } } } }
    ghost.get_wire_connector(RED, true).connect_to(combinator.get_wire_connector(RED, true))
    local behavior = ghost.get_or_create_control_behavior() --[[@as LuaInserterControlBehavior]]
    behavior.circuit_enable_disable = true
    behavior.circuit_condition = { first_signal = { type = 'item', name = 'iron-plate' }, comparator = '>', constant = 5 }

    local new = switch.switch_to(ghost, false)
    assert(new and new.type == 'entity-ghost' and new.ghost_name == f.SUP_INSTANT, 'призрак не стал -instant')
    assert(not ghost.valid, 'старый призрак остался')
    assert(#f.surface().find_entities_filtered({ position = { 0.5, 0.5 }, type = 'entity-ghost' }) == 1, 'на месте не один призрак')

    assert(new.direction == defines.direction.east, 'направление потеряно')
    assert(new.quality.name == quality, 'качество потеряно')
    assert(new.use_filters == true and new.inserter_filter_mode == 'blacklist', 'фильтр потерян')
    assert(new.get_filter(1).name == 'iron-plate', 'фильтры потеряны')
    assert(new.inserter_spoil_priority == 'spoiled-first', 'приоритет порченого потерян')
    assert(new.inserter_stack_size_override == 3, 'размер стака потерян')
    assert(new.pickup_from_left_lane == false, 'выбор полосы захвата потерян')
    assert(math.abs(new.drop_position.y - drop.y) < 0.01, 'точка выкладки потеряна')
    assert(new.tags and new.tags.mark == 7, 'метки потеряны')
    assert(#new.insert_plan == 1, 'план доставки потерян')
    assert(new.get_wire_connector(RED, true).is_connected_to(combinator.get_wire_connector(RED, true)), 'провод потерян')
    local cb = new.get_control_behavior() --[[@as LuaInserterControlBehavior?]]
    assert(cb and cb.circuit_enable_disable == true and cb.circuit_condition.constant == 5, 'условие сети потеряно')

    local back = switch.switch_to(new, true)
    assert(back and back.ghost_name == f.SUP, 'призрак не вернулся в исходный')
  end)

  it('клавиша: переключает своё и призрак, молчит на чужом', function()
    local own = f.create(f.SUP, { 0.5, 0.5 })
    local ghost = f.create('entity-ghost', { 2.5, 0.5 }, { inner_name = f.SUP })
    local bulk = f.create('bulk-inserter', { 4.5, 0.5 })
    local enemy = f.surface().create_entity({ name = f.SUP, position = { 6.5, 0.5 }, force = 'enemy' })
    local player_force = game.forces.player
    assert(switch.classify(own, player_force) == 'switch', 'своё не переключается')
    assert(switch.classify(ghost, player_force) == 'switch', 'призрак не переключается')
    local foreign_ghost = f.create('entity-ghost', { 8.5, 0.5 }, { inner_name = 'bulk-inserter' })
    assert(switch.classify(foreign_ghost, player_force) == 'ignore', 'призрак чужого манипулятора не проигнорирован')
    assert(switch.classify(bulk, player_force) == 'ignore', 'чужой манипулятор не проигнорирован')
    assert(switch.classify(enemy, player_force) == 'ignore', 'манипулятор чужой силы не проигнорирован')
    assert(switch.classify(nil, player_force) == 'ignore', 'пустой курсор не проигнорирован')
  end)

  it('вставка настроек переносит режим источника на приёмник', function()
    local source = f.create(f.SUP_INSTANT, { 0.5, 0.5 })
    local destination = f.create(f.SUP, { 2.5, 0.5 })
    destination.copy_settings(source)
    local result = switch.paste(source, destination)
    assert(result and result.name == f.SUP_INSTANT, 'режим не перенесён')
    local back = switch.paste(f.create(f.LONG, { 4.5, 0.5 }), result)
    assert(back and back.name == f.SUP, 'режим из длинного не перенесён')
    assert(switch.paste(f.create('bulk-inserter', { 6.5, 0.5 }), back) == nil, 'чужой источник подействовал')
    local ghost = f.create('entity-ghost', { 8.5, 0.5 }, { inner_name = f.SUP })
    local pasted = switch.paste(f.create(f.SUP_INSTANT, { 10.5, 0.5 }), ghost)
    assert(pasted and pasted.ghost_name == f.SUP_INSTANT, 'режим не перенесён на призрак')
  end)

  it('разборка варианта «Сразу» отдаёт обычный предмет', function()
    local instant = f.create(f.SUP_INSTANT, { 0.5, 0.5 })
    local inventory = game.create_inventory(4)
    assert(instant.mine({ inventory = inventory }), 'не разобрался')
    -- Отдельного предмета у варианта нет вовсе: в инвентаре ровно один
    -- предмет, и это обычный превосходный манипулятор.
    assert(inventory.get_item_count(f.SUP) == 1, 'в инвентаре нет ' .. f.SUP)
    assert(inventory.get_item_count() == 1, 'в инвентаре лишнее: ' .. inventory.get_item_count())
    inventory.destroy()
  end)
end)
