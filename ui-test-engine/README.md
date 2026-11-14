# UI test engine

Каркас нативных UI-тестов Factorio. Первый PoC загружает отдельный fixture-мод,
нажимает кнопку через `LuaSimulation` и проверяет состояние вместе с PNG.
MCP и управление рабочим столом не используются.

Из корня репозитория, с установленными npm-зависимостями и графической Factorio:

```sh
npm run test:ui:poc
npm run test:ui:poc -- --negative
```

Первый запуск должен вернуть `PASS` и код `0`; второй намеренно отключает кнопку
и должен вернуть `FAIL` и код `1`. Каждый запуск закрывает своё окно игры
после сохранения снимков. Каталог с `report.json`, PNG и логом печатается в выводе.
Для нетиповой установки используется `FACTORIO_BIN`; аргументы —
`npm run test:ui:poc -- --help`.

Это **не готовый универсальный framework**: пока есть один сценарий и компактный
GUI во viewport Factoriopedia. Image checks — по семантическим маркерам fixture,
без golden baseline. Визуальные тесты реальных модов ещё не подключены.

- [Устройство, артефакты и ограничения](../docs/entities/ui-test-engine.yml)
- [Проверяемое поведение](../docs/behavior/ui-test-engine-native-poc.yml)
- [Подтверждённые особенности API](../docs/entities/engine-ui-simulations.yml)
- [Следующая работа](../context/views/goal--ui-test-engine.yaml)
