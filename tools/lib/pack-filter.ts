/**
 * Решение «попадает ли путь в zip релиза». Чистая логика, вынесена из
 * `tools/pack.ts`: ошибка здесь означает либо лишние файлы на портале, либо
 * недостающий модуль в архиве, поэтому правило должно быть покрыто тестами.
 *
 * Состав исключений — `PACK_EXCLUDED` и `PACK_EXCLUDED_SUFFIXES`, причины —
 * conventions `testing` и `mod-naming`, `repo_only` в entity `mod-package`.
 */

import { PACK_EXCLUDED, PACK_EXCLUDED_SUFFIXES } from './conventions.ts';

/**
 * `rel` — путь относительно корня пакета мода, в posix- или win-разделителях.
 * Пустая строка означает сам корень и исключением не является.
 */
export function isExcludedFromPack(rel: string): boolean {
  if (rel === '') return false;

  const segments = rel.split(/[\\/]/);
  if (segments.some((s) => (PACK_EXCLUDED as readonly string[]).includes(s))) {
    return true;
  }
  return PACK_EXCLUDED_SUFFIXES.some((suffix) => rel.endsWith(suffix));
}
