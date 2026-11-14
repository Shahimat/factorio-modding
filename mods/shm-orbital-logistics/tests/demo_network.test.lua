local spec = require('tests.demo.network_spec')

describe('расширенная демо-сеть', function()
  it('пять разных планет экспортируют разные нескоропортящиеся предметы', function()
    local names, items = {}, {}
    assert(#spec.planets == 5)
    for _, planet in ipairs(spec.planets) do
      assert(not names[planet.name] and not items[planet.item])
      names[planet.name], items[planet.item] = true, true
      assert(spec.planet(planet.name) == planet)
    end
    assert(names.nauvis and names.vulcanus and names.fulgora and names.gleba and names.aquilo)
    assert(spec.planet('missing') == nil)
  end)

  it('каждому грузовому плечу соответствуют встречные планетарные запросы', function()
    local seen = {}
    for _, route in ipairs(spec.routes) do
      assert(route[1] ~= route[2] and spec.planet(route[1]) and spec.planet(route[2]))
      for index = 1, 2 do
        local from, to = route[index], route[3 - index]
        local found = false
        for _, imported in ipairs(spec.imports(to)) do
          if imported.name == from then found = true end
        end
        assert(found, 'нет обратного запроса ' .. from .. ' → ' .. to)
        seen[from .. '/' .. to] = true
      end
    end
    local count = 0
    for _ in pairs(seen) do count = count + 1 end
    assert(count == #spec.routes * 2)
    for _, planet in ipairs(spec.planets) do assert(#spec.imports(planet.name) > 0) end
    assert(#spec.imports('missing') == 0)
  end)

  it('окна стоянки длиннее передач, а запросы оставляют видимый запас', function()
    assert(spec.STOP_TICKS > 60 * 60)
    assert(spec.STOP_TICKS % spec.PERIOD == 0)
    assert(spec.DEPOT_STOCK > spec.SHUTTLE_STOCK)
    assert(spec.IMPORT_STOCK > spec.PAD_STOCK and spec.SHUTTLE_STOCK > spec.PAD_STOCK)
    assert(spec.RESERVE > 0)
  end)
end)
