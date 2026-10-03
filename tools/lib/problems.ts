/** Единый формат находки валидатора. */
export interface Problem {
  /** Путь к файлу относительно корня репозитория. */
  readonly file: string;
  /** Строка в файле, 1-индексная. Отсутствует, если находка не про строку. */
  readonly line?: number;
  /** Что именно не так, одной фразой. */
  readonly message: string;
  /** `error` ломает сборку, `warning` только печатается. */
  readonly severity: 'error' | 'warning';
}

export function error(file: string, message: string, line?: number): Problem {
  return line === undefined
    ? { file, message, severity: 'error' }
    : { file, line, message, severity: 'error' };
}

export function warning(file: string, message: string, line?: number): Problem {
  return line === undefined
    ? { file, message, severity: 'warning' }
    : { file, line, message, severity: 'warning' };
}

export function formatProblem(p: Problem): string {
  const where = p.line === undefined ? p.file : `${p.file}:${p.line}`;
  const mark = p.severity === 'error' ? 'ошибка' : 'внимание';
  return `  ${mark}  ${where}  ${p.message}`;
}

export function countErrors(problems: readonly Problem[]): number {
  return problems.filter((p) => p.severity === 'error').length;
}
