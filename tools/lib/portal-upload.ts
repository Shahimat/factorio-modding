/**
 * Чистые функции публикации релиза на мод-портал: разбор строк env-файла,
 * путь к zip, разбор ответа `init_upload`, сверка списка релизов публичного
 * API с ожидаемой версией. Сети здесь нет — её делает `tools/publish.ts`,
 * поэтому модуль покрывается юнит-тестами без запросов (convention
 * `testing`). Сценарий — behavior `release-published-via-api`.
 */
import { join } from 'node:path';

/** Переменная окружения с API-ключом мод-портала. */
export const API_KEY_VAR = 'FACTORIO_UPLOAD_API_KEY';

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}

/**
 * Разбор одной строки env-файла вида `[export ]KEY=value`. Понимает кавычки
 * вокруг значения и `\r` от файлов, правленных в Windows. Пустые строки,
 * комментарии и строки без `=` дают `null`; встроенных комментариев нет —
 * всё после первого `=` считается значением.
 */
export function parseEnvLine(
  line: string,
): { key: string; value: string } | null {
  const trimmed = line.trim();
  if (trimmed === '' || trimmed.startsWith('#')) return null;
  const eq = trimmed.indexOf('=');
  if (eq <= 0) return null;
  const key = trimmed.slice(0, eq).trim().replace(/^export\s+/, '');
  if (key === '' || /\s/.test(key)) return null;
  let value = trimmed.slice(eq + 1).trim();
  const quote = value.at(0);
  if (
    (quote === '"' || quote === "'") &&
    value.length > 1 &&
    value.at(-1) === quote
  ) {
    value = value.slice(1, -1);
  }
  return { key, value };
}

/** Значение ключа из текста env-файла; пустые значения пропускаются. */
export function envValueFor(text: string, key: string): string | null {
  for (const line of text.split('\n')) {
    const entry = parseEnvLine(line);
    if (entry !== null && entry.key === key && entry.value !== '') {
      return entry.value;
    }
  }
  return null;
}

/**
 * Ключ публикации: сначала окружение, затем тексты env-файлов по порядку
 * (`.env.local`, `.env`). Нечитаемый файл — `null` и пропускается. Не нашёлся
 * вовсе — `null`; сообщение пользователю собирает вызывающий.
 */
export function resolveApiKey(input: {
  env: string | undefined;
  files: readonly (string | null)[];
  key: string;
}): string | null {
  const fromEnv = input.env?.trim();
  if (fromEnv !== undefined && fromEnv !== '') return fromEnv;
  for (const text of input.files) {
    if (text === null) continue;
    const value = envValueFor(text, input.key);
    if (value !== null) return value;
  }
  return null;
}

/** Путь к собранному zip релиза: `dist/<name>_<version>.zip` — так кладёт `pack.ts`. */
export function releaseZipPath(
  distDir: string,
  release: { name: string; version: string },
): string {
  return join(distDir, `${release.name}_${release.version}.zip`);
}

/**
 * Разбор ответа `init_upload`. Портал отдаёт адрес загрузки в поле
 * `upload_url` — поле `url` в ответе не существует, и брать его было бы
 * ошибкой. Нет поля — `null`, вызывающий покажет ошибку портала.
 */
export function parseInitUploadResponse(body: string): {
  uploadUrl: string;
} | null {
  let parsed: unknown;
  try {
    parsed = JSON.parse(body);
  } catch {
    return null;
  }
  if (!isRecord(parsed)) return null;
  const uploadUrl = parsed['upload_url'];
  return typeof uploadUrl === 'string' && uploadUrl !== ''
    ? { uploadUrl }
    : null;
}

/** Успех загрузки архива — JSON `{"success": true}`. */
export function isUploadSuccess(body: string): boolean {
  try {
    const parsed: unknown = JSON.parse(body);
    return isRecord(parsed) && parsed['success'] === true;
  } catch {
    return false;
  }
}

export interface PortalErrorInfo {
  /** Код ошибки портала: InvalidApiKey, InvalidModRelease, Forbidden… */
  readonly code: string;
  /** Текст сервера: поле `message` либо кусочек сырого тела. */
  readonly detail: string;
}

const DETAIL_MAX = 200;

/**
 * Разбор ответа портала с ошибкой. Не-JSON (страница прокси, HTML) тоже
 * осмыслен: код `Unknown` и кусочек тела, по которому ошибку можно найти.
 */
export function parsePortalError(body: string): PortalErrorInfo {
  let code = '';
  let message = '';
  try {
    const parsed: unknown = JSON.parse(body);
    if (isRecord(parsed)) {
      if (typeof parsed['error'] === 'string') code = parsed['error'];
      if (typeof parsed['message'] === 'string') message = parsed['message'];
    }
  } catch {
    // тело не JSON — покажем кусочек сырого текста
  }
  return {
    code: code === '' ? 'Unknown' : code,
    detail: message !== '' ? message : body.trim().slice(0, DETAIL_MAX),
  };
}

const ERROR_HINTS: Record<string, string> = {
  InvalidApiKey:
    'ключ не принят: проверь FACTORIO_UPLOAD_API_KEY (выдаётся на factorio.com/profile)',
  Forbidden:
    'у ключа нет нужного usage — для релиза нужен ModPortal: Upload Mods',
  InvalidModRelease:
    'портал не принял данные релиза: часто это уже существующая версия на портале',
  InvalidModUpload:
    'zip не той структуры: ровно одна папка верхнего уровня с info.json, пересобери через npm run pack',
  UnknownMod:
    'мода нет на портале: первая публикация — по manual publish-new-mod, не этим скриптом',
  InternalError: 'внутренняя ошибка портала — повтори позже',
  Unknown: 'неизвестная ошибка портала — повтори позже',
};

/** Подсказка по коду ошибки портала; для незнакомых кодов — `null`. */
export function portalErrorHint(code: string): string | null {
  return ERROR_HINTS[code] ?? null;
}

export interface PortalRelease {
  readonly version: string;
  /** Из `info_json` релиза; в ответе поля может не быть. */
  readonly factorioVersion: string | undefined;
}

/**
 * Список релизов из публичного `GET /api/mods/<name>`. Кривой ответ даёт
 * пустой список, а не падение: решение о неуспехе принимает сверка.
 */
export function releasesOf(modResponse: unknown): PortalRelease[] {
  if (!isRecord(modResponse)) return [];
  const releases = modResponse['releases'];
  if (!Array.isArray(releases)) return [];
  const found: PortalRelease[] = [];
  for (const item of releases) {
    if (!isRecord(item)) continue;
    const version = item['version'];
    if (typeof version !== 'string') continue;
    const info = item['info_json'];
    found.push({
      version,
      factorioVersion:
        isRecord(info) && typeof info['factorio_version'] === 'string'
          ? info['factorio_version']
          : undefined,
    });
  }
  return found;
}

export type ReleaseCheck = { ok: true } | { ok: false; reason: string };

/**
 * Сверка списка релизов с ожидаемой версией и `factorio_version` из
 * info.json. Успех — только точное совпадение обоих полей.
 */
export function checkReleasePresent(
  releases: readonly PortalRelease[],
  version: string,
  factorioVersion: string,
): ReleaseCheck {
  const released = releases.find((release) => release.version === version);
  if (released === undefined) {
    const known = releases.map((release) => release.version).join(', ');
    const suffix =
      known === '' ? ' (список релизов пуст)' : ` (на портале: ${known})`;
    return {
      ok: false,
      reason: `версия ${version} не появилась в списке релизов${suffix}`,
    };
  }
  if (released.factorioVersion !== factorioVersion) {
    return {
      ok: false,
      reason: `версия ${version} на портале объявлена для factorio_version "${released.factorioVersion ?? '?'}", в info.json — "${factorioVersion}"`,
    };
  }
  return { ok: true };
}
