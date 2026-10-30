# Развернуть окружение разработки мода

## Когда использовать

Первичная настройка машины под разработку модов: новая машина, переустановка
системы, или когда Factorio ещё не стоит.

Поддерживаются две платформы: macOS и Linux. Шаги общие, различаются пути и
пакетный менеджер — где они расходятся, указаны оба варианта.

На 2026-10-04 на рабочем Mac шаги 1–3 и 10 уже выполнены: игра стоит из
Steam (на 2026-10-25 — `2.1.23`, `mac-arm64`, нативная сборка), каталог данных создан,
расширения редактора установлены. Остаётся выпустить API-ключи — шаги 5–7.

На 2026-10-30 развёрнута вторая машина — Arch Linux: игра из Steam
(`2.1.24`, `linux64`) во второй библиотеке Steam, Node 24, `lua` 5.5, FMTK.
`npm run check`, Lua-тесты, `pack` и `npm run test:ingame` там зелёные.

## Шаги

1. Установи Factorio на эту машину — с сайта или через Steam. Мод-портал
   доступен только покупателям игры, демо не подойдёт.

   Игра нужна там, где лежит репозиторий: цикл разработки — правка Lua,
   перезапуск игры, чтение лога, и так по кругу. Копия на другой машине не
   заменяет локальную, потому что добавляет перенос файлов в каждую итерацию.

   Steam-покупка покрывает все три платформы одним appID 427520 — вторая
   установка на macOS или Linux не требует доплаты. Сборка под Apple Silicon
   нативная (с 1.1.71), Rosetta не нужна. Минимум по Steam: macOS 10.10+,
   8 ГБ RAM, 5 ГБ на диске; рекомендуется Apple Silicon и 16 ГБ RAM. Под
   Linux сборка тоже нативная (`linux64`), Proton не нужен.

2. Запусти игру один раз и закрой. Это создаст каталог пользовательских
   данных — дальше в манулах он называется **каталогом данных игры**:

   ```
   ~/Library/Application Support/factorio    # macOS
   ~/.factorio                               # Linux
   ```

   Внутри тебя интересуют `mods/`, `saves/`, `config/config.ini`,
   `player-data.json` и файлы логов `factorio-*.log`. Steam-сборка под
   Linux держит `player-data.json` не здесь, а в Steam Cloud — см. шаг 13.

   Для справки, каталог приложения (там `data/` с ванильными прототипами —
   полезно подсматривать, как сделано в базовой игре):

   ```
   /Applications/factorio.app/Contents                                   # macOS, с сайта
   ~/Library/Application Support/Steam/steamapps/common/Factorio/factorio.app/Contents  # macOS, Steam
   ~/.local/share/Steam/steamapps/common/Factorio                       # Linux, Steam
   ```

   Бинарь игры — `factorio.app/Contents/MacOS/factorio` на macOS и
   `bin/x64/factorio` на Linux. Если в Steam несколько библиотек, игра может
   стоять не в основной: список библиотек — в
   `~/.local/share/Steam/steamapps/libraryfolders.vdf`, игра — в
   `<библиотека>/steamapps/common/Factorio`.

   Инструменты репозитория (`test:ingame`, `recolor-sprites`,
   `orbital-art`) ищут игру в типовых местах, а нестандартный путь берут из
   переменной `FACTORIO_BIN`. Её задают в профиле оболочки, а не в
   репозитории — путь содержит имя пользователя, convention `secrets`:

   ```bash
   export FACTORIO_BIN=<библиотека>/steamapps/common/Factorio/bin/x64/factorio
   ```

   Чтобы запускать игру из терминала командой `factorio`, добавь каталог
   бинарника в `PATH` (в `~/.zshrc` или `~/.bashrc`; примеры для Steam):

   ```bash
   # macOS
   export PATH="$PATH:$HOME/Library/Application Support/Steam/steamapps/common/Factorio/factorio.app/Contents/MacOS"
   # Linux
   export PATH="$PATH:$HOME/.local/share/Steam/steamapps/common/Factorio/bin/x64"
   ```

   У Steam-сборки есть особенность: запущенная напрямую, она перезапускает
   себя через Steam («Steam requires game restart») и теряет аргументы
   командной строки, например `--mod-directory`. Перезапуск не происходит,
   если в текущем каталоге лежит `steam_appid.txt` с appID 427520, — так
   устроен Steamworks. Steam при этом должен быть запущен:

   ```bash
   mkdir -p /tmp/factorio-run && echo 427520 > /tmp/factorio-run/steam_appid.txt
   cd /tmp/factorio-run && factorio --mod-directory /tmp/factorio-mods-clean
   ```

   Проверено 2026-10-25 на 2.1.23 (`mac-arm64`, `steam`). Безголовые
   режимы вроде `--create` Steam не трогают и работают без этого файла.

3. Проверь, что каталог модов существует, и создай, если нет:

   ```bash
   # macOS
   ls -d ~/Library/Application\ Support/factorio/mods \
     || mkdir -p ~/Library/Application\ Support/factorio/mods
   # Linux
   ls -d ~/.factorio/mods || mkdir -p ~/.factorio/mods
   ```

4. Зафиксируй актуальные версии игры — они нужны для `factorio_version` и для
   решения, в какую дорожку релизов идти:

   ```bash
   curl -fsSL https://factorio.com/api/latest-releases
   ```

   На 2026-10-23: stable и experimental `2.1.23`. Дорожка новых релизов
   проекта — `2.1`, см. `context/conventions/factorio-version-track.yml`.

5. Войди в аккаунт factorio.com. Имя аккаунта — `Shahimat`, именно оно будет
   показано автором на мод-портале (поле `author` из `info.json` портал
   игнорирует).

6. Выпусти **один** API-ключ на https://factorio.com/profile и отметь у него
   сразу три usage:

   - `ModPortal: Publish Mods` — первая публикация нового мода;
   - `ModPortal: Upload Mods` — новые релизы существующих модов;
   - `ModPortal: Edit Mods` — описание, теги, лицензия, скриншоты.

   Один ключ, а не три: FMTK умеет работать только с одним ключом за раз и
   ждёт у него и Upload, и Edit. Ключ показывается один раз при создании —
   скопируй сразу, потом его можно только удалить и выпустить новый.

7. Положи ключ в переменную окружения своей оболочки, не в репозиторий:

   ```bash
   export FACTORIO_UPLOAD_API_KEY=...
   ```

   Имя переменной именно такое — его читает CLI `fmtk`, и оно имеет
   приоритет над хранилищем ключей системы. Этим же именем пользуются примеры `curl` в
   манулах `publish-new-mod.md` и `release-mod.md`, чтобы не держать три
   разных имени под один ключ.

   В git ключ не попадает никогда — см. behavior
   `release-published-via-api`, последний сценарий.

   Проверить ключ и его usage, ничего не создавая и не меняя:

   ```bash
   # Upload: на несуществующий мод ждём UnknownMod
   curl -sS -X POST -H "Authorization: Bearer $FACTORIO_UPLOAD_API_KEY" \
     -F "mod=shm-zzz-not-a-real-mod" \
     https://mods.factorio.com/api/v2/mods/releases/init_upload

   # Edit: на несуществующий мод ждём UnknownMod
   curl -sS -X POST -H "Authorization: Bearer $FACTORIO_UPLOAD_API_KEY" \
     -F "mod=shm-zzz-not-a-real-mod" -F "summary=probe" \
     https://mods.factorio.com/api/v2/mods/edit_details

   # Publish: на заведомо занятое имя ждём ModAlreadyExists
   curl -sS -X POST -H "Authorization: Bearer $FACTORIO_UPLOAD_API_KEY" \
     -F "mod=flib" \
     https://mods.factorio.com/api/v2/mods/init_publish
   ```

   Читать ответ так: `UnknownMod` / `ModAlreadyExists` — ключ валиден и usage
   на месте; `Forbidden` — у ключа нет этого usage; `InvalidApiKey` — ключ
   не тот или удалён. Ни один из трёх запросов ничего не создаёт: мод
   появляется только после второго шага с загрузкой zip.

8. Проверь Node и npm (инструменты репозитория на TypeScript в strict-режиме):

   ```bash
   node -v && npm -v
   ```

9. Установи зависимости репозитория:

   ```bash
   npm ci
   ```

10. Поставь интерпретатор Lua — он нужен для Lua-тестов модов
    (`npm run check:mod -- <mod-key>`):

    ```bash
    brew install lua            # macOS
    sudo pacman -S lua zip jq   # Arch Linux
    lua -v
    ```

    Версия будет новее той, что исполняет игра: Factorio 2.x работает на
    патченном Lua 5.2, а формул `lua@5.2` и `lua@5.3` в Homebrew нет.
    Разницу диалектов ловит отдельная проверка в `npm run validate` —
    convention `testing`, раздел «Диалект Lua». Если нужен другой бинарь
    (например, `luajit`), путь задаётся переменной `LUA_BIN`. В Arch есть
    отдельный пакет `lua52`, но тесты проекта идут на системном `lua` на
    обеих платформах — решение и его граница в том же разделе convention.

11. Поставь расширения редактора — раздел «Редактор» ниже.

12. Настрой страховочный hook по manual `setup-safety-hooks.md`.

13. Прогони стенд тестов внутри игры — заодно это проверит, что инструменты
    видят игру:

    ```bash
    npm run test:ingame
    ```

    При первом прогоне CLI `factorio-test` качает с портала мод
    `factorio-test` и для этого ищет вход в аккаунт: переменные
    `FACTORIO_USERNAME` / `FACTORIO_TOKEN`, иначе `player-data.json` в
    каталоге игры и в каталоге данных игры. На macOS файл лежит в каталоге
    данных и находится сам. Steam-сборка под Linux хранит его в Steam Cloud,
    `~/.local/share/Steam/userdata/<steam-id>/427520/remote/player-data.json`,
    где CLI не ищет, — креды передаются переменными на один прогон:

    ```bash
    PD=$(ls ~/.local/share/Steam/userdata/*/427520/remote/player-data.json | head -1)
    FACTORIO_USERNAME=$(jq -r '."service-username"' "$PD") \
    FACTORIO_TOKEN=$(jq -r '."service-token"' "$PD") \
      npm run test:ingame
    ```

    Скачанный мод остаётся в `.work/ingame-stand/data/mods/`, следующие
    прогоны идут без кредов. Токен не кладётся ни в `.env.local`, ни в
    репозиторий. Проверено 2026-10-30 на 2.1.24 (`linux64`, `steam`).

## Редактор

Официального расширения от Wube не существует. Ставим два:

- **`justarandomgeek.factoriomod-debug`** — «Factorio Modding Tool Kit»
  (FMTK), де-факто стандарт экосистемы, MIT. Опирается на встроенный в игру
  `LuaDebugAdapter`, то есть на механизм самой Factorio.
- **`tangzx.emmylua`** — language server для Lua, которому FMTK отдаёт
  сгенерированные определения API под установленную версию игры.

Важно про второй: в старых версиях FMTK интеграция шла через `sumneko.lua`,
в текущих — через EmmyLua. На этом легко споткнуться, потому что
`sumneko.lua` на порядок популярнее в общем Lua-мире. При связке FMTK +
EmmyLua отдельное `svizzini.factorio-lua-api-autocomplete` не нужно: FMTK сам
генерирует определения.

Что даёт FMTK поверх инструментов репозитория:

- отладчик с точками останова в Lua работающей игры и профайлер — это
  невозможно воспроизвести своими скриптами;
- валидация `info.json` по схеме и языковая поддержка `locale` и
  `changelog.txt`: ошибки формата (99 дефисов, отступы 2/4/6) видны прямо при
  вводе, а не только на `npm run validate`;
- задачи `Package`, `Upload`, `Details` в панели «Factorio Mod Packages»;
  API-ключ хранится в хранилище ключей системы (Keychain на macOS, Secret
  Service — GNOME Keyring или KWallet — на Linux) либо берётся из
  переменной `FACTORIO_UPLOAD_API_KEY`.

## Если забыт e-mail аккаунта

Аккаунт на сайте и аккаунт на форуме — разные; мод-портал использует логин
сайта. Для выпуска API-ключей нужен вход именно на сайт, поэтому без него
публикация невозможна (локальная разработка и прогон — возможны).

Как узнать, под каким аккаунтом ты вообще залогинен:

```bash
# macOS
python3 -c "import json;print(json.load(open('$HOME/Library/Application Support/factorio/player-data.json'))['service-username'])"
# Linux, Steam
jq -r '."service-username"' ~/.local/share/Steam/userdata/*/427520/remote/player-data.json
```

Файл `player-data.json` хранит `service-username` и `service-token` — это
аккаунт, под которым выполнен вход в самой игре. Steam-сборка под Linux
держит его в Steam Cloud, а не в каталоге данных игры. На Windows тот же файл лежит
в `%appdata%\Factorio`, а при установке через Steam его копия — в
`C:\Program Files (x86)\Steam\userdata\<id>\427520\remote`. E-mail там не
хранится, только имя аккаунта.

Дальше по порядку:

1. Попробуй вход на https://factorio.com/login — проверь, предлагается ли там
   вход через Steam. Если да, это обходит пароль целиком, и e-mail будет виден
   на https://factorio.com/profile.
2. Запроси сброс пароля на https://factorio.com/request-password-reset. Письма
   идут **до двух часов**, проверяй папку «Промоакции» и спам. Если форма
   принимает имя аккаунта, а не только e-mail — укажи имя и смотри, в какой
   ящик придёт письмо.
3. Поищи в своих ящиках по словам `factorio` и `factorio.com` — письмо о
   регистрации или подтверждении адреса. Чека о покупке от Wube не будет:
   покупка шла через Steam.
4. Последний и официально описанный путь — письмо на **support@factorio.com**
   с именем аккаунта и Steam ID64 (узнать на https://steamidfinder.com/).
   Справка Wube прямо описывает этот сценарий для проблем с аккаунтом и
   привязкой Steam.

Смежный факт: имя аккаунта можно менять не чаще одного раза в три месяца, на
странице профиля. Мод-портал требует платного членства — при покупке в Steam
аккаунты должны быть связаны на странице профиля.

## Чего в FMTK делать нельзя

Команда FMTK **`Publish`** — всё-в-одном: проверяет отсутствие
незакоммиченных изменений, делает `git commit`, ставит тег, собирает zip,
грузит на портал и **пушит в upstream**. Она выполняет git-операции сама, без
спроса.

Это противоречит правилу проекта: коммиты, теги и пуши делает владелец
руками. Поэтому:

- командой `Publish` не пользуемся;
- пользуемся отдельными задачами `Package`, `Upload`, `Details`;
- либо, если `Publish` всё же понадобится, в `info.json` выставляются
  `package.no_git_tag` и `package.no_git_push`.

## Если что-то пошло не так

- Каталог пользовательских данных не появился → игра ни разу не
  запускалась успешно, либо путь переопределён через
  `config-path.cfg` / `config/config.ini` в каталоге приложения.
- На macOS правка содержимого `factorio.app` для переноса каталога данных
  ломается о Gatekeeper: модифицированный бандл система может отказаться
  запускать. Переносить каталог данных без явной необходимости не стоит.
- API-ключ не создаётся → проверь, что игра привязана к аккаунту (при покупке
  через Steam нужно связать Steam ID с аккаунтом factorio.com).

## Дальше

- Прогнать мод локально → `test-mod-locally.md`.
- Опубликовать новый мод → `publish-new-mod.md`.
