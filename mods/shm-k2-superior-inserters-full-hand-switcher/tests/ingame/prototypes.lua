-- Прототипы семьи после стадии данных: режимы, скрытая копия, стакинг на
-- ленте с K2 Spaced Out и без него, клавиша переключения.

local f = require('tests.ingame.fixture')

describe('прототипы', function()
  it('исходные ждут полную руку, копии -instant — нет', function()
    for _, base in ipairs({ f.SUP, f.LONG }) do
      local waiting = prototypes.entity[base]
      local instant = prototypes.entity['shm-' .. base .. '-instant']
      assert(waiting and instant, 'нет прототипа ' .. base .. ' или его копии')
      assert(waiting.wait_for_full_hand == true, base)
      assert(waiting.grab_less_to_match_belt_stack == true, base)
      assert(waiting.enter_drop_mode_if_held_stack_spoiled == true, base)
      assert(instant.wait_for_full_hand == false, base)
      assert(instant.grab_less_to_match_belt_stack == false, base)
      assert(instant.enter_drop_mode_if_held_stack_spoiled == false, base)
    end
  end)

  it('копия скрыта и ставится предметом исходного', function()
    local instant = prototypes.entity[f.SUP_INSTANT]
    assert(instant.hidden == true, 'копия не скрыта')
    local items = instant.items_to_place_this
    assert(items and items[1] and items[1].name == f.SUP, 'копия ставится не предметом ' .. f.SUP)
  end)

  it('стакинг на ленте одинаков у обоих режимов и зависит только от K2 Spaced Out', function()
    local waiting = prototypes.entity[f.SUP].inserter_max_belt_stack_size
    local instant = prototypes.entity[f.SUP_INSTANT].inserter_max_belt_stack_size
    assert(waiting == instant, ('стакинг разошёлся: %d и %d'):format(waiting, instant))
    if script.active_mods['Krastorio2-spaced-out'] then
      assert(waiting > 1, 'с K2 Spaced Out манипулятор не стакает: ' .. waiting)
    else
      assert(waiting == 1, 'без K2 Spaced Out манипулятор стакает: ' .. waiting)
    end
  end)

  it('клавиша переключения — SHIFT + M', function()
    local input = prototypes.custom_input['shm-full-hand-toggle']
    assert(input, 'нет custom-input shm-full-hand-toggle')
    assert(input.key_sequence == 'SHIFT + M', 'клавиша: ' .. tostring(input.key_sequence))
  end)
end)
