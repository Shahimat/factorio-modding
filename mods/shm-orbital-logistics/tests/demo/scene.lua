-- Демо-сцена Orbital Logistics: по паре платформ на сценарий, имена
-- начинаются с `OL-`, группы — с `OL demo`. Строится командой dev-мода и
-- тестом в игре основного мода; `check` сверяет итог с ожидаемым.

local scene = {}

local PREFIX = 'OL-'
local PLATE = 'iron-plate'
local COPPER = 'copper-plate'
local HOLMIUM = 'holmium-plate'

--- name, planet, items = { [предмет] = n }, providing,
--- sections = { { group, item, min, from, import_from } }, expect — строка для чата,
--- check(hub, section_of) → true, если итог как ожидается.
local PLATFORMS = {
  {
    name = 'OL-01 Склад плит [depot:nauvis] — отдаёт',
    planet = 'nauvis', items = { [PLATE] = 1000 }, providing = true,
    sections = { { group = 'OL demo plates [depot:nauvis]', item = PLATE, min = 1000, from = 'planet', import_from = 'nauvis' } },
    expect = 'склад над Нависом отдаёт плиты челноку OL-02',
    check = function(hub) return hub.count(PLATE) < 1000 end,
  },
  {
    name = 'OL-02 Челнок над Нависом — получает плиты',
    planet = 'nauvis',
    sections = { { item = PLATE, min = 200, from = 'platforms', import_from = 'nauvis' } },
    expect = 'получает 200 плит со склада OL-01',
    check = function(hub) return hub.count(PLATE) >= 200 end,
  },
  {
    name = 'OL-03 Груз [cargo→aquilo] над Нависом — держит',
    planet = 'nauvis', items = { [PLATE] = 500 }, providing = true,
    sections = { { group = 'OL demo plates [cargo→aquilo]', item = PLATE, min = 500, from = 'planet', import_from = 'nauvis' } },
    expect = 'не отдаёт плиты челноку OL-02: груз для Аквило, остаётся 500',
    check = function(hub) return hub.count(PLATE) == 500 end,
  },
  {
    name = 'OL-04 Груз [cargo→aquilo] над Аквило — отдаёт',
    planet = 'aquilo', items = { [PLATE] = 500 }, providing = true,
    sections = { { group = 'OL demo plates [cargo→aquilo]', item = PLATE, min = 500, from = 'planet', import_from = 'nauvis' } },
    expect = 'на точке назначения отдаёт плиты платформе OL-05',
    check = function(hub) return hub.count(PLATE) < 500 end,
  },
  {
    name = 'OL-05 Получатель над Аквило',
    planet = 'aquilo',
    sections = { { item = PLATE, min = 200, from = 'platforms', import_from = 'aquilo' } },
    expect = 'получает 200 плит от груза OL-04',
    check = function(hub) return hub.count(PLATE) >= 200 end,
  },
  {
    name = 'OL-06 Свой запас [reserve] над Нависом — держит',
    planet = 'nauvis', items = { [PLATE] = 300 }, providing = true,
    sections = { { group = 'OL demo reserve [reserve]', item = PLATE, min = 300, from = 'planet', import_from = 'nauvis' } },
    expect = 'свой запас: челнок OL-02 его не трогает, остаётся 300',
    check = function(hub) return hub.count(PLATE) == 300 end,
  },
  {
    name = 'OL-07 Челнок с гольмием [cargo→nauvis]',
    planet = 'nauvis', items = { [HOLMIUM] = 300 }, providing = true,
    sections = { { group = 'OL demo holmium [cargo→nauvis]', item = HOLMIUM, min = 300, from = 'planet', import_from = 'fulgora' } },
    expect = 'привёз гольмий на Навис и сдаёт его складу OL-08',
    check = function(hub) return hub.count(HOLMIUM) < 300 end,
  },
  {
    name = 'OL-08 Склад гольмия [depot:nauvis] — принимает транзит',
    planet = 'nauvis', providing = true,
    sections = { { group = 'OL demo holmium [depot:nauvis]', item = HOLMIUM, min = 200, from = 'planet', import_from = 'nauvis' } },
    expect = 'мод дозапрашивает гольмий с платформ, склад получает 200 от OL-07',
    check = function(hub) return hub.count(HOLMIUM) >= 200 end,
  },
  {
    name = 'OL-09 Сбор [cargo→fulgora] над Фульгорой — выдаёт',
    planet = 'fulgora', items = { [COPPER] = 400 }, providing = true,
    sections = { { group = 'OL demo scrap [cargo→fulgora]', item = COPPER, min = 5000, from = 'all' } },
    expect = 'секция сбора выключена модом на этом хабе, медь уходит платформе OL-10',
    check = function(hub, section_of)
      local section = section_of('OL demo scrap [cargo→fulgora]')
      return section ~= nil and section.active == false and hub.count(COPPER) < 400
    end,
  },
  {
    name = 'OL-10 Получатель над Фульгорой',
    planet = 'fulgora',
    sections = { { item = COPPER, min = 200, from = 'platforms', import_from = 'fulgora' } },
    expect = 'получает 200 меди от сбора OL-09',
    check = function(hub) return hub.count(COPPER) >= 200 end,
  },
  {
    name = 'OL-11 Склад [depot:nauvis] над Вулканом — держит',
    planet = 'vulcanus', items = { [PLATE] = 500 }, providing = true,
    sections = { { group = 'OL demo plates [depot:nauvis]', item = PLATE, min = 1000, from = 'planet', import_from = 'nauvis' } },
    expect = 'склад вне своей орбиты: платформе OL-12 не отдаёт, остаётся 500',
    check = function(hub) return hub.count(PLATE) == 500 end,
  },
  {
    name = 'OL-12 Получатель над Вулканом',
    planet = 'vulcanus',
    sections = { { item = PLATE, min = 100, from = 'platforms', import_from = 'vulcanus' } },
    expect = 'ничего не получает: склад OL-11 не на своей орбите',
    check = function(hub) return hub.count(PLATE) == 0 end,
  },
}

local function demo_platforms(force)
  local found = {}
  for _, platform in pairs(force.platforms) do
    if platform.valid and string.sub(platform.name, 1, #PREFIX) == PREFIX and platform.scheduled_for_deletion == 0 then
      found[platform.name] = platform
    end
  end
  return found
end

--- Удалённая платформа исчезает не сразу и до того ещё запрашивает и
--- отдаёт, поэтому перед удалением хаб обнуляется.
local function retire(platform)
  local hub = platform.hub
  if hub and hub.valid then
    hub.providing_to_other_platforms = false
    local sections = hub.get_logistic_sections()
    for index = sections.sections_count, 1, -1 do
      if sections.get_section(index).is_manual then
        sections.remove_section(index)
      end
    end
    hub.get_inventory(defines.inventory.hub_main).clear()
    hub.get_inventory(defines.inventory.hub_trash).clear()
  end
  platform.destroy()
end

function scene.clear(force)
  local removed = 0
  for _, platform in pairs(demo_platforms(force)) do
    retire(platform)
    removed = removed + 1
  end
  return removed
end

local function add_section(hub, spec)
  local section = hub.get_logistic_sections().add_section(spec.group)
  section.set_slot(1, {
    value = { type = 'item', name = spec.item, quality = 'normal', comparator = '=' },
    min = spec.min,
    request_from = spec.from,
    import_from = spec.import_from,
  })
end

--- Строит сцену заново и возвращает строки для чата.
function scene.build(force)
  scene.clear(force)
  local lines = { 'Orbital Logistics demo: платформы OL-01…OL-12, смотри в удалённом виде.',
    'Передачи идут ~16 с игры, затем /shm-orbital-demo check.' }
  for _, spec in ipairs(PLATFORMS) do
    local platform = force.create_space_platform({
      name = spec.name,
      planet = spec.planet,
      starter_pack = 'space-platform-starter-pack',
    })
    if platform then
      platform.apply_starter_pack()
      local hub = platform.hub
      hub.request_missing_construction_materials = false
      hub.providing_to_other_platforms = spec.providing == true
      for item, count in pairs(spec.items or {}) do
        hub.insert({ name = item, count = count })
      end
      for _, section in ipairs(spec.sections) do
        add_section(hub, section)
      end
      lines[#lines + 1] = spec.name .. ': ' .. spec.expect
    else
      lines[#lines + 1] = spec.name .. ': не создана'
    end
  end
  return lines
end

--- Сверяет итог: { { name, ok, expect } } по каждой платформе сцены.
function scene.check(force)
  local found = demo_platforms(force)
  local results = {}
  for _, spec in ipairs(PLATFORMS) do
    local platform = found[spec.name]
    local ok = false
    if platform and platform.hub and platform.hub.valid then
      local hub = platform.hub
      local inventory = hub.get_inventory(defines.inventory.hub_main)
      local view = {
        count = function(item)
          return inventory.get_item_count(item)
        end,
      }
      local function section_of(group)
        local sections = hub.get_logistic_sections()
        for index = 1, sections.sections_count do
          local section = sections.get_section(index)
          if section.group == group then
            return section
          end
        end
        return nil
      end
      ok = spec.check(view, section_of) == true
    end
    results[#results + 1] = { name = spec.name, ok = ok, expect = spec.expect }
  end
  return results
end

return scene
