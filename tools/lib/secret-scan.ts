/**
 * Чистая часть проверки секретов: разбор одной строки и решение по имени
 * файла. Отделено от работы с git и файловой системой, чтобы покрываться
 * юнит-тестами — convention `testing`.
 */
import { extname } from 'node:path';

import { error, type Problem } from './problems.ts';
import {
  ALLOWED_EMAILS,
  BINARY_EXTENSIONS,
  EMAIL_PATTERN,
  FORBIDDEN_FILE_PATTERNS,
  HASH_KEY_PATTERN,
  LONG_BASE64_PATTERN,
  LONG_HEX_PATTERN,
  looksLikeToken,
  PLACEHOLDER_PATTERN,
  SECRET_ASSIGNMENT_PATTERN,
  SECRET_RULES,
} from './secret-rules.ts';

const SHA_LABEL_PATTERN = /\bSHA(?:-?256)?\b/i;

/** Только само значение поля хеша, не остальные значения той же строки. */
function isHashFieldValue(line: string, offset: number): boolean {
  for (const key of line.matchAll(new RegExp(HASH_KEY_PATTERN.source, 'gi'))) {
    const start = key.index + key[0].length;
    const value = /^\s*["'`]?([^\s"'`,;]+)/.exec(line.slice(start));
    if (value?.[1] === undefined) continue;
    if (!/^(?:[a-f0-9]{30,}|sha(?:1|256|384|512)-[a-z0-9+/=]+)$/i.test(value[1])) continue;
    const valueStart = start + value[0].indexOf(value[1]);
    if (offset >= valueStart && offset < valueStart + value[1].length) return true;
  }
  return false;
}

/** Публичный commit pin только указанного upstream, не URL целиком. */
function isPublicCommit(line: string, offset: number, value: string): boolean {
  if (value.length !== 40) return false;
  const urls = /(?<![\w/?=&:%.-])https:\/\/raw\.githubusercontent\.com\/Shahimat\/ai-prompts\/([a-fA-F0-9]{40})\/[^\s<>"'`]+/g;
  for (const url of line.matchAll(urls)) {
    const commitOffset = url.index + url[0].indexOf('/ai-prompts/') + '/ai-prompts/'.length;
    if (offset === commitOffset) return true;
  }
  return false;
}

/** Колонка checksum в Markdown; label сам по себе ничего не исключает. */
function checksumOffset(file: string, line: string, context: boolean): number | undefined {
  if (extname(file).toLowerCase() !== '.md') return undefined;
  if (!context && !SHA_LABEL_PATTERN.test(line)) return undefined;
  const column = /^\s*`?([a-f0-9]{64})(?:`(?=[\s.]|$)|(?=\s|$))/i.exec(line);
  return column?.[1] === undefined ? undefined : line.indexOf(column[1]);
}

/** Находки по одной строке файла. */
export function scanLine(
  file: string,
  line: string,
  lineNo: number,
  checksumContext = false,
): Problem[] {
  const problems: Problem[] = [];

  for (const rule of SECRET_RULES) {
    if (rule.pattern.test(line)) {
      problems.push(error(file, `${rule.message} [${rule.id}]`, lineNo));
    }
  }

  const assignment = SECRET_ASSIGNMENT_PATTERN.exec(line);
  if (assignment !== null) {
    const raw = (assignment[2] ?? '').trim().replace(/[,;]$/, '');
    const value = raw.replace(/^["']|["']$/g, '').trim();
    const looksSecret =
      value.length >= 12 && !PLACEHOLDER_PATTERN.test(value);
    // Строка документации вида «ключ хранится в переменной X» значения не
    // содержит: отсекаем по пробелу внутри значения.
    const isProse = /\s/.test(value);
    if (looksSecret && !isProse) {
      problems.push(
        error(
          file,
          `присваивание секретного поля литералу: "${assignment[1] ?? ''}" [secret-assignment]`,
          lineNo,
        ),
      );
    }
  }

  for (const match of line.matchAll(EMAIL_PATTERN)) {
    const email = match[0];
    if (!(ALLOWED_EMAILS as readonly string[]).includes(email)) {
      problems.push(
        error(file, `адрес e-mail вне белого списка: ${email} [email]`, lineNo),
      );
    }
  }

  // Строка YAML вида «имя: <чистый hex>» — SHA-чекпоинт контракта v3:
  // sync.contract.parts и manifest'ы модулей держат хеш значением
  // именованного ключа. Секретные ключи всё равно ловит правило
  // присваивания выше.
  const isHashValueLine =
    /^\s*["']?[\w.-]+["']?\s*:\s*["']?[A-Fa-f0-9]{30,}["']?,?\s*$/.test(line);

  if (!isHashValueLine) {
    const checksum = checksumOffset(file, line, checksumContext);
    for (const match of line.matchAll(LONG_HEX_PATTERN)) {
      if (isHashFieldValue(line, match.index) ||
          (match.index === checksum && match[0].length === 64) ||
          isPublicCommit(line, match.index, match[0])) continue;
      problems.push(
        error(
          file,
          `длинная hex-строка вне поля хеша: ${match[0].slice(0, 12)}… [long-hex]`,
          lineNo,
        ),
      );
    }
    for (const match of line.matchAll(LONG_BASE64_PATTERN)) {
      if (isHashFieldValue(line, match.index) ||
          (match.index === checksum && match[0].length === 64) ||
          isPublicCommit(line, match.index, match[0])) continue;
      if (!looksLikeToken(match[0])) continue;
      problems.push(
        error(
          file,
          `длинная base64-подобная строка вне поля хеша: ${match[0].slice(0, 12)}… [long-base64]`,
          lineNo,
        ),
      );
    }
  }

  return problems;
}

/** Все находки по тексту файла. */
export function scanText(file: string, text: string): Problem[] {
  const problems: Problem[] = [];
  const lines = text.split('\n');
  let fence: string | undefined;
  let checksumBlock = false;
  for (const [index, line] of lines.entries()) {
    const marker = /^\s*(`{3,}|~{3,})(.*)$/.exec(line);
    const nearbyLabel = lines.slice(Math.max(0, index - 2), index)
      .some((previous) => SHA_LABEL_PATTERN.test(previous));
    if (marker !== null) {
      const delimiter = marker[1] ?? '';
      if (fence === undefined) {
        fence = delimiter;
        checksumBlock = nearbyLabel && /^\s*(?:text)?\s*$/.test(marker[2] ?? '');
      } else if (delimiter[0] === fence[0] && delimiter.length >= fence.length) {
        fence = undefined;
        checksumBlock = false;
      }
    }
    problems.push(...scanLine(file, line, index + 1,
      fence === undefined ? nearbyLabel : checksumBlock));
  }
  return problems;
}

/** Находка по самому имени файла, если такому файлу не место в git. */
export function checkFileName(relPath: string): Problem | null {
  for (const forbidden of FORBIDDEN_FILE_PATTERNS) {
    if (forbidden.pattern.test(relPath)) {
      return error(relPath, `${forbidden.message} [forbidden-file]`);
    }
  }
  return null;
}

/** Файлы, которые не сканируются построчно. */
export function isBinaryPath(relPath: string): boolean {
  return (BINARY_EXTENSIONS as readonly string[]).includes(extname(relPath));
}
