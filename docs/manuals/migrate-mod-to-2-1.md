# Перевести мод на дорожку Factorio 2.1

## Когда использовать

Когда чужой мод под Factorio 2.0 форкается или берётся за основу и
переводится на 2.1. Проект поддерживает только 2.1, так что своего кода
под 2.0 не бывает — manual нужен для чужого.

Правила дорожек — `context/conventions/factorio-version-track.yml`.

## Что требуется

- Установленный клиент Factorio 2.1. Сейв, открытый в 2.1, может не
  открыться в 2.0 — бэкапь сейвы заранее.
- Исходники мода под 2.0.

## Ключевой факт

`factorio_version` указывает **ровно одну** мажорную версию. «И 2.0, и 2.1» в
одном релизе невозможно, даже если мод фактически работает в обеих. Поэтому
поддержка двух версий — это два потока релизов одного мода на портале; игра
сама выбирает последний релиз с подходящим `factorio_version`.

Так живёт Krastorio2: релизы `2.0.19` (`factorio_version: 2.0`) и
`2.1.1`…`2.1.3` (`factorio_version: 2.1`) лежат вперемешку в одном списке
релизов. Проект так не делает: у наших модов релизы только под 2.1.

## Шаги

1. Поменяй `factorio_version` на `"2.1"`.

2. Проверь актуальную версию игры и прогони мод на ней:

   ```bash
   curl -q -fsSL https://factorio.com/api/latest-releases -o /tmp/factorio-latest-releases.json
   cat /tmp/factorio-latest-releases.json
   ```

3. Прогон по `test-mod-locally.md` целиком, включая
   `--check-unused-prototype-data`: переименованные или удалённые свойства
   прототипов проявляются именно там.

4. Просмотри лог на предупреждения об устаревших API — ошибки стадии данных
   и runtime уходят в `factorio-current.log`.

5. Добавь секцию в `changelog.txt` с категорией `Compatibility` или
   `Modding` — явно укажи, что релиз под Factorio 2.1.

6. Выпусти релиз по `release-mod.md`. Версия мода остаётся в своей
   нумерации, в дорожку её не кодируем.

7. Проверь, что на портале появился релиз именно с `factorio_version: 2.1`,
   и что релизов под другие версии у мода нет:

   ```bash
   curl -q -fsSL "https://mods.factorio.com/api/mods/shm-<mod-key>" -o /tmp/factorio-mod-releases.json
   python3 -c 'import json,collections; j=json.load(open("/tmp/factorio-mod-releases.json")); \
print(collections.Counter(r["info_json"]["factorio_version"] for r in j["releases"]))'
   ```

## Если что-то пошло не так

- Ошибка загрузки или устаревший API → вернись к шагам 3–4 и точному
  сообщению в `factorio-current.log`; не считай смену `factorio_version`
  доказательством совместимости.
- На портале нет релиза 2.1 → проверь результат публикации по `release-mod.md`;
  не публикуй повторно без проверки версии и подтверждения владельца.
