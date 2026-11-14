-- Данные расширенной демо-сети; без игрового API, чтобы проверять связность
-- и набор запросов отдельно от размещения мира.
local spec = {
  PERIOD = 60,
  STOP_TICKS = 90 * 60,
  DEPOT_STOCK = 2000,
  IMPORT_STOCK = 600,
  SHUTTLE_STOCK = 400,
  PAD_STOCK = 100,
  RESERVE = 20,
  planets = {
    { name = 'nauvis', item = 'iron-plate' },
    { name = 'vulcanus', item = 'tungsten-plate' },
    { name = 'fulgora', item = 'holmium-plate' },
    { name = 'gleba', item = 'carbon-fiber' },
    { name = 'aquilo', item = 'lithium-plate' },
  },
  routes = {
    { 'nauvis', 'vulcanus' },
    { 'nauvis', 'fulgora' },
    { 'nauvis', 'gleba' },
    { 'gleba', 'aquilo' },
    { 'fulgora', 'aquilo' },
  },
}

function spec.planet(name)
  for _, planet in ipairs(spec.planets) do
    if planet.name == name then return planet end
  end
end

function spec.imports(name)
  local imports = {}
  for _, route in ipairs(spec.routes) do
    local other = route[1] == name and route[2] or route[2] == name and route[1] or nil
    if other then imports[#imports + 1] = spec.planet(other) end
  end
  return imports
end

return spec
