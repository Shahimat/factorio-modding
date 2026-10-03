/**
 * Единственное место, где живут числовые и строковые значения конвенций
 * проекта. Источник правды — `context/conventions/*.yml`; при их правке
 * этот файл обновляется в той же фазе.
 */

/** Авторская приписка, convention `mod-naming`. */
export const MOD_NAME_PREFIX = 'shm-';

/** Префикс человекочитаемого заголовка, convention `mod-naming`. */
export const MOD_TITLE_PREFIX = 'Shahimat: ';

/** Значение поля `author` в info.json, convention `mod-naming`. */
export const MOD_AUTHOR = 'Shahimat';

/**
 * Ограничения мод-портала на поле `name`: только латиница, цифры, дефис и
 * подчёркивание; длина строго больше 3 и строго меньше 50.
 */
export const MOD_NAME_PATTERN = /^[A-Za-z0-9_-]+$/;
export const MOD_NAME_MIN_LENGTH_EXCLUSIVE = 3;
export const MOD_NAME_MAX_LENGTH_EXCLUSIVE = 50;

/** Игра отклоняет `title` длиннее 100 символов. */
export const MOD_TITLE_MAX_LENGTH = 100;

/** Каждое число версии лежит в диапазоне 0..65535. */
export const VERSION_PART_MAX = 65535;

/**
 * Дорожки релизов, convention `factorio-version-track`. Основная — первая.
 * `factorio_version` указывает ровно одну мажорную версию, из двух чисел.
 */
export const FACTORIO_VERSION_TRACKS = ['2.0', '2.1'] as const;

/** Разделитель секции в changelog.txt — ровно столько дефисов. */
export const CHANGELOG_SEPARATOR_LENGTH = 99;

/**
 * Категории changelog, которые игра распознаёт и выносит перед вкладкой
 * «All». Нераспознанные категории не ошибка, но повод перепроверить опечатку.
 */
export const CHANGELOG_KNOWN_CATEGORIES = [
  'Major Features',
  'Features',
  'Minor Features',
  'Graphics',
  'Sounds',
  'Optimizations',
  'Balancing',
  'Combat Balancing',
  'Circuit Network',
  'Changes',
  'Bugfixes',
  'Modding',
  'Scripting',
  'Gui',
  'Control',
  'Translation',
  'Debug',
  'Ease of use',
  'Info',
  'Locale',
  'Compatibility',
] as const;

/**
 * Каталоги и файлы, которые не попадают в zip релиза. `tests` и
 * `package.json` — по convention `testing`: они лежат в пакете мода, но
 * игроку не нужны, см. `repo_only` в entity `mod-package`.
 */
export const PACK_EXCLUDED = [
  'node_modules',
  '.git',
  '.DS_Store',
  'dist',
  'tests',
  'package.json',
  'package-lock.json',
] as const;

/**
 * Суффиксы путей, которые не попадают в zip. `.test.lua` страхует случай,
 * когда тест лежит не в `tests/`, а рядом с модулем.
 */
export const PACK_EXCLUDED_SUFFIXES = ['.zip', '.test.lua'] as const;

/** Суффикс файла Lua-теста, convention `testing`. */
export const LUA_TEST_SUFFIX = '.test.lua';

/** Ожидаемый размер thumbnail.png в пикселях. */
export const THUMBNAIL_SIZE = 144;
