# factorio-modding

Монорепозиторий модов Factorio автора Shahimat. Человеку — `README.md`.

## Где искать ответ

- как сейчас устроено X → источник реальности (`context/project.yml` → `reality`: код репозитория или целевые системы); почему X → `CHANGELOG.md`, затем `git log`;
- как договорились → `context/conventions/<key>.yml`; реквизиты, namespaces, external, roles.exceptions → `context/project.yml`;
- цели, программы, тикеты → `goals/`; роль, skills, browser, autonomy → `.agents/agents/`, `context/skills.yml`, `context/autonomy.yml`; возможности → `context/modules/*.yml`.

Полный обход `docs/`, `context/` и `goals/` запрещён: иди по маршруту.

## Жёсткие правила

1. Перед правкой — прочитай документы по маршруту задачи.
2. Memory агента запрещена: «запомни» — это `docs_request` librarian, а не память инструмента.
3. Внимание пользователя — самый дорогой ресурс: вопрос — только когда без решения нельзя продолжить или откатить.
4. Документацию пишет только librarian по `docs_request`: оператор, executor и judge её читают; генерируемое меняет `ai`.
5. Ничего не создавать, не переносить, не удалять без явного «да».
6. Git-запись (commit, amend, push, merge) делает пользователь; агент — только по явной просьбе.
7. Тяжёлая работа — ролям; действие наружу — по `context/autonomy.yml`; ролевые skills оператор не загружает.
Блоки возможностей ниже обязательны наравне с этими правилами.
## Сценарии

`plan` — «предложи»; `execute` — «делай»; `audit` — «проверь»; `challenge` — «покритикуй»; `report` — «статус». Протоколы — skill `workflow`.

## Оператор

- одна primary-сессия: приоритеты — порядок импортов программ и указания пользователя; пишет `goals/`, `.ops/operator/state.yml`, `.ops/feedback/`, сбрасывает `*.expect.json`, не пишет `docs/`, `context/`, `CHANGELOG.md`, код;
- роли запускает только с `background: true`; не блокируется и остаётся доступен человеку, просыпается на результате или сообщении;
- цель — `goals/<goal>.expect.ts`, программа — `goals/program--<key>.expect.ts`, тикет — `describe('ticket: …')`; один активный тикет на цель, paused — `crit.wip`;
- ролям — `brief` до 15 строк, от них — `report`; judge — `verdict`, librarian — `docs_request`; researcher от оператора — сколько угодно, от executor — ≤2 на тикет; executor — ≤5 активных (paused не считается); librarian — один;
- worktree и merge — оператор; external публикует по autonomy; проверки — в скоупе цели или программы; фидбек — skill `operator-feedback`.

## Skills

- ролевые skills — в `.agents/skills/`, привязка — `context/skills.yml`; оператор — только `operator-feedback` и явный `browser-read`; браузер — `browser` у executor, `browser-read` у judge и researcher.

<!-- блоки возможностей ниже добавляет contract-setup -->

<!-- module:domain -->
## domain

- как устроено X → `docs/entities/<id>.yml`, затем код;
- как X должно себя вести → `docs/behavior/<id>.yml`;
- правила слоя и `verified` → skill `domain`.
<!-- /module:domain -->

<!-- module:manuals -->
## manuals

- как сделать руками X → `docs/manuals/<name>.md`;
- формат и связи → skill `manuals`.
<!-- /module:manuals -->
