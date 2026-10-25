-- Поведение манипулятора в мире: ожидание полной руки, выкладка сразу,
-- выкладка испортившейся руки, стопки на ленте.

local f = require('tests.ingame.fixture')

describe('полная рука', function()
  before_each(function()
    f.clear()
    f.power()
    f.widen_hands()
  end)

  after_each(function()
    f.clear()
    f.reset_force()
  end)

  it('в режиме по умолчанию неполная рука не выкладывается', function()
    local input, inserter, output = f.chest_line(f.SUP, 0)
    input.insert({ name = 'iron-plate', count = 1 })
    after_ticks(300, function()
      assert(f.count(output, 'iron-plate') == 0, 'неполная рука выложена, рука вмещает ' .. inserter.inserter_target_pickup_count)
      assert(inserter.held_stack.valid_for_read and inserter.held_stack.count == 1, 'предмет не в руке')
    end)
  end)

  it('в режиме «Сразу» неполная рука выкладывается', function()
    local input, _, output = f.chest_line(f.SUP_INSTANT, 0)
    input.insert({ name = 'iron-plate', count = 1 })
    after_ticks(300, function()
      assert(f.count(output, 'iron-plate') == 1, 'предмет не выложен')
    end)
  end)

  it('при достатке предметов манипулятор работает, а не стоит', function()
    local input, _, output = f.chest_line(f.SUP, 0)
    input.insert({ name = 'iron-plate', count = 200 })
    after_ticks(300, function()
      assert(f.count(output, 'iron-plate') > 0, 'полная рука не выложена')
    end)
  end)

  it('испортившаяся рука выкладывается, а не держится вечно', function()
    if not script.active_mods['space-age'] then
      return -- порча предметов есть только со Space Age
    end
    local input, inserter, output = f.chest_line(f.SUP, 0)
    -- Плод юмако портится за час; 0,1 % оставшегося срока — около 200 тиков.
    input.insert({ name = 'yumako', count = 1, spoil_percent = 0.999 })
    after_ticks(900, function()
      assert(f.count(output, 'spoilage') == 1, 'испорченная рука не выложена')
      assert(not inserter.held_stack.valid_for_read, 'рука не пуста')
    end)
  end)

  -- Высота стопки на ленте — `1 + belt_stack_size_bonus` силы (исследование
  -- вместимости конвейера), но не больше `max_belt_stack_size` манипулятора.
  local function biggest_belt_stack(bonus, ticks, check)
    game.forces.player.belt_stack_size_bonus = bonus
    local input = f.create('steel-chest', { 0.5, -0.5 })
    f.create(f.SUP, { 0.5, 0.5 })
    local belts = {}
    for x = 0, 3 do
      belts[#belts + 1] = f.create('transport-belt', { x + 0.5, 1.5 }, { direction = defines.direction.east })
    end
    input.insert({ name = 'iron-plate', count = 200 })
    after_ticks(ticks, function()
      local biggest = 0
      for _, belt in ipairs(belts) do
        for i = 1, belt.get_max_transport_line_index() do
          for _, item in pairs(belt.get_transport_line(i).get_detailed_contents()) do
            biggest = math.max(biggest, item.stack.count)
          end
        end
      end
      check(biggest)
    end)
  end

  it('без исследования вместимости конвейера стопок на ленте нет', function()
    biggest_belt_stack(0, 240, function(biggest)
      assert(biggest == 1, 'стопка на ленте без исследования: ' .. biggest)
    end)
  end)

  it('с исследованием стопки растут до максимума стакинга манипулятора', function()
    local max = prototypes.entity[f.SUP].inserter_max_belt_stack_size
    biggest_belt_stack(3, 240, function(biggest)
      local expected = math.min(max, 4)
      assert(biggest == expected, ('самая большая стопка %d, ожидалась %d'):format(biggest, expected))
    end)
  end)
end)
