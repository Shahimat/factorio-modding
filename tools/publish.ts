#!/usr/bin/env node
/**
 * Публикует собранный релиз мода на мод-портал: `init_upload` → загрузка zip
 * на выданный `upload_url` → проверка публичным API, что версия появилась с
 * ожидаемой `factorio_version`. Запуск: `npm run publish:mod -- <mod-key>`,
 * приставку shm- можно опустить. Архив должен быть собран заранее —
 * `npm run pack -- <mod-key>` кладёт `dist/<name>_<version>.zip`.
 *
 * Ключ `FACTORIO_UPLOAD_API_KEY` берётся из окружения, затем из `.env.local`
 * и `.env` в корне; нигде не печатается. Первая публикация нового мода — не
 * здесь (manual `publish-new-mod`); правок страницы мода и git-действий в
 * инструменте нет. Покрывает behavior `release-published-via-api`.
 */
import { readFile } from 'node:fs/promises';
import { basename, join, relative } from 'node:path';

import { validateInfoJson } from './lib/info-json.ts';
import { countErrors, formatProblem } from './lib/problems.ts';
import { fileExists, REPO_ROOT, resolveModDirs } from './lib/packages.ts';
import {
  API_KEY_VAR,
  checkReleasePresent,
  isUploadSuccess,
  parseInitUploadResponse,
  parsePortalError,
  portalErrorHint,
  releasesOf,
  releaseZipPath,
  resolveApiKey,
} from './lib/portal-upload.ts';

const PORTAL = 'https://mods.factorio.com';
const INIT_UPLOAD_URL = `${PORTAL}/api/v2/mods/releases/init_upload`;
/** Порядок поиска ключа после окружения: локальный файл сильнее общего. */
const ENV_FILES = ['.env.local', '.env'] as const;
/** Browse-API портала кэшируется — релиз появляется в нём не мгновенно. */
const VERIFY_ATTEMPTS = 5;
const VERIFY_PAUSE_MS = 4000;

function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

/** Сообщение об отказе портала: HTTP-код, текст сервера, подсказка. */
function portalFailure(what: string, status: number, body: string): Error {
  const { code, detail } = parsePortalError(body);
  const parts = [`${what}: портал ответил ${status} (${code})`];
  if (detail !== '') parts.push(detail);
  const hint = portalErrorHint(code);
  if (hint !== null) parts.push(hint);
  return new Error(parts.join(' — '));
}

async function post(
  url: string,
  init: RequestInit,
  what: string,
): Promise<Response> {
  try {
    return await fetch(url, init);
  } catch (cause: unknown) {
    const detail = cause instanceof Error ? cause.message : String(cause);
    throw new Error(`${what}: портал недоступен (${detail})`);
  }
}

/** Шаг 1: получить upload_url. Форма `mod=<name>`, авторизация Bearer. */
async function initUpload(
  modName: string,
  portalKey: string,
): Promise<string> {
  const form = new FormData();
  form.append('mod', modName);
  const res = await post(
    INIT_UPLOAD_URL,
    {
      method: 'POST',
      headers: { Authorization: `Bearer ${portalKey}` },
      body: form,
    },
    'init_upload',
  );
  const text = await res.text();
  const parsed = parseInitUploadResponse(text);
  if (parsed === null) throw portalFailure('init_upload', res.status, text);
  return parsed.uploadUrl;
}

/** Шаг 2: загрузить zip на upload_url. Успех — `{"success": true}`. */
async function uploadZip(uploadUrl: string, zipPath: string): Promise<void> {
  const form = new FormData();
  form.append('file', new Blob([await readFile(zipPath)]), basename(zipPath));
  const res = await post(
    uploadUrl,
    { method: 'POST', body: form },
    'загрузка zip',
  );
  const text = await res.text();
  if (!isUploadSuccess(text)) {
    throw portalFailure('загрузка zip', res.status, text);
  }
}

/** Шаг 3: публичный API должен показать версию с ожидаемой factorio_version. */
async function verifyRelease(
  modName: string,
  version: string,
  factorioVersion: string,
): Promise<void> {
  const url = `${PORTAL}/api/mods/${modName}`;
  let reason = '';
  for (let attempt = 1; attempt <= VERIFY_ATTEMPTS; attempt += 1) {
    if (attempt > 1) await sleep(VERIFY_PAUSE_MS);
    try {
      const res = await fetch(url);
      const text = await res.text();
      if (!res.ok) {
        reason = `публичный API ответил ${res.status}`;
        continue;
      }
      const verdict = checkReleasePresent(
        releasesOf(JSON.parse(text)),
        version,
        factorioVersion,
      );
      if (verdict.ok) {
        console.log(
          `${modName}: версия ${version} подтверждена на портале (factorio_version ${factorioVersion})`,
        );
        return;
      }
      reason = verdict.reason;
    } catch {
      reason = 'публичный API вернул не JSON или недоступен';
    }
  }
  throw new Error(
    `не удалось подтвердить релиз за ${VERIFY_ATTEMPTS} попыток: ${reason} — проверь вручную ${url}`,
  );
}

/** Ключ публикации: окружение, затем `.env.local`, затем `.env` в корне. */
async function loadApiKey(): Promise<string> {
  const files = await Promise.all(
    ENV_FILES.map(async (name) => {
      try {
        return await readFile(join(REPO_ROOT, name), 'utf8');
      } catch {
        return null; // файла нет — штатный случай
      }
    }),
  );
  const portalKey = resolveApiKey({
    env: process.env[API_KEY_VAR],
    files,
    key: API_KEY_VAR,
  });
  if (portalKey === null) {
    throw new Error(
      `нет ключа ${API_KEY_VAR}: задай его в окружении или строкой export ${API_KEY_VAR}=… в ${ENV_FILES.join(' или ')} в корне репозитория; ` +
        'ключ выдаётся на https://factorio.com/profile (API keys), нужен usage ModPortal: Upload Mods',
    );
  }
  return portalKey;
}

async function publishMod(modDir: string, portalKey: string): Promise<void> {
  const name = basename(modDir);
  const { info, problems } = await validateInfoJson(modDir, REPO_ROOT);
  for (const problem of problems) {
    console.log(formatProblem(problem));
  }
  if (countErrors(problems) > 0 || info === null) {
    throw new Error(
      `${name}: публикация остановлена — сначала исправь ошибки в info.json`,
    );
  }

  const zipPath = releaseZipPath(join(REPO_ROOT, 'dist'), info);
  if (!(await fileExists(zipPath))) {
    throw new Error(
      `${name}: нет архива ${relative(REPO_ROOT, zipPath)} — сначала собери его: npm run pack -- ${info.name}`,
    );
  }

  console.log(
    `${name}: релиз ${info.version} для factorio_version ${info.factorio_version}, запрашиваю upload_url`,
  );
  const uploadUrl = await initUpload(info.name, portalKey);
  console.log(`${name}: загружаю ${relative(REPO_ROOT, zipPath)}`);
  await uploadZip(uploadUrl, zipPath);
  console.log(`${name}: портал принял архив, подтверждаю релиз через публичный API`);
  await verifyRelease(info.name, info.version, info.factorio_version);
}

async function main(): Promise<void> {
  const args = process.argv.slice(2);
  if (args.length === 0) {
    throw new Error(
      'не задан мод: `npm run publish:mod -- <mod-key>`; приставку shm- можно опустить',
    );
  }

  const { dirs, unknown } = await resolveModDirs(args);
  if (unknown.length > 0) {
    throw new Error(`нет таких модов в mods/: ${unknown.join(', ')}`);
  }

  const portalKey = await loadApiKey();
  for (const modDir of dirs) {
    await publishMod(modDir, portalKey);
  }
}

try {
  await main();
} catch (cause: unknown) {
  console.error(cause instanceof Error ? cause.message : String(cause));
  process.exitCode = 1;
}
