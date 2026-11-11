import { readdir, readFile } from 'node:fs/promises';
import { join } from 'node:path';

import { parse } from 'yaml';

import { asRecord, docsDirs, loadYamlDir } from './docs-model.ts';
import { fileExists, REPO_ROOT } from './packages.ts';
import { error, type Problem } from './problems.ts';

async function readYaml(root: string, file: string, problems: Problem[]): Promise<unknown> {
  try {
    return parse(await readFile(join(root, file), 'utf8'));
  } catch (cause: unknown) {
    problems.push(error(file, `не читается или не парсится: ${String(cause)}`));
    return undefined;
  }
}

function nonempty(value: unknown): value is string {
  return typeof value === 'string' && value.trim().length > 0;
}

/** Classic v2 index sections; extension sections (including specs) remain open. */
export async function checkIndex(root = REPO_ROOT): Promise<Problem[]> {
  const problems: Problem[] = [];
  const file = 'context/index.yml';
  const raw = await readYaml(root, file, problems);
  if (raw === undefined) return problems;
  const index = asRecord(raw);
  if (!index) return [error(file, 'ожидается YAML-объект')];
  const namespaces = asRecord(index['namespaces']);
  const conventions = asRecord(index['conventions']);
  if (!namespaces) problems.push(error(file, 'нет блока namespaces'));
  if (!conventions) problems.push(error(file, 'нет блока conventions'));
  const dirs = docsDirs(root);
  const project = asRecord(await readYaml(root, 'context/project.yml', problems));
  const declared = asRecord(project?.['namespaces']);

  for (const section of ['entities', 'behaviors', 'conventions'] as const) {
    const loaded = await loadYamlDir(dirs[section]);
    problems.push(...loaded.problems);
    const byId = new Map(loaded.items.map((item) => [
      item.data[section === 'conventions' ? 'key' : 'id'], item,
    ]));
    const seen = new Set<string>();
    const groups: Array<[string | null, unknown]> = section === 'conventions'
      ? [[null, conventions]]
      : Object.entries(namespaces ?? {}).map(([ns, value]) => [ns, asRecord(value)?.[section]]);
    for (const [ns, rawEntries] of groups) {
      if (rawEntries === undefined || rawEntries === null) continue;
      const entries = asRecord(rawEntries);
      if (!entries) {
        problems.push(error(file, `${ns ?? ''}/${section}: ожидается карта id → описание`));
        continue;
      }
      for (const [id, summary] of Object.entries(entries)) {
        if (!nonempty(summary)) problems.push(error(file, `${section}/${id}: пустое описание`));
        if (seen.has(id)) problems.push(error(file, `${section}/${id}: дубликат id`));
        seen.add(id);
        const item = byId.get(id);
        if (!item) problems.push(error(file, `${section}/${id}: отсутствует файл с таким id`));
        else if (ns !== null && item.data['namespace'] !== ns) {
          problems.push(error(file, `${section}/${id}: namespace не совпадает с ${ns}`));
        }
      }
    }
    for (const id of byId.keys()) {
      if (typeof id === 'string' && !seen.has(id)) {
        problems.push(error(file, `${section}/${id}: нет записи в индексе`));
      }
    }
  }
  const seenManuals = new Set<string>();
  for (const [ns, value] of Object.entries(namespaces ?? {})) {
    if (!declared || !(ns in declared)) problems.push(error(file, `неизвестный namespace ${ns}`));
    const group = asRecord(value);
    if (!group) {
      problems.push(error(file, `${ns}: ожидается объект namespace`));
      continue;
    }
    const rawManuals = group['manuals'];
    if (rawManuals === undefined) continue;
    const manuals = asRecord(rawManuals);
    if (!manuals) {
      problems.push(error(file, `${ns}/manuals: ожидается карта id → описание`));
      continue;
    }
    for (const [id, summary] of Object.entries(manuals)) {
      seenManuals.add(id);
      if (!/^[a-z0-9][a-z0-9-]*$/.test(id) || !(await fileExists(join(dirs.manuals, `${id}.md`)))) {
        problems.push(error(file, `manuals/${id}: отсутствует допустимый файл`));
      }
      if (!nonempty(summary)) problems.push(error(file, `manuals/${id}: пустое описание`));
    }
  }
  for (const name of await readdir(dirs.manuals).catch(() => [] as string[])) {
    if (name.endsWith('.md') && !seenManuals.has(name.slice(0, -3))) {
      problems.push(error(file, `manuals/${name}: нет записи в индексе`));
    }
  }
  return problems;
}

/** Structural checks only: intent conflicts and dependency priority need human review. */
export async function checkQueue(root = REPO_ROOT): Promise<Problem[]> {
  const problems: Problem[] = [];
  const indexFile = 'context/views/goals.yaml';
  const raw = await readYaml(root, indexFile, problems);
  if (raw === undefined) return problems;
  const entries: unknown = Array.isArray(raw) ? raw : asRecord(raw)?.['goals'];
  if (!Array.isArray(entries)) return [error(indexFile, 'ожидается список goals')];
  const nodes = new Map<string, { file: string; deps: string[] }>();
  const files = new Set<string>();
  const statuses = ['active', 'planned', 'paused'];
  const priorities = ['blocker', 'high', 'medium', 'low'];

  async function visit(rawEntry: unknown, parent?: string): Promise<void> {
    const entry = asRecord(rawEntry);
    if (!entry || !nonempty(entry['key']) || !/^[a-z0-9][a-z0-9-]*$/.test(entry['key'])) {
      problems.push(error(indexFile, 'запись: нет допустимого key'));
      return;
    }
    const key = entry['key'];
    const program = entry['kind'] === 'program';
    const expected = `${program ? 'program' : 'goal'}--${key}.yaml`;
    if (entry['file'] !== expected) {
      problems.push(error(indexFile, `${key}: file должен быть ${expected}`));
      return;
    }
    if (nodes.has(key) || files.has(expected)) {
      problems.push(error(indexFile, `${key}: дубликат key/file`));
      return;
    }
    const file = `context/views/${expected}`;
    files.add(expected);
    nodes.set(key, { file, deps: [] });
    if (!statuses.includes(String(entry['status']))) problems.push(error(indexFile, `${key}: недопустимый status`));
    if (!nonempty(entry['one_liner'])) problems.push(error(indexFile, `${key}: нет one_liner`));
    if (entry['kind'] !== undefined && !program) problems.push(error(indexFile, `${key}: неизвестный kind`));
    if (parent && program) problems.push(error(indexFile, `${key}: вложенная программа недопустима`));
    const data = asRecord(await readYaml(root, file, problems));
    if (data) {
      if (data['key'] !== key) problems.push(error(file, 'key не совпадает с индексом'));
      if (data['status'] !== entry['status'] || !statuses.includes(String(data['status']))) {
        problems.push(error(file, 'status не совпадает с индексом или недопустим'));
      }
      if ((data['kind'] === 'program') !== program || (data['kind'] !== undefined && data['kind'] !== 'program')) {
        problems.push(error(file, 'kind не совпадает с индексом'));
      }
      if (data['program'] !== parent) problems.push(error(file, 'program membership не совпадает с индексом'));
      const tasks = asRecord(data['tasks']);
      if (!tasks) problems.push(error(file, 'нет объекта tasks'));
      else {
        for (const priority of Object.keys(tasks)) {
          if (!priorities.includes(priority)) problems.push(error(file, `tasks: неизвестный приоритет ${priority}`));
        }
        for (const priority of priorities) {
          const tasksAtPriority = tasks[priority];
          if (!Array.isArray(tasksAtPriority) || tasksAtPriority.some((task) => !nonempty(task))) {
            problems.push(error(file, `tasks.${priority}: ожидается список непустых строк`));
          }
        }
      }
      const deps = data['depends_on'] ?? [];
      if (!Array.isArray(deps) || deps.some((dep) => !nonempty(dep))) {
        problems.push(error(file, 'depends_on: ожидается список ключей'));
      } else nodes.set(key, { file, deps: deps as string[] });
    } else if (problems.every((problem) => problem.file !== file)) {
      problems.push(error(file, 'ожидается YAML-объект'));
    }
    if (program) {
      if (!Array.isArray(entry['subgoals'])) problems.push(error(indexFile, `${key}: нет списка subgoals`));
      else for (const child of entry['subgoals']) await visit(child, key);
    } else if (entry['subgoals'] !== undefined) problems.push(error(indexFile, `${key}: subgoals только у программы`));
  }
  for (const entry of entries) await visit(entry);
  for (const name of await readdir(join(root, 'context/views')).catch(() => [] as string[])) {
    if (/^(goal|program)--.*\.ya?ml$/.test(name) && !files.has(name)) {
      problems.push(error(indexFile, `${name}: файл не включён в индекс`));
    }
  }
  const active = new Set<string>();
  const visited = new Set<string>();
  function walk(key: string): void {
    const node = nodes.get(key);
    if (!node || visited.has(key)) return;
    if (active.has(key)) {
      problems.push(error(node.file, `цикл depends_on: ${[...active, key].join(' → ')}`));
      return;
    }
    active.add(key);
    for (const dep of node.deps) {
      if (!nodes.has(dep)) problems.push(error(node.file, `depends_on: неизвестный key ${dep}`));
      else walk(dep);
    }
    active.delete(key);
    visited.add(key);
  }
  for (const key of nodes.keys()) walk(key);
  return problems;
}
