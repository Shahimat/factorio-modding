/**
 * Единственное место, где живут числовые и строковые значения конвенций
 * проекта. Источник правды — `context/conventions/*.yml`; при их правке
 * этот файл обновляется в той же фазе.
 */

/** Авторская приписка, convention `mod-naming`. */
export const MOD_NAME_PREFIX = 'shm-';

/**
 * Ник, которого нет в человекочитаемом заголовке ни у одного мода,
 * convention `mod-naming`. Сравнение без учёта регистра.
 */
export const MOD_TITLE_FORBIDDEN_NICK = 'Shahimat';

/**
 * Признак форка чужого мода в конце `name`, convention `mod-naming`, раздел
 * «Форки чужих модов». Форк не несёт ника: вместо приставки `shm-` и
 * префикса `title` — суффиксы.
 */
export const MOD_FORK_NAME_SUFFIX = '-fork';

/** Суффикс `title` форка: `<исходный title> fork`. */
export const MOD_FORK_TITLE_SUFFIX = ' fork';

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
 * Поддерживаемые версии игры, convention `factorio-version-track`: только
 * 2.1, поддержка 2.0 снята. `factorio_version` указывает ровно одну мажорную
 * версию, из двух чисел; любое значение вне списка — ошибка `validate`.
 */
export const FACTORIO_VERSION_TRACKS = ['2.1'] as const;

/**
 * Feature-флаги info.json: каждый требует у игрока Space Age, entity
 * `mod-package`. Мод с жёсткой зависимостью `space-age` несёт хотя бы один —
 * иначе мод-портал не помечает его как требующий Space Age, entity
 * `mod-portal`, `requires_space_age`.
 */
export const FEATURE_FLAGS = [
  'quality_required',
  'rail_bridges_required',
  'spoiling_required',
  'freezing_required',
  'segmented_units_required',
  'expansion_shaders_required',
  'space_travel_required',
] as const;

/** Имя мода дополнения Space Age в зависимостях. */
export const SPACE_AGE_MOD = 'space-age';

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
