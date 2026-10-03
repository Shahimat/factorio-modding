/**
 * Проверка блока `dod` в файлах программ и подцелей. Правило — convention
 * `spec-program`: DoD живёт в `context/views/`, у каждого пункта обязателен
 * вид проверки, и хотя бы один пункт подцели должен проверяться машинно.
 *
 * Логика чистая и принимает уже разобранный YAML, поэтому покрывается
 * юнит-тестами, в отличие от самого `check-docs-context.ts`, который привязан
 * к `REPO_ROOT` (известный пробел в convention `testing`).
 */

import { asRecord, asString, type YamlRecord } from './docs-model.ts';
import { error, warning, type Problem } from './problems.ts';

export const DOD_KINDS = ['unit', 'check', 'proof'] as const;
export type DodKind = (typeof DOD_KINDS)[number];

/** Виды, которые проверяются без участия человека. */
export const MACHINE_KINDS: readonly DodKind[] = ['unit', 'check'];

/** `id` попадает в имена файлов пруфов, поэтому без пробелов и регистра. */
const ID_PATTERN = /^[a-z0-9][a-z0-9-]*$/;

/** Корень пруфов; пункт вида `proof` обязан указывать путь внутри него. */
const PROOFS_ROOT = '.work/proofs/';

export interface DodContext {
  /** Путь файла относительно корня репозитория — для сообщений. */
  readonly file: string;
  readonly isProgram: boolean;
  /** Подцель программы: в файле есть поле `program`. */
  readonly isSubgoal: boolean;
  readonly behaviorIds: readonly string[];
}

export function checkDod(data: YamlRecord, ctx: DodContext): Problem[] {
  const problems: Problem[] = [];
  const raw = data['dod'];
  const required = ctx.isProgram || ctx.isSubgoal;

  if (raw === undefined || raw === null) {
    if (required) {
      problems.push(
        error(
          ctx.file,
          'нет блока "dod" — у программы и её подцелей критерии приёмки обязательны, см. convention spec-program',
        ),
      );
    }
    return problems;
  }

  if (!Array.isArray(raw) || raw.length === 0) {
    problems.push(error(ctx.file, '"dod" должен быть непустым списком'));
    return problems;
  }

  const ids = new Set<string>();
  let machine = 0;

  for (const [index, item] of raw.entries()) {
    const at = `dod[${index + 1}]`;
    const entry = asRecord(item);
    if (entry === null) {
      problems.push(error(ctx.file, `${at}: пункт должен быть объектом`));
      continue;
    }

    const id = asString(entry['id']);
    if (id === null || id.trim() === '') {
      problems.push(error(ctx.file, `${at}: нет поля "id"`));
    } else if (!ID_PATTERN.test(id)) {
      problems.push(
        error(
          ctx.file,
          `${at}: "id" = "${id}" — допустимы только строчные латинские буквы, цифры и дефис: id попадает в имена файлов пруфов`,
        ),
      );
    } else if (ids.has(id)) {
      problems.push(error(ctx.file, `${at}: "id" = "${id}" уже занят выше`));
    } else {
      ids.add(id);
    }

    for (const field of ['what', 'how'] as const) {
      const value = asString(entry[field]);
      if (value === null || value.trim() === '') {
        problems.push(error(ctx.file, `${at}: нет непустого поля "${field}"`));
      }
    }

    const kind = asString(entry['kind']);
    if (kind === null) {
      problems.push(error(ctx.file, `${at}: нет поля "kind"`));
    } else if (!(DOD_KINDS as readonly string[]).includes(kind)) {
      problems.push(
        error(
          ctx.file,
          `${at}: "kind" = "${kind}" вне набора ${DOD_KINDS.join(' / ')}`,
        ),
      );
    } else {
      if ((MACHINE_KINDS as readonly string[]).includes(kind)) machine += 1;
      const how = asString(entry['how']) ?? '';
      if (kind === 'proof' && !how.includes(PROOFS_ROOT)) {
        problems.push(
          warning(
            ctx.file,
            `${at}: пункт вида proof не указывает путь внутри ${PROOFS_ROOT} — владельцу негде положить пруф`,
          ),
        );
      }
    }

    const behavior = asString(entry['behavior']);
    if (behavior !== null && !ctx.behaviorIds.includes(behavior)) {
      problems.push(
        error(
          ctx.file,
          `${at}: ссылка на несуществующий behavior "${behavior}"`,
        ),
      );
    }
  }

  // Программа собирает критерии из спеки, в том числе целиком ручные;
  // требование машинной проверки предъявляется именно подцели — она единица
  // работы и приёмки.
  if (ctx.isSubgoal && machine === 0) {
    problems.push(
      error(
        ctx.file,
        'в "dod" нет ни одного пункта вида unit или check — цель, проверяемая только глазами владельца, не заводится (convention spec-program)',
      ),
    );
  }

  return problems;
}
