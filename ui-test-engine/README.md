# UI test engine

Каркас нативных UI-тестов Factorio: counter fixture и реальный Orbital Logistics.
`LuaSimulation` доставляет настоящие клики; проверяются состояние и PNG.
MCP и управление рабочим столом не используются.

Из корня репозитория, с установленными npm-зависимостями и графической Factorio:

```sh
npm run test:ui:poc
npm run test:ui:poc -- --negative
npm run test:ui:orbital
npm run test:ui:orbital -- --negative
```

Обычный запуск должен вернуть `PASS` и код `0`; `--negative` намеренно отключает
целевую кнопку и должен вернуть `FAIL` и код `1`. Каждый запуск закрывает своё окно игры
после сохранения снимков. Каталог с `report.json`, PNG и логом печатается в выводе.
Для нетиповой установки используется `FACTORIO_BIN`; аргументы —
`npm run test:ui:poc -- --help`.

Orbital требует установленного Space Age. Сценарий открывает обзор, разворачивает
и сворачивает карточку платформы. Аналогичная команда из workspace:
`npm run test:ui -w shm-orbital-logistics`. Dev-only адаптер подготавливает штатную
стартовую кнопку; обработчики ввода не вызываются напрямую.

Это **не готовый универсальный framework**: два профиля заданы кодом, capture
использует фиксированные таймеры. Counter проверяется по цветам; Orbital — по
отрисованному production-заголовку, состоянию и изменению содержимого окна.
Старая относительная панель и остальные GUI-сценарии мода этим не покрыты.

- [Устройство, артефакты и ограничения](../docs/entities/ui-test-engine.yml)
- [Проверяемое поведение](../docs/behavior/ui-test-engine-native-poc.yml)
- [Подтверждённые особенности API](../docs/entities/engine-ui-simulations.yml)
- [Следующая работа](../context/views/goal--ui-test-engine.yaml)
