import { readFile } from 'node:fs/promises';
import { join } from 'node:path';

import { parse } from 'yaml';

import {
  asRecord,
  asString,
  asStringArray,
  DIRS,
  loadYamlDir,
  type YamlRecord,
} from './docs-model.ts';
import { fileExists, REPO_ROOT } from './packages.ts';
import { error, type Problem } from './problems.ts';

const PROJECT_FILE = 'context/project.yml';

/**
 * Метаданные синхронизации v2; ручной индекс проверяется отдельно.
 */
export async function checkProject(root = REPO_ROOT): Promise<Problem[]> {
  const problems: Problem[] = [];
  const path = join(root, PROJECT_FILE);
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
