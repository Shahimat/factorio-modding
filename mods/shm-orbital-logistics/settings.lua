data:extend({
  {
    type = 'bool-setting',
    name = 'shm-orbital-logistics-enabled',
    setting_type = 'runtime-global',
    default_value = true,
    order = 'a',
  },
})

-- «Режим отладки» есть только в рабочей копии: метка `tests/debug.lua`
-- вырезается из zip релиза вместе со всем каталогом `tests/`.
if pcall(require, 'tests.debug') then
  data:extend({
    {
      type = 'bool-setting',
      name = 'shm-orbital-logistics-debug',
      setting_type = 'startup',
      default_value = false,
      order = 'z',
    },
  })
end
