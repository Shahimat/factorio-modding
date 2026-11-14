local route = require('logic.overview_route')
local stops = { 'nauvis', 'vulcanus', 'fulgora' }

describe('цикл маршрута обзора', function()
  it('сохраняет порядок расписания, выделяет только текущую планету', function()
    for index, name in ipairs(stops) do
      local model = route.build(stops, index, name)
      assert_eq(model.stops, stops)
      assert(model.loop and model.active_stop == index and model.active_leg == nil)
    end
  end)

  it('выделяет каждое плечо, включая замыкающее от последней остановки к первой', function()
    for from = 1, #stops do
      local to = from % #stops + 1
      local model = route.build(stops, to, nil, stops[from], stops[to])
      assert_eq(model.stops, stops)
      assert(model.loop and model.active_stop == nil and model.active_leg == from)
    end
  end)

  it('повторные остановки и одинаковые перегоны различаются индексом расписания', function()
    local repeated = { 'nauvis', 'vulcanus', 'nauvis', 'vulcanus' }
    assert(route.build(repeated, 3, 'nauvis').active_stop == 3)
    assert(route.build(repeated, 4, 'nauvis').active_stop == 3)
    assert(route.build(repeated, 4, nil, 'nauvis', 'vulcanus').active_leg == 3)
    assert(route.build(repeated, 1, nil, 'vulcanus', 'nauvis').active_leg == 4)
  end)

  it('промежуточная связь не меняет цель и порядок длинного плеча расписания', function()
    local model = route.build({ 'nauvis', 'aquilo' }, 2, nil, 'gleba', 'aquilo', 1)
    assert_eq(model.stops, { 'nauvis', 'aquilo' })
    assert(model.active_leg == 1)
  end)

  it('ручной пропуск остановки не выдаёт предшественника назначения за реальный источник', function()
    assert(route.build(stops, 3, nil, 'nauvis', 'fulgora', 1).active_leg == nil)
    assert(route.build(stops, 3, nil, 'nauvis', 'fulgora').active_leg == nil)
  end)

  it('без истории промежуточного перелёта и при неоднозначных повторных плечах не угадывает', function()
    assert(route.build({ 'nauvis', 'aquilo' }, 2, nil, 'gleba', 'aquilo').active_leg == nil)
    assert(route.build({ 'nauvis', 'vulcanus', 'nauvis', 'vulcanus' }, nil, nil, 'nauvis', 'vulcanus').active_leg == nil)
  end)

  it('без расписания показывает реальное место или открытый перегон без выдуманной петли', function()
    assert_eq(route.build({}, nil, 'nauvis'), { stops = { 'nauvis' }, loop = false, active_stop = 1 })
    assert_eq(route.build({}, nil, nil, 'vulcanus', 'nauvis'), {
      stops = { 'vulcanus', 'nauvis' }, loop = false, active_leg = 1,
    })
    assert_eq(route.build({}, nil, nil), { stops = {}, loop = false })
  end)

  it('одна остановка не изображает полёт на себя, посторонняя орбита не получает ложную подсветку', function()
    assert_eq(route.build({ 'nauvis' }, 1, 'nauvis'), { stops = { 'nauvis' }, loop = false, active_stop = 1 })
    assert_eq(route.build(stops, 1, 'aquilo'), { stops = stops, loop = true })
    assert(route.build(stops, nil, nil, 'fulgora', 'nauvis').active_leg == 3)
  end)
end)
