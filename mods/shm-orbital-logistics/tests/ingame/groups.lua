-- Перевод секций на имя группы с меткой: фильтры сохраняются, меняется у всех
-- хабов группы, чужое имя не затирается.

local f = require('tests.ingame.fixture')
local groups = require('runtime.groups')
local tags = require('logic.tags')

local function slot_of(section)
  local slot = section.get_slot(1)
  return slot.value and slot.value.name, slot.min
end

describe('группы', function()
  before_all(f.prepare_force)
  before_each(f.clear)
  after_each(f.clear)

  it('секция без группы получает имя с меткой и сохраняет фильтры', function()
    local _, hub = f.platform('a')
    local section = f.request(hub, 300, { from = 'planet', import_from = f.PLANET })
    local name = groups.name_for(section, tags.parse('[reserve]'), 'Test fuel 1')
    assert(name == 'Test fuel 1 [reserve]', name)
    assert(groups.rename(game.forces.player, section, name))
    assert(section.group == name, 'группа не назначена: ' .. section.group)
    local item, min = slot_of(section)
    assert(item == f.ITEM and min == 300, 'фильтр потерян: ' .. tostring(item) .. ' ' .. tostring(min))
    game.forces.player.delete_logistic_group(name)
  end)

  it('смена метки у группы меняет её у всех хабов и удаляет старое имя', function()
    local force = game.forces.player
    local _, a = f.platform('a')
    local _, b = f.platform('b')
    local old = 'Test plates [depot:nauvis]'
    local section_a = f.request(a, 500, { group = old, from = 'planet', import_from = f.PLANET })
    local section_b = b.get_logistic_sections().add_section(old)
    section_b.multiplier = 3
    local name = groups.name_for(section_a, tags.parse('[cargo→aquilo]'))
    assert(groups.rename(force, section_a, name))
    assert(section_a.group == 'Test plates [cargo→aquilo]' and section_b.group == section_a.group,
      'не у всех: ' .. section_a.group .. ' / ' .. section_b.group)
    local item, min = slot_of(section_b)
    assert(item == f.ITEM and min == 500, 'фильтры B потеряны')
    assert(section_b.multiplier == 3, 'множитель B потерян')
    assert(force.get_logistic_group(old) == nil, 'старая группа осталась')
    force.delete_logistic_group(name)
  end)

  it('занятое имя не затирается', function()
    local force = game.forces.player
    local _, a = f.platform('a')
    f.request(a, 100, { group = 'Test taken', from = 'planet', import_from = f.PLANET })
    local section = f.request(a, 200, { from = 'planet', import_from = f.PLANET })
    local ok, reason = groups.rename(force, section, 'Test taken')
    assert(not ok and reason == 'name-taken', 'чужая группа затёрта')
    assert(section.group == '')
    force.delete_logistic_group('Test taken')
  end)
end)
