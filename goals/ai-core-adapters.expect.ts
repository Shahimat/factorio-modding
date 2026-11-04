import { crit, describe } from '@shahimat/ai-core/expect';

// Нулевой пункт раунда 0.2, решение владельца 2026-11-04: после
// source-sync в context/ai-core.yml остался один адаптер opencode, а
// инструменты контракта знают только claude-code и codex —
// `oc3 adapters check` падает на каждом запуске.
describe('goal: ai-core-adapters', () => {
  describe('ticket: tool-adapters-opencode', () => {
    crit.todo('oc3 adapters check зелёный при adapters: [opencode] в context/ai-core.yml: инструменты контракта распознают адаптер opencode');
    crit.todo('в активных конфигах и производных контракта (.agents/, context/) упоминаний claude-code не осталось; упоминания codex в генерате навыков — легитимное зеркало поддерживаемого адаптера источника ai-prompts');
    crit.todo('npm run check зелёный целиком');
  });
});
