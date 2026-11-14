export interface Check {
  readonly name: string;
  readonly passed: boolean;
  readonly detail: string;
}

type Scalar = string | number | boolean | null;
interface Assertion {
  readonly name: string;
  readonly actual: Scalar;
  readonly expected: Scalar;
}
interface Envelope {
  readonly protocol: 1;
  readonly run_id: string;
  readonly tick: number;
}
export interface GuiFrame { readonly x: number; readonly y: number; readonly width: number; readonly height: number }

export type NativeEvent = Envelope & (
  | { readonly type: 'started'; readonly scenario: string }
  | { readonly type: 'located'; readonly position: { readonly x: number; readonly y: number }; readonly step?: string }
  | { readonly type: 'input'; readonly action: 'mouse_click'; readonly step?: string }
  | { readonly type: 'result'; readonly checks: readonly Assertion[]; readonly frame?: GuiFrame }
  | { readonly type: 'checkpoint'; readonly checks: readonly Assertion[]; readonly frame: GuiFrame }
  | { readonly type: 'capture'; readonly role: 'before' | 'after' }
  | { readonly type: 'complete' }
  | { readonly type: 'error'; readonly source: string; readonly message: string }
);

function record(value: unknown): Record<string, unknown> {
  if (typeof value !== 'object' || value === null || Array.isArray(value)) {
    throw new Error('[protocol] expected object');
  }
  return value as Record<string, unknown>;
}

function text(value: unknown): string {
  if (typeof value !== 'string' || value.length === 0) throw new Error('[protocol] expected nonempty text');
  return value;
}

function number(value: unknown): number {
  if (typeof value !== 'number' || !Number.isFinite(value)) throw new Error('[protocol] expected finite number');
  return value;
}

function scalar(value: unknown): Scalar {
  if (value === null || typeof value === 'string' || typeof value === 'boolean') return value;
  return number(value);
}

function frameOf(raw: unknown): GuiFrame {
  const value = record(raw);
  const frame = { x: number(value['x']), y: number(value['y']), width: number(value['width']), height: number(value['height']) };
  if (frame.width <= 0 || frame.height <= 0) throw new Error('[protocol] invalid GUI frame');
  return frame;
}

/** Only complete newline-delimited Factorio log lines enter this parser. */
export function parseEvent(line: string): NativeEvent | undefined {
  const marker = 'SHM_UI_TEST ';
  const at = line.indexOf(marker);
  if (at === -1) return undefined;
  let parsed: unknown;
  try { parsed = JSON.parse(line.slice(at + marker.length)); }
  catch { throw new Error('[protocol] malformed JSON'); }
  const value = record(parsed);
  if (value['protocol'] !== 1) throw new Error('[protocol] unsupported version');
  const envelope: Envelope = { protocol: 1, run_id: text(value['run_id']), tick: number(value['tick']) };
  const type = value['type'];
  const step = value['step'] === undefined ? {} : { step: text(value['step']) };
  switch (type) {
    case 'started': return { ...envelope, type, scenario: text(value['scenario']) };
    case 'located': {
      const point = record(value['position']);
      return { ...envelope, type, ...step, position: { x: number(point['x']), y: number(point['y']) } };
    }
    case 'input':
      if (value['action'] !== 'mouse_click') throw new Error('[protocol] unsupported input');
      return { ...envelope, type, ...step, action: 'mouse_click' };
    case 'checkpoint':
    case 'result': {
      const checks = value['checks'];
      if (!Array.isArray(checks) || checks.length === 0) throw new Error('[protocol] empty assertions');
      const assertions = checks.map((item: unknown): Assertion => {
        const check = record(item);
        return { name: text(check['name']), actual: scalar(check['actual']), expected: scalar(check['expected']) };
      });
      if (new Set(assertions.map((item) => item.name)).size !== assertions.length) {
        throw new Error('[protocol] duplicate assertion');
      }
      if (type === 'checkpoint') return { ...envelope, type, checks: assertions, frame: frameOf(value['frame']) };
      const frame = value['frame'] === undefined ? {} : { frame: frameOf(value['frame']) };
      return { ...envelope, type, checks: assertions, ...frame };
    }
    case 'capture':
      if (value['role'] !== 'before' && value['role'] !== 'after') throw new Error('[protocol] invalid capture');
      return { ...envelope, type, role: value['role'] };
    case 'complete': return { ...envelope, type };
    case 'error': return { ...envelope, type, source: text(value['source']), message: text(value['message']) };
    default: throw new Error('[protocol] unknown event');
  }
}

/** State and capture order are checked independently of the process exit code. */
export function checkTrace(events: readonly NativeEvent[], runId: string, profile?: { readonly name: string; readonly order: readonly string[] }): Check[] {
  const checks: Check[] = [];
  const order = events.filter((event) => event.type !== 'error').map((event) =>
    event.type === 'capture' ? `capture:${event.role}` :
      (event.type === 'located' || event.type === 'input') && event.step !== undefined ? `${event.type}:${event.step}` : event.type);
  const expected = profile?.order ?? ['started', 'capture:before', 'located', 'input', 'result', 'capture:after', 'complete'];
  checks.push({ name: 'native lifecycle', passed: JSON.stringify(order) === JSON.stringify(expected), detail: order.join(' → ') || 'no events' });
  checks.push({ name: 'run identity', passed: events.length > 0 && events.every((event) => event.run_id === runId), detail: runId });
  if (profile !== undefined) checks.push({ name: 'scenario identity', passed: events.some((event) => event.type === 'started' && event.scenario === profile.name), detail: profile.name });
  for (const event of events) {
    if (event.type === 'error') checks.push({ name: `native ${event.source}`, passed: false, detail: event.message });
    if (event.type === 'result' || event.type === 'checkpoint') {
      for (const assertion of event.checks) checks.push({
        name: assertion.name,
        passed: Object.is(assertion.actual, assertion.expected),
        detail: `expected ${JSON.stringify(assertion.expected)}, actual ${JSON.stringify(assertion.actual)}`,
      });
    }
  }
  return checks;
}
