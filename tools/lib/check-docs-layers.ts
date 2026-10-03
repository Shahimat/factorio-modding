import { stringify } from 'yaml';

import {
  asRecord,
  asString,
  asStringArray,
  DIRS,
  listBaseNames,
  loadYamlDir,
  type LoadedYaml,
} from './docs-model.ts';
import { error, warning, type Problem } from './problems.ts';

const MAX_ENTITIES_PER_NAMESPACE = 7;
const MAX_BEHAVIORS_PER_NAMESPACE = 12;

function idOf(item: LoadedYaml): string | null {
  return asString(item.data['id']);
}

function expectedFileName(id: string): string {
  return `${id}.yml`;
}

/** Слова длиннее трёх символов из kebab-case ключа фичи. */
function featureWords(feature: string): string[] {
  return feature.split(/[-_]/).filter((w) => w.length > 3);
}

export interface LayerCheck {
  readonly problems: Problem[];
  readonly entityIds: string[];
  readonly behaviorIds: string[];
  readonly manualNames: string[];
  readonly conventionKeys: string[];
}

export async function checkLayers(): Promise<LayerCheck> {
  const problems: Problem[] = [];

  const entities = await loadYamlDir(DIRS.entities);
  const behaviors = await loadYamlDir(DIRS.behaviors);
  const conventions = await loadYamlDir(DIRS.conventions);
  problems.push(
    ...entities.problems,
    ...behaviors.problems,
    ...conventions.problems,
  );

  const manualNames = await listBaseNames(DIRS.manuals, '.md');

  const entityById = new Map<string, LoadedYaml>();
  for (const item of entities.items) {
    const id = idOf(item);
    if (id === null) {
      problems.push(error(item.file, 'нет поля "id"'));
      continue;
    }
    if (item.fileName !== expectedFileName(id)) {
      problems.push(
        error(item.file, `имя файла не совпадает с id "${id}"`),
      );
    }
    if (entityById.has(id)) {
      problems.push(error(item.file, `id "${id}" уже занят другим файлом`));
      continue;
    }
    entityById.set(id, item);
  }

  const behaviorById = new Map<string, LoadedYaml>();
  for (const item of behaviors.items) {
    const id = idOf(item);
    if (id === null) {
      problems.push(error(item.file, 'нет поля "id"'));
      continue;
    }
    if (item.fileName !== expectedFileName(id)) {
      problems.push(
        error(item.file, `имя файла не совпадает с id "${id}"`),
      );
    }
    if (behaviorById.has(id)) {
      problems.push(error(item.file, `id "${id}" уже занят другим файлом`));
      continue;
    }
    behaviorById.set(id, item);
  }

  const conventionKeys: string[] = [];
  for (const item of conventions.items) {
    const key = asString(item.data['key']);
    if (key === null) {
      problems.push(error(item.file, 'нет поля "key"'));
      continue;
    }
    if (item.fileName !== `${key}.yml`) {
      problems.push(
        error(item.file, `имя файла не совпадает с key "${key}"`),
      );
    }
    if (!asString(item.data['rule'])) {
      problems.push(error(item.file, 'нет непустого поля "rule"'));
    }
    conventionKeys.push(key);
  }

  // Двусторонние ссылки entity ↔ behavior.
  for (const [id, item] of entityById) {
    for (const ref of asStringArray(item.data['behaviors'])) {
      const target = behaviorById.get(ref);
      if (target === undefined) {
        problems.push(
          error(item.file, `ссылка на несуществующий behavior "${ref}"`),
        );
        continue;
      }
      if (!asStringArray(target.data['entities']).includes(id)) {
        problems.push(
          error(
            item.file,
            `односторонняя ссылка на "${ref}": обратной ссылки на "${id}" нет`,
          ),
        );
      }
    }
  }
  for (const [id, item] of behaviorById) {
    for (const ref of asStringArray(item.data['entities'])) {
      const target = entityById.get(ref);
      if (target === undefined) {
        problems.push(
          error(item.file, `ссылка на несуществующий entity "${ref}"`),
        );
        continue;
      }
      if (!asStringArray(target.data['behaviors']).includes(id)) {
        problems.push(
          error(
            item.file,
            `односторонняя ссылка на "${ref}": обратной ссылки на "${id}" нет`,
          ),
        );
      }
    }
  }

  // Ссылки на manuals и conventions.
  for (const item of [...entityById.values(), ...behaviorById.values()]) {
    for (const ref of asStringArray(item.data['manuals'])) {
      if (!manualNames.includes(ref)) {
        problems.push(
          error(item.file, `ссылка на несуществующий manual "${ref}"`),
        );
      }
    }
    for (const ref of asStringArray(item.data['conventions'])) {
      if (!conventionKeys.includes(ref)) {
        problems.push(
          error(item.file, `ссылка на несуществующую convention "${ref}"`),
        );
      }
    }
  }

  // Механика verified.
  for (const [id, item] of behaviorById) {
    const verified = item.data['verified'];
    const verifiedAt = item.data['verified_at'];
    const note = asString(item.data['verified_note']);

    if (typeof verified !== 'boolean') {
      problems.push(error(item.file, 'поле "verified" должно быть true/false'));
    } else if (verified && (verifiedAt === null || verifiedAt === undefined)) {
      problems.push(error(item.file, 'verified: true без "verified_at"'));
    } else if (
      !verified &&
      verifiedAt !== null &&
      verifiedAt !== undefined
    ) {
      problems.push(
        error(item.file, '"verified_at" заполнен при verified: false'),
      );
    }

    if (note === null || note.trim() === '') {
      problems.push(
        error(item.file, 'пустой "verified_note": причина статуса обязательна'),
      );
    }

    const scenarios = item.data['scenarios'];
    if (!Array.isArray(scenarios) || scenarios.length === 0) {
      problems.push(error(item.file, 'нет непустого списка "scenarios"'));
    } else {
      for (const [index, raw] of scenarios.entries()) {
        const scenario = asRecord(raw);
        if (scenario === null) {
          problems.push(
            error(item.file, `сценарий ${index + 1} не объект`),
          );
          continue;
        }
        for (const field of ['given', 'when', 'then'] as const) {
          if (!asString(scenario[field])) {
            problems.push(
              error(item.file, `сценарий ${index + 1}: нет поля "${field}"`),
            );
          }
        }
      }
    }
    void id;
  }

  // features_enabled отражён хотя бы в одной связанной behavior.
  for (const item of entityById.values()) {
    const linked = asStringArray(item.data['behaviors'])
      .map((ref) => behaviorById.get(ref))
      .filter((b): b is LoadedYaml => b !== undefined);
    const haystack = linked.map((b) => stringify(b.data)).join('\n').toLowerCase();
    for (const feature of asStringArray(item.data['features_enabled'])) {
      const words = featureWords(feature);
      const reflected =
        words.length === 0 || words.some((w) => haystack.includes(w));
      if (!reflected) {
        problems.push(
          warning(
            item.file,
            `features_enabled "${feature}" не отражён ни в одной связанной behavior`,
          ),
        );
      }
    }
  }

  // Размеры namespace.
  const countByNamespace = (items: Iterable<LoadedYaml>): Map<string, number> => {
    const counts = new Map<string, number>();
    for (const item of items) {
      const ns = asString(item.data['namespace']);
      if (ns === null) {
        problems.push(error(item.file, 'нет поля "namespace"'));
        continue;
      }
      counts.set(ns, (counts.get(ns) ?? 0) + 1);
    }
    return counts;
  };
  for (const [ns, count] of countByNamespace(entityById.values())) {
    if (count > MAX_ENTITIES_PER_NAMESPACE) {
      problems.push(
        warning(
          'context/project.yml',
          `namespace "${ns}": ${count} entities, порог ${MAX_ENTITIES_PER_NAMESPACE} — обсудить дробление`,
        ),
      );
    }
  }
  for (const [ns, count] of countByNamespace(behaviorById.values())) {
    if (count > MAX_BEHAVIORS_PER_NAMESPACE) {
      problems.push(
        warning(
          'context/project.yml',
          `namespace "${ns}": ${count} behaviors, порог ${MAX_BEHAVIORS_PER_NAMESPACE} — обсудить дробление`,
        ),
      );
    }
  }

  return {
    problems,
    entityIds: [...entityById.keys()],
    behaviorIds: [...behaviorById.keys()],
    manualNames,
    conventionKeys,
  };
}
