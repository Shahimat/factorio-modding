-- Зонд стенда: перенастраивает тиры через API, как чужой мод.

ShmAdvancedBelts.configure('hyper', {
  speed = 120,
  recipes = {
    belt = { ingredients = { { type = 'item', name = 'iron-plate', amount = 7 } } },
  },
  technology = { count = 3000 },
})
ShmAdvancedBelts.set_enabled('absolute', false)
