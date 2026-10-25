-- Клавиша переключения режима и подсказка в разделе «Манипуляторы».

data:extend({
  {
    type = 'custom-input',
    name = 'shm-full-hand-toggle',
    key_sequence = 'SHIFT + M',
    action = 'lua',
  },
  {
    type = 'tips-and-tricks-item',
    name = 'shm-full-hand',
    tag = '[entity=kr-superior-inserter]',
    category = 'inserters',
    order = 'z-[shm-full-hand]',
    indent = 1,
    dependencies = { 'inserters' },
    trigger = {
      type = 'build-entity',
      entity = 'kr-superior-inserter',
      count = 1,
    },
  },
})
