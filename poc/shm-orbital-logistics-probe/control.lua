-- Точка входа прототипа. Своей логики нет: наблюдения за ванильными
-- передачами между платформами 2.1 — тесты в игре в `tests/`, их запускает
-- мод `factorio-test`, см. README.md.

if script.active_mods['factorio-test'] then
  require('__factorio-test__/init')({
    'tests.transfers',
  })
end
