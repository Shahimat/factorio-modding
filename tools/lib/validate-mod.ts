import { join, relative } from 'node:path';

import { validateChangelog } from './changelog.ts';
import { THUMBNAIL_SIZE } from './conventions.ts';
import { validateInfoJson, type InfoJson } from './info-json.ts';
import { error, warning, type Problem } from './problems.ts';
import {
  fileExists,
  isExpectedThumbnailSize,
  readPngSize,
  REPO_ROOT,
} from './packages.ts';

export interface ModValidation {
  readonly info: InfoJson | null;
  readonly problems: readonly Problem[];
}

/**
 * Полная проверка одного пакета мода: info.json, changelog.txt, обязательные
 * файлы и сверка версии changelog с версией релиза.
 */
export async function validateMod(modDir: string): Promise<ModValidation> {
  const problems: Problem[] = [];
  const rel = relative(REPO_ROOT, modDir);

  const { info, problems: infoProblems } = await validateInfoJson(
    modDir,
    REPO_ROOT,
  );
  problems.push(...infoProblems);

  const changelog = await validateChangelog(modDir, REPO_ROOT);
  problems.push(...changelog.problems);

  if (!changelog.present) {
    problems.push(
      warning(
        join(rel, 'changelog.txt'),
        'changelog.txt отсутствует — история версий не будет видна в браузере модов',
      ),
    );
  } else if (info !== null) {
    const top = changelog.versions[0];
    if (top !== undefined && top !== info.version) {
      problems.push(
        error(
          join(rel, 'changelog.txt'),
          `верхняя секция changelog ${top} не совпадает с "version" = ${info.version} в info.json`,
        ),
      );
    }
  }

  const thumbnailPath = join(modDir, 'thumbnail.png');
  if (!(await fileExists(thumbnailPath))) {
    problems.push(
      warning(join(rel, 'thumbnail.png'), 'thumbnail.png отсутствует'),
    );
  } else {
    const size = await readPngSize(thumbnailPath);
    if (size === null) {
      problems.push(
        error(join(rel, 'thumbnail.png'), 'файл не является корректным PNG'),
      );
    } else if (!isExpectedThumbnailSize(size)) {
      problems.push(
        warning(
          join(rel, 'thumbnail.png'),
          `размер ${size.width}x${size.height}, ожидается ${THUMBNAIL_SIZE}x${THUMBNAIL_SIZE}`,
        ),
      );
    }
  }

  if (!(await fileExists(join(modDir, 'LICENSE')))) {
    problems.push(
      error(
        join(rel, 'LICENSE'),
        'LICENSE обязателен в составе мода, см. convention licensing',
      ),
    );
  }

  return { info, problems };
}
