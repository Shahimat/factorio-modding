import { readdir, readFile } from 'node:fs/promises';
import { join } from 'node:path';

import { parse } from 'yaml';

import { checkDod } from './dod.ts';
import {
  asRecord,
  asString,
  asStringArray,
  DIRS,
  listBaseNames,
  loadYamlDir,
  type LoadedYaml,
  type YamlRecord,
} from './docs-model.ts';
import { fileExists, REPO_ROOT } from './packages.ts';
import { error, warning, type Problem } from './problems.ts';
import type { LayerCheck } from './check-docs-layers.ts';

const MAX_TASK_LENGTH = 200;
const PRIORITIES = ['blocker', 'high', 'medium', 'low'] as const;

const INDEX_FILE = 'context/index.yml';
const PROJECT_FILE = 'context/project.yml';

/** Все строковые значения `id:` и `key:` из index.yml, в порядке появления. */
function collectIndexRefs(text: string): { ids: string[]; keys: string[] } {
  const ids = [...text.matchAll(/^\s*-?\s*id:\s*(\S+)\s*$/gm)].map(
    (m) => m[1] ?? '',
  );
  const keys = [...text.matchAll(/^\s*-?\s*key:\s*(\S+)\s*$/gm)].map(
    (m) => m[1] ?? '',
  );
  return { ids: ids.filter(Boolean), keys: keys.filter(Boolean) };
}

export async function checkIndex(layers: LayerCheck): Promise<Problem[]> {
  const problems: Problem[] = [];
  const path = join(REPO_ROOT, 'context', 'index.yml');
  let text: string;
  try {
    text = await readFile(path, 'utf8');
  } catch {
    problems.push(error(INDEX_FILE, 'файл отсутствует'));
    return problems;
  }

  const refs = collectIndexRefs(text);
  const expectedIds = [
    ...layers.entityIds,
    ...layers.behaviorIds,
    ...layers.manualNames,
  ];

  for (const id of expectedIds) {
    if (!refs.ids.includes(id)) {
      problems.push(error(INDEX_FILE, `не отражён в индексе: ${id}`));
    }
  }
  for (const key of layers.conventionKeys) {
    if (!refs.keys.includes(key)) {
      problems.push(error(INDEX_FILE, `convention не в индексе: ${key}`));
    }
  }
  for (const id of refs.ids) {
    if (!expectedIds.includes(id)) {
      problems.push(
        error(INDEX_FILE, `в индексе есть "${id}", но такого файла нет`),
      );
    }
  }

  // Файлы ТЗ должны быть зарегистрированы, см. convention spec-intake.
  const specs = await listBaseNames(DIRS.specs, '.md');
  for (const spec of specs) {
    if (!text.includes(`specs/${spec}.md`)) {
      problems.push(
        error(INDEX_FILE, `файл specs/${spec}.md не зарегистрирован в индексе`),
      );
    }
  }

  return problems;
}

export async function checkProject(): Promise<Problem[]> {
  const problems: Problem[] = [];
  const path = join(REPO_ROOT, 'context', 'project.yml');
  let data: YamlRecord | null;
  try {
    data = asRecord(parse(await readFile(path, 'utf8')));
  } catch (cause: unknown) {
    const detail = cause instanceof Error ? cause.message : String(cause);
    problems.push(error(PROJECT_FILE, `не читается или не парсится: ${detail}`));
    return problems;
  }
  if (data === null) {
    problems.push(error(PROJECT_FILE, 'ожидается YAML-объект'));
    return problems;
  }

  const sync = asRecord(data['sync']);
  if (sync === null) {
    problems.push(error(PROJECT_FILE, 'нет блока "sync"'));
    return problems;
  }
  for (const field of ['index_source', 'index_sha'] as const) {
    if (!asString(sync[field])) {
      problems.push(error(PROJECT_FILE, `sync: нет поля "${field}"`));
    }
  }
  const contract = asRecord(sync['contract']);
  if (contract === null) {
    problems.push(error(PROJECT_FILE, 'нет блока "sync.contract"'));
  } else {
    for (const field of ['key', 'synced_sha'] as const) {
      if (!asString(contract[field])) {
        problems.push(
          error(PROJECT_FILE, `sync.contract: нет поля "${field}"`),
        );
      }
    }
  }

  const namespaces = asRecord(data['namespaces']);
  if (namespaces === null || Object.keys(namespaces).length === 0) {
    problems.push(error(PROJECT_FILE, 'нет непустого блока "namespaces"'));
  }

  return problems;
}

export async function checkModules(): Promise<Problem[]> {
  const problems: Problem[] = [];
  const { items, problems: loadProblems } = await loadYamlDir(DIRS.modules);
  problems.push(...loadProblems);

  for (const item of items) {
    const key = asString(item.data['key']);
    if (key === null) {
      problems.push(error(item.file, 'нет поля "key"'));
      continue;
    }
    if (item.fileName !== `${key}.yml`) {
      problems.push(error(item.file, `имя файла не совпадает с key "${key}"`));
    }
    const provides = asRecord(item.data['provides']);
    if (provides === null) {
      problems.push(error(item.file, 'нет блока "provides"'));
      continue;
    }
    for (const relPath of asStringArray(provides['files'])) {
      if (!(await fileExists(join(REPO_ROOT, relPath)))) {
        problems.push(
          error(
            item.file,
            `provides.files указывает на отсутствующий файл "${relPath}"`,
          ),
        );
      }
    }
  }
  return problems;
}

interface GoalFile {
  readonly key: string;
  readonly file: string;
  readonly dependsOn: string[];
  readonly tasks: string[];
  readonly isProgram: boolean;
  /** `key` программы для подцели, иначе `null`. */
  readonly program: string | null;
}

export async function checkGoals(layers: LayerCheck): Promise<Problem[]> {
  const problems: Problem[] = [];
  const indexPath = join(DIRS.views, 'goals.yaml');
  const indexRel = 'context/views/goals.yaml';

  let indexData: YamlRecord | null;
  try {
    indexData = asRecord(parse(await readFile(indexPath, 'utf8')));
  } catch (cause: unknown) {
    const detail = cause instanceof Error ? cause.message : String(cause);
    problems.push(error(indexRel, `не читается или не парсится: ${detail}`));
    return problems;
  }
  if (indexData === null) {
    problems.push(error(indexRel, 'ожидается YAML-объект'));
    return problems;
  }

  const rawGoals = indexData['goals'];
  const order: string[] = [];
  if (!Array.isArray(rawGoals)) {
    problems.push(error(indexRel, 'нет списка "goals"'));
  } else {
    for (const raw of rawGoals) {
      const entry = asRecord(raw);
      const key = entry === null ? null : asString(entry['key']);
      if (key === null) {
        problems.push(error(indexRel, 'запись индекса без "key"'));
        continue;
      }
      order.push(key);
      const subgoals = entry === null ? undefined : entry['subgoals'];
      if (Array.isArray(subgoals)) {
        for (const sub of subgoals) {
          const subEntry = asRecord(sub);
          const subKey = subEntry === null ? null : asString(subEntry['key']);
          if (subKey !== null) order.push(subKey);
        }
      }
    }
  }

  let fileNames: string[];
  try {
    fileNames = await readdir(DIRS.views);
  } catch {
    problems.push(error('context/views/', 'каталог отсутствует'));
    return problems;
  }

  const goals: GoalFile[] = [];
  for (const fileName of fileNames.sort()) {
    if (!fileName.startsWith('goal--') && !fileName.startsWith('program--')) {
      continue;
    }
    const rel = `context/views/${fileName}`;
    let data: YamlRecord | null;
    try {
      data = asRecord(parse(await readFile(join(DIRS.views, fileName), 'utf8')));
    } catch (cause: unknown) {
      const detail = cause instanceof Error ? cause.message : String(cause);
      problems.push(error(rel, `не парсится: ${detail}`));
      continue;
    }
    if (data === null) {
      problems.push(error(rel, 'ожидается YAML-объект'));
      continue;
    }
    const key = asString(data['key']);
    if (key === null) {
      problems.push(error(rel, 'нет поля "key"'));
      continue;
    }
    const isProgram = fileName.startsWith('program--');
    const prefix = isProgram ? 'program--' : 'goal--';
    if (fileName !== `${prefix}${key}.yaml`) {
      problems.push(error(rel, `имя файла не совпадает с key "${key}"`));
    }

    // Подцель программы объявляет принадлежность полем `program`,
    // convention `goals`.
    const program = asString(data['program']);
    if (program !== null && isProgram) {
      problems.push(
        error(rel, 'файл программы не может сам ссылаться на программу'),
      );
    }
    problems.push(
      ...checkDod(data, {
        file: rel,
        isProgram,
        isSubgoal: program !== null,
        behaviorIds: layers.behaviorIds,
        stage: asString(data['stage']),
      }),
    );

    const status = asString(data['status']);
    if (status === null || !['active', 'planned', 'paused'].includes(status)) {
      problems.push(
        error(rel, 'поле "status" должно быть active / planned / paused'),
      );
    }

    const tasksRecord = asRecord(data['tasks']);
    const tasks: string[] = [];
    if (tasksRecord === null) {
      problems.push(error(rel, 'нет блока "tasks"'));
    } else {
      for (const priority of PRIORITIES) {
        if (!(priority in tasksRecord)) {
          problems.push(
            error(rel, `нет секции приоритета "${priority}" (пустая — ок)`),
          );
        }
      }
      for (const [section, value] of Object.entries(tasksRecord)) {
        if (!(PRIORITIES as readonly string[]).includes(section)) {
          problems.push(
            error(rel, `секция "${section}" вне набора приоритетов`),
          );
          continue;
        }
        for (const task of asStringArray(value)) {
          tasks.push(task);
          if (task.length > MAX_TASK_LENGTH) {
            problems.push(
              warning(
                rel,
                `задача ${task.length} символов, порог ${MAX_TASK_LENGTH} — пересобрать в ближайшую фазу docs`,
              ),
            );
          }
        }
      }
    }

    goals.push({
      key,
      file: rel,
      dependsOn: asStringArray(data['depends_on']),
      tasks,
      isProgram,
      program,
    });
  }

  // Подцель ссылается на существующую программу.
  const programKeys = new Set(
    goals.filter((g) => g.isProgram).map((g) => g.key),
  );
  for (const goal of goals) {
    if (goal.program !== null && !programKeys.has(goal.program)) {
      problems.push(
        error(goal.file, `program: нет программы с key "${goal.program}"`),
      );
    }
  }

  const keys = new Set(goals.map((g) => g.key));
  for (const key of order) {
    if (!keys.has(key)) {
      problems.push(error(indexRel, `в индексе есть "${key}", но файла нет`));
    }
  }
  for (const goal of goals) {
    if (!order.includes(goal.key)) {
      problems.push(error(goal.file, `цель "${goal.key}" нет в индексе`));
    }
  }

  // Осиротевшие зависимости, циклы, приоритет против зависимости.
  const byKey = new Map(goals.map((g) => [g.key, g]));
  for (const goal of goals) {
    for (const dep of goal.dependsOn) {
      if (!byKey.has(dep)) {
        problems.push(
          error(goal.file, `depends_on ссылается на несуществующую цель "${dep}"`),
        );
        continue;
      }
      const depIndex = order.indexOf(dep);
      const selfIndex = order.indexOf(goal.key);
      if (depIndex >= 0 && selfIndex >= 0 && depIndex > selfIndex) {
        problems.push(
          error(
            goal.file,
            `зависит от "${dep}", но "${dep}" стоит в индексе ниже — приоритет против зависимости`,
          ),
        );
      }
    }
  }

  const visiting = new Set<string>();
  const done = new Set<string>();
  const hasCycle = (key: string): boolean => {
    if (visiting.has(key)) return true;
    if (done.has(key)) return false;
    visiting.add(key);
    for (const dep of byKey.get(key)?.dependsOn ?? []) {
      if (byKey.has(dep) && hasCycle(dep)) return true;
    }
    visiting.delete(key);
    done.add(key);
    return false;
  };
  for (const goal of goals) {
    if (hasCycle(goal.key)) {
      problems.push(error(goal.file, `цикл depends_on через "${goal.key}"`));
    }
  }

  // Дубли задач между целями.
  const seen = new Map<string, string>();
  for (const goal of goals) {
    for (const task of goal.tasks) {
      const owner = seen.get(task);
      if (owner !== undefined && owner !== goal.key) {
        problems.push(
          error(
            goal.file,
            `задача дублирует задачу цели "${owner}" — должна принадлежать одной, вторая выражает потребность через depends_on`,
          ),
        );
      } else {
        seen.set(task, goal.key);
      }
    }
  }

  return problems;
}

export type { LoadedYaml };
