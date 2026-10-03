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

/** Находки по одной строке файла. */
export function scanLine(
  file: string,
  line: string,
  lineNo: number,
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

  if (!HASH_KEY_PATTERN.test(line)) {
    for (const match of line.matchAll(LONG_HEX_PATTERN)) {
      problems.push(
        error(
          file,
          `длинная hex-строка вне поля хеша: ${match[0].slice(0, 12)}… [long-hex]`,
          lineNo,
        ),
      );
    }
    for (const match of line.matchAll(LONG_BASE64_PATTERN)) {
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
  for (const [index, line] of text.split('\n').entries()) {
    problems.push(...scanLine(file, line, index + 1));
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
