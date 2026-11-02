# Отчёт executor — тикет tool-publish-command, run 1

Дата: 2026-11-03 · checkout: /mnt/dev/my/prj/factorio-modding (worktree владельца, дерево было чистым)

```yaml
done:
  - tools/publish.ts — команда публикации: resolveModDirs (приставка shm- опциональна) → ключ → init_upload (форма mod=<name>, Bearer) → POST upload_url с file=@zip → {"success": true} → проверка публичным GET /api/mods/<name> с 5 попытками и паузой 4 с
  - package.json — скрипт "publish:mod": "node tools/publish.ts" рядом с check:mod
  - ключ FACTORIO_UPLOAD_API_KEY: окружение → .env.local → .env в корне; строки вида [export ]KEY=value, кавычки, \r; ключ не печатается нигде (в сообщениях только HTTP-код и текст сервера); нет ключа — подсказка factorio.com/profile + usage ModPortal: Upload Mods + куда положить
  - нет zip dist/<name>_<version>.zip — ошибка с подсказкой «сначала собери его: npm run pack -- <info.name>»
  - ошибки портала: HTTP-код + код ошибки сервера (InvalidApiKey, InvalidModRelease, Forbidden…) + message/кусок тела + подсказка по известным кодам; UnknownMod отсылает к manual publish-new-mod
  - git-действий и edit_details в инструменте нет — только релиз (init_upload + загрузка + публичная проверка)
  - tools/lib/portal-upload.ts — чистые функции: parseEnvLine, envValueFor, resolveApiKey, releaseZipPath, parseInitUploadResponse (поле upload_url, не url), isUploadSuccess, parsePortalError, portalErrorHint, releasesOf, checkReleasePresent
  - tools/lib/portal-upload.test.ts — 30 тестов node:test на фейковых значениях, сеть не дёргается; регрессия на путаницу url/upload_url
checks:
  - npm run typecheck — зелёный
  - npm test — 186 pass / 0 fail (из них 30 новых portal-upload)
  - npm run check-secrets — ок (первый прогон поймал присваивание `const apiKey = resolveApiKey({` по правилу secret-assignment, переименовано в portalKey)
  - npm run check (typecheck + test + check-secrets + check-docs + validate) — зелёный целиком
  - npm run publish:mod -- no-such-mod — «нет таких модов в mods/: no-such-mod», exit 1, до сети и ключа не доходит
  - npm run publish:mod (без аргументов) — подсказка с форматом запуска, exit 1
  - реальная публикация не запускалась — 0.1.1 shm-orbital-logistics уже на портале, повтор даст InvalidModRelease; живая проверка — с оператором
left:
  - живой прогон публикации на новой версии — только по явному «да» оператора (convention publication)
risks:
  - verifyRelease ждёт до ~20 с (5 попыток × 4 с); browse-API портала кэшируется — при большем лаге инструмент отдаст «не удалось подтвердить… проверь вручную», релиз при этом загружен
  - тестируемый разбор env покрывает export/кавычки/\r; inline-комментарии в значении (KEY=value # комм) не поддержаны сознательно — всё после = считается значением
refs:
  - tools/publish.ts, tools/lib/portal-upload.ts, tools/lib/portal-upload.test.ts, package.json
  - судейские прогоны: .ops/tool-publish-command/verdicts/1.yml (run 1, pass), счётчик — goals/toolchain.expect.json
```

## Судейский прогон

- Judge run 1 (свежая сессия, протокол `.agents/skills/judge/SKILL.md`): `status: pass`, все 6 crit — `pass`, замечаний нет — `.ops/tool-publish-command/verdicts/1.yml`; счётчик — `goals/toolchain.expect.json` (`run: 1`, только пункты этого тикета).
- Run 2 не запускался: негативных пунктов нет, дорабатывать нечего (по skill judge run 2 — только после замечаний run 1).
- Примечание для оператора: в дереве есть предсуществующие незакоммиченные правки не из этого тикета — `CHANGELOG.md`, `context/conventions/publication.yml`, `docs/behavior/release-published-via-api.yml`, `docs/entities/orbital-logistics.yml`, блок тикета в `goals/toolchain.expect.ts`. Это работа оператора (запрет /tmp-скриптов и заведение тикета), judge и executor их не трогали.

## Evidence для librarian

- Новая команда `npm run publish:mod -- <mod-key>` (приставку shm- можно опустить): публикует `dist/<name>_<version>.zip` — init_upload → POST на `upload_url` → проверка публичным API с повторами.
- Ключ `FACTORIO_UPLOAD_API_KEY` ищется: переменная окружения → `.env.local` → `.env` в корне; формат строки `[export ]KEY=value`, кавычки и `\r` допустимы; ключ не печатается.
- Публикация мода (edit_details, первая публикация нового мода) инструментом не покрывается — только релиз существующего.
