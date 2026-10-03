# factorio-modding

Монорепозиторий модов [Factorio](https://factorio.com/) автора **Shahimat**.
Модов несколько, каждый решает свою задачу; моды могут зависеть друг от друга.

- Исходники модов — Lua, по одному пакету на мод в `mods/`.
- Инструменты сборки и публикации — TypeScript в strict-режиме, `tools/`,
  запуск через npm.
- Основная дорожка релизов — Factorio **2.0**; дорожка **2.1** подготовлена.
- Лицензия — MIT на собственный код и ассеты, с оговоркой про ассеты Wube,
  см. [LICENSE](LICENSE).

Все моды носят авторскую приписку `shm-`: внутреннее имя мода —
`shm-<mod-key>`, заголовок — `Shahimat: <Название>`. Это же префикс для имён
прототипов и ключей локали.

## Куда идти

- развернуть окружение с нуля —
  [setup-dev-environment.md](docs/manuals/setup-dev-environment.md)
- прогнать мод локально —
  [test-mod-locally.md](docs/manuals/test-mod-locally.md)
- опубликовать новый мод —
  [publish-new-mod.md](docs/manuals/publish-new-mod.md)
- выпустить новую версию —
  [release-mod.md](docs/manuals/release-mod.md)
- перевести мод на Factorio 2.1 —
  [migrate-mod-to-2-1.md](docs/manuals/migrate-mod-to-2-1.md)
- настроить страховочный hook —
  [setup-safety-hooks.md](docs/manuals/setup-safety-hooks.md)
- понять, почему принято то или иное решение — [CHANGELOG.md](CHANGELOG.md)

## Структура

```
docs/manuals/    пошаговые ручные процедуры — для человека
docs/entities/   спецификация: что за штука, из чего состоит
docs/behavior/   ожидаемое поведение в BDD-форме с полем verified
context/         слой для AI-агента: conventions, workflow, project.yml, цели
specs/           входящие ТЗ автора, по файлу на мод
mods/            пакеты модов, npm-workspaces
tools/           инструменты на TypeScript
```

`docs/` читают и человек, и агент. `context/` — только агент, точка входа для
него — [CLAUDE.md](CLAUDE.md).

## Как положить ТЗ

Файл markdown прямо в `specs/`, имя — `<mod-key>.md`, где `<mod-key>` — та же
часть, что пойдёт в имя мода `shm-<mod-key>`. Дальше агент разложит ТЗ по
слоям: состав мода → entity, критерии приёмки → behaviors, работа → задачи.
Сам файл спеки остаётся неизменным — его правит только автор. Правила —
`context/conventions/spec-intake.yml`.

## Правовые рамки

Моды используют API и ассеты Factorio. Производные от ассетов Wube можно
включать в мод, но права на них остаются у Wube; коммерческое использование —
только по отдельному согласию. Подробнее — [LICENSE](LICENSE) и
[Terms of Service](https://factorio.com/terms-of-service).

Этот репозиторий не связан с Wube Software Ltd. и не одобрен ею.
