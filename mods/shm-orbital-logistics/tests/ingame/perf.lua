-- V-10: цена прохода контроллера на нагрузке «поздней игры» — 40 платформ на
-- одной орбите, по 4 секции на 40 фильтров (две с метками, две без).
-- Результат пишется в лог строкой `[PERF]`, тест падает, если проход дороже
-- бюджета.

local f = require('tests.ingame.fixture')
local controller = require('runtime.controller')

local PLATFORMS = 40
local SECTIONS = 4
local SLOTS = 40
local PASSES = 20

local function items(count)
  local list = {}
  for name, prototype in pairs(prototypes.item) do
    if not prototype.hidden and not prototype.parameter and prototype.type == 'item' then
      list[#list + 1] = name
    end
  end
  table.sort(list)
  assert(#list >= count, 'предметов меньше ' .. count)
  return list
end

describe('нагрузка', function()
  before_all(f.prepare_force)
  before_each(f.clear)
  after_each(f.clear)

  it('V-10 проход по 40 платформам с 4×40 фильтрами укладывается в бюджет', function()
    local names = items(SECTIONS * SLOTS)
    local groups = { 'Perf reserve [reserve]', 'Perf depot [depot:nauvis]', '', '' }
    for p = 1, PLATFORMS do
      local _, hub = f.platform('perf')
      hub.providing_to_other_platforms = true
      for s = 1, SECTIONS do
        local group = groups[s] ~= '' and groups[s] or nil
        local section = hub.get_logistic_sections().add_section(group)
        if p == 1 or group == nil then
          for slot = 1, SLOTS do
            section.set_slot(slot, {
              value = { type = 'item', name = names[(s - 1) * SLOTS + slot], quality = 'normal', comparator = '=' },
              min = 10,
              request_from = 'planet',
              import_from = f.PLANET,
            })
          end
        end
      end
      hub.insert({ name = names[1], count = 5 })
    end
    controller.pass()
    local profiler = helpers.create_profiler()
    for _ = 1, PASSES do
      controller.pass()
    end
    profiler.stop()
    profiler.divide(PASSES)
    log({ '', '[PERF] V-10 полный проход, 40 платформ × 4 × 40: ', profiler })
    local slice = helpers.create_profiler()
    for tick = 0, PASSES * controller.SLICES - 1 do
      controller.slice({ tick = tick * controller.SLICE_TICKS })
    end
    slice.stop()
    slice.divide(PASSES * controller.SLICES)
    log({ '', '[PERF] V-10 порция прохода (1/', tostring(controller.SLICES), ' раз в ', tostring(controller.SLICE_TICKS), ' тиков): ', slice })
  end)
end)
