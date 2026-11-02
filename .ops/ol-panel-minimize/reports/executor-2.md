# executor · ol-panel-minimize · run 3 · доработка (retry-цикл)

Доработка по решению владельца (посмотрел свёрнутый вид вживую: кнопка-стрелка
ни о чём не говорит — свёрнутый вид должен упоминать мод).

```yaml
done:
  - свёрнутый вид — мини-окошко: caption { L .. 'panel-title' } теперь у frame в обоих видах (перенесён в конструктор рамки, раньше ставился только после раннего return свёрнутой ветки); кнопка разворачивания осталась внутри рамки
  - тест: у свёрнутой рамки caption — { 'shm-orbital-logistics.panel-title' }, после разворачивания заголовок на месте; сценарий переименован («сворачивается в мини-окошко с названием мода»)
  - новых строк локали нет (ключ panel-title существующий)
checks:
  - npm run check — зелёный
  - npm run check:mod -- shm-orbital-logistics — зелёный: lua 37 passed, пакет ок
  - npm run test:ingame:gui -w shm-orbital-logistics — зелёный, 7/7, с графикой
  - judge run 3 (retry-цикл) — pass, 8/8 crit, включая новый «свёрнутый вид упоминает мод» (.ops/ol-panel-minimize/verdicts/3.yml)
left:
  - публикация на портал — вне тикета, только по явному «да» владельца
risks:
  - caption свёрнутого вида делает мини-окошко шире кнопки-стрелки (ширина по тексту «Orbital Logistics»); вживую после правки владелец не смотрел
  - замечание judge вне пунктов (не блокер): строка features в changelog.txt 0.1.1 ещё описывает свёрнутый вид как «small button» — уточнить формулировку решит оператор
refs:
  - git diff главного checkout по mods/shm-orbital-logistics/ (panel.lua, tests/ingame/gui.lua)
  - вердикты: .ops/ol-panel-minimize/verdicts/{1,2}.yml (до доработки), 3.yml (после)
  - goals/orbital-logistics.expect.json: retry true, run 3 — по заданию оператора
```
