-- Топливо K2 становится химическим, транспорт K2 — снова на ванильном
-- топливе. Последняя стадия данных: к этому моменту K2, K2 Spaced Out и их
-- модули совместимости уже расставили `kr-vehicle-fuel`.

local fuel_merge = require('logic.fuel-merge')

fuel_merge.merge(data.raw, 'kr-vehicle-fuel', 'chemical')
