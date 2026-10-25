-- Тиры лент и лоадеры AAI к ним. Стадия `data-updates`: к этому моменту
-- зависимые моды отработали `data.lua` и их переопределения из API собраны,
-- а AAI Loaders уже объявил `AAILoaders.make_tier`.

require('prototypes.tiers').run(ShmAdvancedBelts._take())
