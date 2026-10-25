-- Превосходные манипуляторы K2 ждут полную руку, рядом — скрытые копии без
-- ожидания для переключателя режима. Последняя стадия данных: к этому
-- моменту K2 Spaced Out уже задал им стакинг на ленте, а
-- ChangeInserterDropLane — `allow_custom_vectors`, и копии их наследуют.

local variants = require('logic.variants')

local created = variants.apply(data.raw)
if #created > 0 then
  data:extend(created)
end
