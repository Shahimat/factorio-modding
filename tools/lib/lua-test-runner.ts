/**
 * Разбор результата Lua-харнесса. Логика чистая: обнаружение файлов и запуск
 * интерпретатора живут в `tools/lua-test.ts`, сюда приходит готовый вывод.
 *
 * Формат вывода раннера (`tools/lua/run.lua`) собственный, не TAP:
 *
 *     TEST ok <имя>
 *     TEST fail <имя> :: <сообщение>
 *     TOTAL <прошло> <упало>
 *
 * Своя разметка вместо TAP потому, что разбирать её нужно одним регулярным
 * выражением, а совместимость с внешними потребителями не нужна.
 */

import { LUA_TEST_SUFFIX } from './conventions.ts';
import { error, type Problem } from './problems.ts';

export interface LuaTestCase {
  readonly name: string;
  readonly ok: boolean;
  readonly message?: string;
}

export interface LuaTestOutput {
  readonly cases: readonly LuaTestCase[];
  /** `null`, если строки `TOTAL` в выводе не было. */
  readonly passed: number | null;
  readonly failed: number | null;
}

export function isLuaTestFile(path: string): boolean {
  return path.endsWith(LUA_TEST_SUFFIX);
}

const CASE_PATTERN = /^TEST (ok|fail) (.+?)(?: :: ([\s\S]*))?$/;
const TOTAL_PATTERN = /^TOTAL (\d+) (\d+)$/;

export function parseHarnessOutput(stdout: string): LuaTestOutput {
  const cases: LuaTestCase[] = [];
  let passed: number | null = null;
  let failed: number | null = null;

  for (const raw of stdout.split('\n')) {
    const line = raw.replace(/\r$/, '');

    const total = TOTAL_PATTERN.exec(line);
    if (total !== null) {
      passed = Number(total[1]);
      failed = Number(total[2]);
      continue;
    }

    const match = CASE_PATTERN.exec(line);
    if (match === null) continue;

    const name = match[2] ?? '';
    const message = match[3];
    cases.push(
      match[1] === 'ok'
        ? { name, ok: true }
        : message === undefined
          ? { name, ok: false }
          : { name, ok: false, message },
    );
  }

  return { cases, passed, failed };
}

/**
 * Находки по одному прогону. Отдельно от разбора, потому что молчаливый
 * упавший интерпретатор — тоже находка: падение `lua` до первой строки
 * вывода выглядело бы как «тестов нет, значит всё хорошо».
 */
export function luaRunProblems(
  file: string,
  parsed: LuaTestOutput,
  exitCode: number | null,
  stderr: string,
): Problem[] {
  const problems: Problem[] = [];

  for (const testCase of parsed.cases) {
    if (testCase.ok) continue;
    const detail =
      testCase.message === undefined ? '' : `: ${testCase.message}`;
    problems.push(error(file, `тест упал — ${testCase.name}${detail}`));
  }

  const firstStderrLine = stderr.trim().split('\n')[0] ?? '';

  if (parsed.passed === null || parsed.failed === null) {
    const tail = firstStderrLine === '' ? '' : `: ${firstStderrLine}`;
    problems.push(
      error(
        file,
        `раннер не досчитал прогон до конца — нет итоговой строки${tail}`,
      ),
    );
    return problems;
  }

  const counted = parsed.cases.length;
  if (counted !== parsed.passed + parsed.failed) {
    problems.push(
      error(
        file,
        `вывод обрезан: строк с тестами ${counted}, в итоге заявлено ${parsed.passed + parsed.failed}`,
      ),
    );
  }

  if (parsed.failed === 0 && exitCode !== 0) {
    const tail = firstStderrLine === '' ? '' : `: ${firstStderrLine}`;
    problems.push(
      error(
        file,
        `все тесты прошли, но код возврата ${exitCode === null ? 'неизвестен' : exitCode}${tail}`,
      ),
    );
  }

  return problems;
}
