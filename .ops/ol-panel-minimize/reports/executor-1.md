# executor · ol-panel-minimize · run 1

```yaml
done:
  - кнопка сворачивания — первый элемент развёрнутой панели (слева в ряду, сверху в столбике); клик перестраивает панель в свёрнутый вид, клик по кнопке разворачивает обратно (runtime/panel.lua: toggle_button, panel.build, panel.on_click)
  - состояние «свёрнуто» per player в storage.panel_collapsed; on_init/on_configuration_changed в control.lua; переоткрытие окна и сохранение/загрузка переживает самим storage; пока свёрнуто — on_gui_opened строит кнопку, refresh_all не обновляет
  - свёрнутая кнопка на том же якоре: anchor(entity) + defines.relative_gui_position[position_of(player)]; настройка shm-orbital-logistics-panel-position действует на оба вида
  - иконки utility/collapse (кнопка «свернуть») и utility/expand (кнопка «развернуть») проверены helpers.is_valid_sprite_path, при провале — текстовый фолбэк (кнопка с локализованным caption); подсказки — локализованные строки collapse/expand
  - ключи collapse/expand добавлены во все 11 локалей; набор ключей каждого языка = en (проверено скриптом, 67 ключей)
  - тест в игре (тег gui): сворачивание, разворачивание, якорь, refresh_all не трогает свёрнутый вид, переоткрытие окна, настройка положения, площадка; сброс состояния в after_each
  - версия 0.1.1 в info.json и верхняя секция changelog.txt (валидатор мода зелёный)
checks:
  - npm run check — зелёный (typecheck, unit, secrets, docs, validate)
  - npm run check:mod -- shm-orbital-logistics — зелёный: lua-тесты 37 passed, пакет ок
  - npm run test:ingame:gui -w shm-orbital-logistics — зелёный, 7/7, прогон с графикой
  - judge run 1 — pass, 7/7 crit (.ops/ol-panel-minimize/verdicts/1.yml); замечаний нет, доработок не было
  - judge run 2 — pass, 7/7 crit (.ops/ol-panel-minimize/verdicts/2.yml)
left:
  - публикация на портал — вне тикета, только по явному «да» владельца
risks:
  - свёрнутый вид — frame с одной sprite-button размера 24; вид (рамка с отступами) не проверялся глазами в игре, только тестами
  - иконки utility/collapse и utility/expand существуют в core 2.1 (в прогоне is_valid_sprite_path принял их — кнопка со спрайтом, тест подтверждает только наличие элемента)
refs:
  - git diff главного checkout: mods/shm-orbital-logistics/{runtime/panel.lua,control.lua,tests/ingame/gui.lua,info.json,changelog.txt,locale/*/locale.cfg}
  - правки .agents/agents/*.md и goals/orbital-logistics.expect.ts в дереве — оператора, executor их не делал
  - вердикты: .ops/ol-panel-minimize/verdicts/{1,2}.yml; judge запускался через opencode run (claude-адаптер недоступен: аккаунт на холде), модель zai-coding-plan/glm-5.3-flash
```
