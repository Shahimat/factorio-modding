/**
 * Проверка исходников модов на диалект Lua. Factorio 2.0 исполняет патченный
 * Lua 5.2, а локально доступен интерпретатор 5.5 — тест на нём не поймает
 * конструкцию, которой в игре нет. Правило и его границы — convention
 * `testing`, раздел «Диалект Lua».
 *
 * Логика чистая: вход — текст файла, выход — находки. Обход каталогов живёт
 * в `validate-mod.ts`.
 */

import { error, type Problem } from './problems.ts';

export interface LuaDialectRule {
  readonly id: string;
  /** Обязательно с флагом `g`: ищем все вхождения, не первое. */
  readonly pattern: RegExp;
  readonly message: string;
}

/**
 * Конструкции, которых в Lua 5.2 нет или которые из него убраны.
 *
 * `~` без `=` — побитовые xor и not из 5.3; `~=` это «не равно» и
 * существует с 5.1, поэтому исключён явно.
 */
export const LUA_DIALECT_RULES: readonly LuaDialectRule[] = [
  {
    id: 'integer-division',
    pattern: /\/\//g,
    message: 'целочисленное деление `//` появилось в Lua 5.3 — используй math.floor(a / b)',
  },
  {
    id: 'bitwise-operator',
    pattern: /<<|>>|&|\||~(?!=)/g,
    message: 'побитовые операторы появились в Lua 5.3 — используй библиотеку bit32',
  },
  {
    id: 'integer-math',
    pattern: /\bmath\.(?:type|ult|tointeger|maxinteger|mininteger)\b/g,
    message: 'целочисленный подраздел math появился в Lua 5.3',
  },
  {
    id: 'table-move',
    pattern: /\btable\.move\b/g,
    message: '`table.move` появился в Lua 5.3',
  },
  {
    id: 'string-pack',
    pattern: /\bstring\.(?:pack|unpack|packsize)\b/g,
    message: '`string.pack` и соседи появились в Lua 5.3',
  },
  {
    id: 'utf8-library',
    pattern: /\butf8\./g,
    message: 'библиотека utf8 появилась в Lua 5.3',
  },
  {
    id: 'variable-attribute',
    pattern: /<\s*(?:const|close)\s*>/g,
    message: 'атрибуты <const> и <close> появились в Lua 5.4',
  },
  {
    id: 'coroutine-close',
    pattern: /\bcoroutine\.close\b/g,
    message: '`coroutine.close` появился в Lua 5.4',
  },
  {
    id: 'removed-in-5-2',
    pattern: /\b(?:setfenv|getfenv|loadstring|newproxy)\s*\(/g,
    message: 'функция убрана в Lua 5.2 и в игре не существует',
  },
  {
    id: 'global-unpack',
    pattern: /(?<![\w.])unpack\s*\(/g,
    message: 'глобальный `unpack` убран в Lua 5.2 — используй table.unpack',
  },
];

/**
 * Заменяет строковые литералы и комментарии пробелами, сохраняя длину и
 * переводы строк. Нужно, чтобы правила не срабатывали на `|` внутри строки
 * или на `//` внутри комментария, и чтобы номера строк остались верными.
 */
export function blankStringsAndComments(text: string): string {
  const out: string[] = [];
  let i = 0;

  /** `[`, затем N знаков `=`, затем `[` — открывающая длинная скобка. */
  const longBracketLevel = (at: number): number | null => {
    if (text[at] !== '[') return null;
    let level = 0;
    let j = at + 1;
    while (text[j] === '=') {
      level += 1;
      j += 1;
    }
    return text[j] === '[' ? level : null;
  };

  /** Копирует область как пробелы, переводы строк оставляет. */
  const blankTo = (from: number, to: number): void => {
    for (let j = from; j < to && j < text.length; j += 1) {
      out.push(text[j] === '\n' ? '\n' : ' ');
    }
  };

  while (i < text.length) {
    const ch = text[i];

    // Комментарий: строчный либо длинный.
    if (ch === '-' && text[i + 1] === '-') {
      const level = longBracketLevel(i + 2);
      if (level !== null) {
        const close = `]${'='.repeat(level)}]`;
        const end = text.indexOf(close, i + 2);
        const stop = end === -1 ? text.length : end + close.length;
        blankTo(i, stop);
        i = stop;
        continue;
      }
      const nl = text.indexOf('\n', i);
      const stop = nl === -1 ? text.length : nl;
      blankTo(i, stop);
      i = stop;
      continue;
    }

    // Длинная строка [[...]] или [=[...]=].
    const level = longBracketLevel(i);
    if (level !== null) {
      const close = `]${'='.repeat(level)}]`;
      const end = text.indexOf(close, i + 1);
      const stop = end === -1 ? text.length : end + close.length;
      blankTo(i, stop);
      i = stop;
      continue;
    }

    // Короткая строка. Незакрытая обрывается переводом строки: в Lua это
    // синтаксическая ошибка, и глотать за ней весь файл нельзя.
    if (ch === '"' || ch === "'") {
      let j = i + 1;
      while (j < text.length && text[j] !== ch && text[j] !== '\n') {
        j += text[j] === '\\' ? 2 : 1;
      }
      const stop = text[j] === ch ? j + 1 : j;
      blankTo(i, stop);
      i = stop;
      continue;
    }

    out.push(ch ?? '');
    i += 1;
  }

  return out.join('');
}

/** Номер строки по смещению в тексте, 1-индексный. */
function lineAt(text: string, index: number): number {
  let line = 1;
  for (let i = 0; i < index && i < text.length; i += 1) {
    if (text[i] === '\n') line += 1;
  }
  return line;
}

/**
 * Находки по одному файлу. Одно правило — одна находка на строку: повтор на
 * той же строке ничего не добавляет к пониманию.
 */
export function scanLuaDialect(file: string, text: string): Problem[] {
  const code = blankStringsAndComments(text);
  const problems: Problem[] = [];
  const seen = new Set<string>();

  for (const rule of LUA_DIALECT_RULES) {
    const pattern = new RegExp(rule.pattern.source, 'g');
    let match: RegExpExecArray | null;
    while ((match = pattern.exec(code)) !== null) {
      const line = lineAt(code, match.index);
      const key = `${rule.id}:${line}`;
      if (seen.has(key)) continue;
      seen.add(key);
      problems.push(error(file, `[${rule.id}] ${rule.message}`, line));
      if (match[0] === '') pattern.lastIndex += 1;
    }
  }

  return problems.sort((a, b) => (a.line ?? 0) - (b.line ?? 0));
}
