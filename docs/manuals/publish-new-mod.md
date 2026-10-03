# Опубликовать новый мод на портале

## Когда использовать

Первая публикация мода, которого на портале ещё нет. Для новых версий уже
опубликованного мода — `release-mod.md`.

Шаг необратим в части имени: `name` из `info.json` становится постоянным
идентификатором мода на портале, его используют другие моды в `dependencies`.
Переименования нет.

## Что требуется

- Аккаунт factorio.com с купленной игрой (портал доступен только покупателям).
- API-ключ с usage `ModPortal: Publish Mods`, см. `setup-dev-environment.md`,
  шаги 6–7. FMTK этот шаг не покрывает: он умеет Upload и Details, но не
  `init_publish`. Поэтому первая публикация — либо веб-интерфейсом портала,
  либо `curl` по этому манулу.
- Мод, прошедший локальный прогон по `test-mod-locally.md`.
- Собранный zip (шаг 2 ниже).

## Шаги

1. Проверь `info.json` против ограничений портала:

   - `name` — `shm-<mod-key>`, длина строго больше 3 и меньше 50 символов,
     только латиница, цифры, `-` и `_`;
   - `version` — три числа `0..65535`;
   - `title` — `Shahimat: <Название>`, до 100 символов;
   - `author` — `Shahimat` (портал покажет имя аккаунта, но поле обязательно);
   - `factorio_version` — ровно два числа, `"2.0"` для основной дорожки.
     Три числа портал отклонит.

   Убедись, что имя свободно:

   ```bash
   curl -s -o /dev/null -w "%{http_code}\n" \
     https://mods.factorio.com/api/mods/shm-<mod-key>
   ```

   `404` — имя свободно, `200` — занято.

2. Собери zip. Имя файла строго `{name}_{version}.zip`, внутри ровно одна
   папка верхнего уровня (её имя не важно), `info.json` — в корне этой папки:

   ```
   shm-<mod-key>_0.1.0.zip
   └── shm-<mod-key>/
       ├── info.json
       ├── changelog.txt
       ├── thumbnail.png
       ├── LICENSE
       └── ...
   ```

   В архив не должны попасть `node_modules`, файлы из `specs/` и `context/`.

3. Положи в архив `thumbnail.png` 144×144 — он показывается и на портале, и в
   мод-менеджере игры.

4. Проверь `changelog.txt` на формат (разбор правил — в
   `release-mod.md`, раздел «Формат changelog.txt»). Портал формат не
   проверяет и покажет файл как обычный текст, а вот игра на кривом формате
   напишет ошибку в лог.

5. Подготовь `LICENSE` в составе мода: текст MIT плюс абзац-оговорка про
   ассеты Wube. Без оговорки лицензия обещает права на то, чем ты не
   владеешь — см. `context/conventions/licensing.yml`.

6. Запроси `upload_url`:

   ```bash
   curl -fsS -X POST \
     -H "Authorization: Bearer $FACTORIO_UPLOAD_API_KEY" \
     -F "mod=shm-<mod-key>" \
     https://mods.factorio.com/api/v2/mods/init_publish
   ```

   В ответе — JSON с полем `upload_url`.

7. Загрузи архив вместе с метаданными мода:

   ```bash
   curl -fsS -X POST \
     -F "file=@shm-<mod-key>_0.1.0.zip" \
     -F "license=default_mit" \
     -F "category=<одно из значений enum>" \
     -F "source_url=https://github.com/<owner>/factorio-modding" \
     -F "description=<описание в markdown>" \
     "<upload_url>"
   ```

   Успех — `{"success": true, "url": "..."}`.

   Значения `category`: `no-category`, `content`, `overhaul`, `tweaks`,
   `utilities`, `scenarios`, `mod-packs`, `localizations`, `internal`.

8. Добей страницу мода: summary, теги, FAQ, скриншоты —
   см. `release-mod.md`, раздел «Правка страницы мода».

9. Проверь результат и зафиксируй факт:

   ```bash
   curl -fsS https://mods.factorio.com/api/mods/shm-<mod-key>/full
   ```

   Затем обнови `docs/behavior/release-published-via-api.yml`
   (`verified: true` + `verified_at` + `verified_note`) и поле
   `published_mods` в `docs/entities/mod-portal.yml`.

## Если что-то пошло не так

Ответ API содержит поле `error`:

- `ModAlreadyExists` — имя занято, выбирай другое (шаг 1).
- `InvalidApiKey` — ключ не тот или просрочен.
- `Forbidden` — у ключа нет usage `ModPortal: Publish Mods`.
- `InvalidModRelease` — некорректные данные в `info.json` (чаще всего
  `factorio_version` из трёх чисел или недопустимые символы в `name`).
- `InvalidModUpload` — проблема со структурой zip: нет одной папки верхнего
  уровня, либо `info.json` не в её корне.
- `InternalError` / `Unknown` — повторить позже, с exponential backoff: Wube
  просит об этом в usage guidelines и оставляет право ограничивать
  злоупотребляющих клиентов.

## Правовые рамки

- Wube оставляет право удалить мод или отредактировать его листинг без
  предупреждения.
- Загружаемое не должно содержать чужих защищённых материалов без разрешения
  правообладателя.
- Производные от ассетов Factorio включать в мод можно, но права на них
  остаются у Wube, и Wube вправе потребовать их удаления.
- Публикуя мод, ты выдаёшь Wube безотзывную бессрочную безвозмездную
  сублицензируемую лицензию на мод и его содержимое.
- Коммерческое использование ассетов и исходников Factorio — только по
  отдельному согласию Wube (`factorio@factorio.com`).
