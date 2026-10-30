-- Линии снабжения: K-15 (правка шапки доходит до всех), K-16 (ручные секции
-- рядом с секциями линии), K-17 (площадка — участник со своим множителем),
-- K-21 (одна группа, разные множители), удаление участника и линии.

local f = require('tests.ingame.fixture')
local lines = require('runtime.lines')

local function line_section(entity, line)
  local sections = entity.get_logistic_sections()
  local found = nil
  local count = 0
  for index = 1, sections.sections_count do
    local section = sections.get_section(index)
    local prefix = line.name .. ' · '
    if string.sub(section.group, 1, #prefix) == prefix then
      found = section
      count = count + 1
    end
  end
  return found, count
end

local function slots(section)
  local list = {}
  for slot = 1, section.filters_count do
    local s = section.get_slot(slot)
    if s.value then
      list[#list + 1] = string.format('%s/%s/%d/%s', s.value.name, tostring(s.value.quality and (s.value.quality.name or s.value.quality)),
        s.min or 0, tostring(s.request_from or 'planet'))
    end
  end
  table.sort(list)
  return table.concat(list, ' ')
end

describe('линии снабжения', function()
  before_all(f.prepare_force)
  before_each(f.clear)
  after_each(function()
    for _, line in ipairs(lines.list(game.forces.player)) do
      lines.delete(game.forces.player, line)
    end
    f.clear()
  end)

  it('K-15, K-17, K-21: участники получают свои группы и множители, правка шапки доходит до всех', function()
    local force = game.forces.player
    local line = assert(lines.create(force, 'Test Aquilo'))
    line.items = { { name = f.ITEM, quality = 'rare', count = 2000 } }
    local _, depot = f.platform('depot')
    local _, shuttle1 = f.platform('s1')
    local _, shuttle2 = f.platform('s2')
    local pad = f.pad()
    local p_depot = lines.attach(force, line, depot)
    p_depot.role, p_depot.places, p_depot.import_from, p_depot.request_from, p_depot.multiplier = 'depot', 'nauvis', 'nauvis', 'planet', 5
    local p1 = lines.attach(force, line, shuttle1)
    p1.role, p1.places, p1.import_from, p1.request_from = 'cargo', 'aquilo', 'nauvis', 'platforms'
    local p2 = lines.attach(force, line, shuttle2)
    p2.role, p2.places, p2.import_from, p2.request_from, p2.multiplier = 'cargo', 'aquilo', 'nauvis', 'platforms', 0.5
    local p_pad = lines.attach(force, line, pad)
    p_pad.multiplier = 0.5
    lines.sync(force, line)

    local s_depot = line_section(depot, line)
    local s1 = line_section(shuttle1, line)
    local s2 = line_section(shuttle2, line)
    local s_pad = line_section(pad, line)
    assert(s_depot.group == 'Test Aquilo · nauvis/planet [depot:nauvis]', s_depot.group)
    assert(s1.group == 'Test Aquilo · nauvis/platforms [cargo→aquilo]' and s2.group == s1.group, 'челноки не в одной группе')
    assert(s_pad.group == 'Test Aquilo · pad', s_pad.group)
    assert(s_depot.multiplier == 5 and s1.multiplier == 1 and s2.multiplier == 0.5 and s_pad.multiplier == 0.5, 'множители')
    assert(slots(s_depot) == 'iron-plate/rare/2000/planet', slots(s_depot))
    assert(slots(s1) == 'iron-plate/rare/2000/platforms', slots(s1))

    line.items = { { name = f.ITEM, quality = 'legendary', count = 3000 }, { name = 'copper-plate', quality = 'normal', count = 100 } }
    lines.sync(force, line)
    assert(slots(s_depot) == 'copper-plate/normal/100/planet iron-plate/legendary/3000/planet', slots(s_depot))
    assert(slots(s2) == 'copper-plate/normal/100/platforms iron-plate/legendary/3000/platforms', slots(s2))
    assert(slots(s_pad) == 'copper-plate/normal/100/planet iron-plate/legendary/3000/planet', slots(s_pad))
    assert(s_depot.multiplier == 5 and s2.multiplier == 0.5, 'множители потеряны после правки шапки')
  end)

  it('K-16 ручные секции хаба не трогаются линией', function()
    local force = game.forces.player
    local line = assert(lines.create(force, 'Test manual'))
    line.items = { { name = f.ITEM, quality = 'normal', count = 100 } }
    local _, hub = f.platform('a')
    local manual = f.request(hub, 42, { item = 'copper-plate', from = 'planet', import_from = f.PLANET })
    lines.attach(force, line, hub)
    lines.sync(force, line)
    assert(manual.valid and manual.get_slot(1).min == 42 and manual.group == '', 'ручная секция изменена')
    local _, count = line_section(hub, line)
    assert(count == 1, 'секций линии ' .. count)
  end)

  it('смена роли переводит участника в другую группу, старая удаляется', function()
    local force = game.forces.player
    local line = assert(lines.create(force, 'Test role'))
    line.items = { { name = f.ITEM, quality = 'normal', count = 100 } }
    local _, hub = f.platform('a')
    local participant = lines.attach(force, line, hub)
    local old = line_section(hub, line).group
    participant.role, participant.places = 'depot', 'nauvis'
    lines.sync(force, line)
    local section, count = line_section(hub, line)
    assert(count == 1 and section.group ~= old, 'группа не сменилась: ' .. section.group)
    assert(force.get_logistic_group(old) == nil, 'старая группа осталась')
  end)

  it('отключение участника и удаление линии убирают секции и группы', function()
    local force = game.forces.player
    local line = assert(lines.create(force, 'Test remove'))
    line.items = { { name = f.ITEM, quality = 'normal', count = 100 } }
    local _, a = f.platform('a')
    local _, b = f.platform('b')
    lines.attach(force, line, a)
    lines.attach(force, line, b)
    lines.detach(force, line, 1)
    assert(select(2, line_section(a, line)) == 0, 'у отключённого осталась секция')
    assert(select(2, line_section(b, line)) == 1, 'у оставшегося нет секции')
    local name = line.name
    lines.delete(force, line)
    assert(select(2, line_section(b, { name = name })) == 0, 'секция осталась после удаления линии')
    for _, group in pairs(force.get_logistic_groups()) do
      assert(string.sub(group, 1, #name) ~= name, 'группа линии осталась: ' .. group)
    end
  end)

  it('имя линии: пустое, с разделителем и повтор — отказ; переименование переносит группы', function()
    local force = game.forces.player
    assert(lines.create(force, '  ') == nil)
    assert(lines.create(force, 'a · b') == nil)
    local line = assert(lines.create(force, 'Test rename'))
    assert(select(2, lines.create(force, 'Test rename')) == 'name-taken')
    line.items = { { name = f.ITEM, quality = 'normal', count = 100 } }
    local _, hub = f.platform('a')
    lines.attach(force, line, hub)
    assert(lines.rename(force, line, 'Test renamed'))
    local section, count = line_section(hub, line)
    assert(count == 1 and string.sub(section.group, 1, 12) == 'Test renamed', 'группа не переименована')
    for _, group in pairs(force.get_logistic_groups()) do
      local old = 'Test rename · '
      assert(string.sub(group, 1, #old) ~= old, 'старая группа осталась: ' .. group)
    end
  end)
end)
