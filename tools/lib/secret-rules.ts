/**
 * Образцы чувствительных данных для `check-secrets`. Правило —
 * `context/conventions/secrets.yml`.
 *
 * Набор образцов заведомо неполон: он ловит известные виды секретов. Новый
 * вид он не знает, поэтому ответственность за правило остаётся на человеке и
 * агенте, которые правят файлы.
 */

export interface SecretRule {
  readonly id: string;
  readonly pattern: RegExp;
  readonly message: string;
  readonly severity: 'error' | 'warning';
}

/**
 * Публичные адреса, опубликованные самой Wube в справке. Всё остальное,
 * похожее на e-mail, считается утечкой.
 */
export const ALLOWED_EMAILS = [
  'support@factorio.com',
  'factorio@factorio.com',
] as const;

/**
 * Ключи, значение которых — хеш, а не секрет. Длинные hex-строки рядом с
 * ними пропускаются.
 */
export const HASH_KEY_PATTERN =
  /(^|[\s"'_-])(integrity|checksum|hash|sha|sha1|sha256|sha512|index_sha|synced_sha)["']?\s*[:=]/i;

/** Значения-заглушки: не секрет, а место под него. */
export const PLACEHOLDER_PATTERN =
  /^(\s*|\.{3}|<[^>]*>|\$\{?[A-Za-z_][A-Za-z0-9_]*\}?|["']{2}|null|changeme|your[-_]?\w*)$/i;

/** Файлы, которые не сканируем построчно. */
export const BINARY_EXTENSIONS = [
  '.png',
  '.jpg',
  '.jpeg',
  '.gif',
  '.ico',
  '.zip',
  '.pdf',
  '.woff',
  '.woff2',
  '.ttf',
] as const;

/** Пути, которые обязаны быть скрыты .gitignore. */
export const MUST_BE_IGNORED = [
  '.env',
  '.env.local',
  'secrets/key.txt',
  'node_modules/x',
  'dist/x',
  // Рабочее пространство пруфов и ревью, convention `spec-program`.
  // Внутри — логи игры и скриншоты с абсолютными путями.
  '.work/proofs/program/goal/d1-log.txt',
  '.work/review/goal/round-01.md',
] as const;

/** Пути, которые обязаны НЕ игнорироваться. */
export const MUST_NOT_BE_IGNORED = ['.env.example'] as const;

export const SECRET_RULES: readonly SecretRule[] = [
  {
    id: 'private-key-block',
    pattern: /-----BEGIN (?:[A-Z ]+ )?PRIVATE KEY-----/,
    message: 'блок приватного ключа',
    severity: 'error',
  },
  {
    id: 'github-token',
    pattern: /\b(?:ghp|gho|ghu|ghs|ghr)_[A-Za-z0-9]{16,}|\bgithub_pat_[A-Za-z0-9_]{20,}/,
    message: 'токен GitHub',
    severity: 'error',
  },
  {
    id: 'slack-token',
    pattern: /\bxox[baprs]-[A-Za-z0-9-]{8,}/,
    message: 'токен Slack',
    severity: 'error',
  },
  {
    id: 'openai-token',
    pattern: /\bsk-[A-Za-z0-9]{20,}/,
    message: 'ключ вида sk-…',
    severity: 'error',
  },
  {
    id: 'aws-access-key',
    pattern: /\bAKIA[0-9A-Z]{16}\b/,
    message: 'AWS access key id',
    severity: 'error',
  },
  {
    id: 'google-api-key',
    pattern: /\bAIza[0-9A-Za-z_-]{35}\b/,
    message: 'ключ Google API',
    severity: 'error',
  },
  {
    id: 'npm-auth-token',
    pattern: /_authToken\s*=/,
    message: 'учётные данные реестра пакетов',
    severity: 'error',
  },
  {
    id: 'bearer-literal',
    // Литерал после Bearer — секрет. Подстановка переменной — норма.
    pattern: /Bearer\s+(?!\$|<|\.\.\.)[A-Za-z0-9._~+/-]{12,}/,
    message: 'литеральный токен в заголовке Authorization',
    severity: 'error',
  },
  {
    id: 'url-embedded-credentials',
    pattern: /https?:\/\/[^/\s:@]+:[^/\s@]+@/,
    message: 'логин и пароль внутри URL',
    severity: 'error',
  },
  {
    id: 'home-absolute-path',
    pattern: /\/(?:Users|home)\/(?!<)[A-Za-z0-9._-]+\//,
    message: 'абсолютный путь с именем пользователя — замени на ~ или $HOME',
    severity: 'error',
  },
];

/**
 * Присваивание секретного по смыслу ключа непустому литералу.
 * Отдельно от SECRET_RULES, потому что требует разбора значения.
 *
 * Границы заданы через `(?<![A-Za-z0-9])`, а не `\b`: подчёркивание —
 * символ слова, поэтому `\bapi` не совпал бы в `FACTORIO_UPLOAD_API_KEY`.
 */
export const SECRET_ASSIGNMENT_PATTERN =
  /(?<![A-Za-z0-9])(api[_-]?key|apikey|access[_-]?token|auth[_-]?token|service[_-]?token|secret|password|passwd|pwd|credentials?|private[_-]?key)(?![A-Za-z0-9])["']?\s*[:=]\s*(.+)$/i;

export const EMAIL_PATTERN =
  /[A-Za-z0-9._%+-]+@[A-Za-z0-9](?:[A-Za-z0-9.-]*[A-Za-z0-9])?\.[A-Za-z]{2,}/g;

/**
 * Порог 30, а не 32: токен сервиса Factorio из `player-data.json` — ровно
 * 30 hex-символов (проверено 2026-10-04 на живом файле). На 32 он
 * проскакивал.
 */
export const LONG_HEX_PATTERN = /\b[A-Fa-f0-9]{30,}\b/g;

/**
 * Длинная base64-подобная строка — типичная форма токена.
 *
 * Слеш из алфавита исключён сознательно: с ним правило ловило файловые пути
 * и base64 из `integrity` в `package-lock.json`. Плата — токены со слешем
 * этим правилом не ловятся; их закрывают правило присваивания и образцы
 * известных префиксов.
 */
export const LONG_BASE64_PATTERN = /\b[A-Za-z0-9+]{40,}={0,2}\b/g;

/**
 * Base64-подобное считается токеном только при смешанном регистре с цифрой —
 * иначе под правило попадают длинные английские идентификаторы.
 */
export function looksLikeToken(value: string): boolean {
  return (
    /[a-z]/.test(value) && /[A-Z]/.test(value) && /[0-9]/.test(value)
  );
}

/** Имена файлов, которые не должны попадать под контроль git. */
export const FORBIDDEN_FILE_PATTERNS: readonly {
  pattern: RegExp;
  message: string;
}[] = [
  {
    pattern: /player-data[^/]*\.json$/i,
    message: 'файл player-data содержит service-token и в git попадать не должен',
  },
  {
    pattern: /^(?:.*\/)?\.env(?!\.example$)/,
    message: 'файл .env под контролем git — проверь .gitignore',
  },
  {
    pattern: /\.(key|pem|p12|pfx)$/i,
    message: 'файл ключа или сертификата',
  },
];
