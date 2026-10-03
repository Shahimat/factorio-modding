#!/usr/bin/env node
/**
 * Проверка внутренней непротиворечивости проектной документации.
 * Запуск: `npm run check-docs`.
 *
 * Покрывает машинно проверяемую часть чек-листа из
 * `context/conventions/consistency.yml`. Часть «проверяется только головой»
 * этот инструмент не заменяет: зелёный прогон означает лишь, что формальные
 * связи между слоями целы.
 */
import { checkLayers } from './lib/check-docs-layers.ts';
import {
  checkGoals,
  checkIndex,
  checkModules,
  checkProject,
} from './lib/check-docs-context.ts';
import { countErrors, formatProblem, type Problem } from './lib/problems.ts';

async function main(): Promise<void> {
  const layers = await checkLayers();

  const sections: Array<{ title: string; problems: readonly Problem[] }> = [
    { title: 'слои docs/', problems: layers.problems },
    { title: 'context/index.yml', problems: await checkIndex(layers) },
    { title: 'context/project.yml', problems: await checkProject() },
    { title: 'context/modules/', problems: await checkModules() },
    { title: 'context/views/ (цели)', problems: await checkGoals() },
  ];

  let errorsTotal = 0;
  let warningsTotal = 0;

  for (const section of sections) {
    const errors = countErrors(section.problems);
    const warnings = section.problems.length - errors;
    errorsTotal += errors;
    warningsTotal += warnings;

    const status = errors > 0 ? 'ОШИБКИ' : warnings > 0 ? 'замечания' : 'ок';
    console.log(`${section.title}: ${status}`);
    for (const problem of section.problems) {
      console.log(formatProblem(problem));
    }
  }

  console.log(
    `\nСлои: entities ${layers.entityIds.length}, behaviors ${layers.behaviorIds.length}, manuals ${layers.manualNames.length}, conventions ${layers.conventionKeys.length}`,
  );
  console.log(`Итого: ошибок ${errorsTotal}, замечаний ${warningsTotal}`);

  if (errorsTotal > 0) {
    process.exitCode = 1;
  }
}

await main();
