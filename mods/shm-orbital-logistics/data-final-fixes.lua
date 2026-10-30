-- Иконка страницы «Советов и подсказок» — межпланетный маршрут Наувис —
-- Вулкан. Маршрут объявляет Space Age, жёсткой зависимости от него у мода
-- нет, поэтому иконка ставится только когда маршрут есть.

local connections = data.raw['space-connection']
local tip = data.raw['tips-and-tricks-item'] and data.raw['tips-and-tricks-item']['shm-orbital-logistics']
if tip and connections and connections['nauvis-vulcanus'] then
  tip.tag = '[img=space-connection/nauvis-vulcanus]'
end
