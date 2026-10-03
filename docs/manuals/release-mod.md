# Выпустить новый релиз существующего мода

## Когда использовать

Мод уже есть на портале, нужно выложить новую версию. Первая публикация — в
`publish-new-mod.md`.

## Что требуется

- API-ключ с usage `ModPortal: Upload Mods`, для правки страницы мода — ещё и
  `ModPortal: Edit Mods`. У нас это один ключ с тремя usage, см.
  `setup-dev-environment.md`, шаги 6–7.
- Вместо `curl` из этого манула те же два шага умеет FMTK — задачи `Upload` и
  `Details` в панели «Factorio Mod Packages». Команду FMTK `Publish` не
  использовать: она сама делает git commit, тег и push.
- Прогон по `test-mod-locally.md` на той мажорной версии игры, в дорожку
  которой идёт релиз.

## Шаги

1. Подними `version` в `info.json`. Версия мода **не** привязана к версии
   игры: она свободна для семантики изменений самого мода, а дорожка
   задаётся полем `factorio_version` — см.
   `context/conventions/factorio-version-track.yml`.

2. Добавь секцию в `changelog.txt` сверху. Формат жёсткий, разбор ниже.

3. Прогони мод локально по `test-mod-locally.md` и проверь лог на ошибки
   парсинга.

4. Собери zip `{name}_{version}.zip` — требования к архиву в behavior
   `mod-zip-matches-portal-rules`.

5. Запроси `upload_url`:

   ```bash
   curl -fsS -X POST \
     -H "Authorization: Bearer $FACTORIO_UPLOAD_API_KEY" \
     -F "mod=shm-<mod-key>" \
     https://mods.factorio.com/api/v2/mods/releases/init_upload
   ```

6. Загрузи архив:

   ```bash
   curl -fsS -X POST -F "file=@shm-<mod-key>_<version>.zip" "<upload_url>"
   ```

   Успех — `{"success": true}`.

7. Проверь, что релиз появился:

   ```bash
   curl -fsS https://mods.factorio.com/api/mods/shm-<mod-key> \
     | python3 -m json.tool
   ```

   В списке `releases` должна быть новая версия с ожидаемым
   `info_json.factorio_version`.

## Формат changelog.txt

Правила жёсткие, парсер придирчив, ошибки уходят в лог-файл игры, а не на
экран:

- разделитель секции — **ровно 99 дефисов**;
- следующая строка непустая и начинается с `Version: ` (с пробелом после
  двоеточия);
- необязательная строка даты начинается с `Date: `, формат самой даты
  произвольный;
- категория — **ровно два пробела**, текст, двоеточие в конце строки;
- запись — **ровно четыре пробела**, дефис, пробел;
- продолжение многострочной записи — **ровно шесть пробелов**;
- никаких табов и никаких пробелов в конце строк;
- двух секций с одной версией быть не может, точных дублей записей внутри
  одной категории одной версии — тоже;
- запись обязана идти после строки категории.

Категории, которые игра распознаёт и выносит перед вкладкой «All»:
`Major Features`, `Features`, `Minor Features`, `Graphics`, `Sounds`,
`Optimizations`, `Balancing`, `Combat Balancing`, `Circuit Network`,
`Changes`, `Bugfixes`, `Modding`, `Scripting`, `Gui`, `Control`,
`Translation`, `Debug`, `Ease of use`, `Info`, `Locale`, `Compatibility`.

Шаблон секции:

```
---------------------------------------------------------------------------------------------------
Version: 0.2.0
Date: 2026-10-03
  Features:
    - Новая возможность одной строкой.
  Bugfixes:
    - Починено то-то.
```

## Правка страницы мода

Описание, теги, лицензия, FAQ, homepage — через отдельный эндпоинт, ключом с
usage `ModPortal: Edit Mods`:

```bash
curl -fsS -X POST \
  -H "Authorization: Bearer $FACTORIO_UPLOAD_API_KEY" \
  -F "mod=shm-<mod-key>" \
  -F "summary=<до 500 символов>" \
  -F "description=<markdown>" \
  -F "license=default_mit" \
  -F "tags=logistics" -F "tags=circuit-network" \
  -F "source_url=https://github.com/<owner>/factorio-modding" \
  https://mods.factorio.com/api/v2/mods/edit_details
```

Ограничения: `title` 1–250 символов, `summary` до 500, `homepage` и
`source_url` — схема `http`/`https`, до 256 символов. Флаг `deprecated=true`
скрывает мод из публичных листингов.

Скриншоты — двухшаговой загрузкой:

```bash
curl -fsS -X POST -H "Authorization: Bearer $FACTORIO_UPLOAD_API_KEY" \
  -F "mod=shm-<mod-key>" \
  https://mods.factorio.com/api/v2/mods/images/add
curl -fsS -X POST -F "image=@screenshot.png" "<upload_url>"
```

## Если что-то пошло не так

- `UnknownMod` — мода нет на портале, значит это первая публикация, иди в
  `publish-new-mod.md`.
- `InvalidModRelease` — некорректные данные релиза в `info.json`. Частые
  причины: версия уже существует на портале, `factorio_version` из трёх
  чисел.
- `InvalidModUpload` — структура zip не та: нужна ровно одна папка верхнего
  уровня с `info.json` в её корне.
- `Forbidden` — ключ без нужного usage: для релиза нужен `Upload Mods`, для
  страницы мода — `Edit Mods`.
- `InternalError` / `Unknown` — повтор с exponential backoff.

## После релиза

Обнови `verified` / `verified_at` в затронутых `docs/behavior/*.yml` —
локальный прогон и факт публикации проверяемы именно сейчас, по горячим
следам.
