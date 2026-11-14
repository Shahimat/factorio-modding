export type ScenarioName = 'counter' | 'orbital';
export interface Viewport { readonly width: number; readonly height: number }
export interface Point { readonly x: number; readonly y: number }
export interface Profile {
  readonly name: ScenarioName;
  readonly mods: readonly { readonly name: string; readonly source: string }[];
  readonly builtins: readonly string[];
  readonly simulationMods: readonly string[];
  readonly window: string;
  readonly viewport?: Viewport;
  readonly reference?: Viewport & Point;
  readonly order: readonly string[];
}

export const BUILTINS = ['elevated-rails', 'recycler', 'quality', 'space-age'] as const;

const PROFILES: Record<ScenarioName, Profile> = {
  counter: {
    name: 'counter',
    mods: [{ name: 'shm-ui-test-fixture', source: 'ui-test-engine/fixtures/counter' }],
    builtins: [], simulationMods: ['shm-ui-test-engine', 'shm-ui-test-fixture'], window: '1280x720',
    order: ['started', 'capture:before', 'located', 'input', 'result', 'capture:after', 'complete'],
  },
  orbital: {
    name: 'orbital',
    mods: [{ name: 'shm-orbital-logistics', source: 'mods/shm-orbital-logistics' }],
    builtins: BUILTINS, simulationMods: ['space-age', 'shm-orbital-logistics', 'shm-ui-test-engine'],
    window: '1600x1000', viewport: { width: 1920, height: 1080 },
    reference: { x: 64, y: 48, width: 256, height: 64 },
    order: ['started', 'located:open', 'input:open', 'located:expand', 'input:expand', 'checkpoint',
      'capture:before', 'located:collapse', 'input:collapse', 'result', 'capture:after', 'complete'],
  },
};

export function isScenarioName(value: string): value is ScenarioName {
  return value === 'counter' || value === 'orbital';
}

export function profileFor(name: ScenarioName): Profile { return PROFILES[name]; }

export function markerPoints(viewport: Viewport): readonly [Point, Point] {
  return [{ x: 64, y: 0 }, { x: viewport.width - 24, y: viewport.height - 24 }];
}

export function modList(profile: Profile): { mods: { name: string; enabled: boolean }[] } {
  return { mods: [
    { name: 'base', enabled: true },
    ...BUILTINS.map((name) => ({ name, enabled: profile.builtins.includes(name) })),
    ...profile.mods.map(({ name }) => ({ name, enabled: true })),
    { name: 'shm-ui-test-engine', enabled: true },
  ] };
}

/** Only registry-owned ASCII names and a validated generated run identifier enter Lua. */
export function runOptions(profile: Profile, runId: string, negative: boolean): string {
  if (!/^run-[A-Za-z0-9-]+$/.test(runId)) throw new Error('[profile] invalid run identifier');
  const mods = profile.simulationMods.map((name) => JSON.stringify(name)).join(', ');
  const viewport = profile.viewport === undefined ? 'nil' : `{width=${profile.viewport.width}, height=${profile.viewport.height}}`;
  const markers = profile.viewport === undefined ? '{}' : `{${markerPoints(profile.viewport).map((point) => `{x=${point.x}, y=${point.y}}`).join(',')}}`;
  const reference = profile.reference === undefined ? 'nil' : `{x=${profile.reference.x}, y=${profile.reference.y}, width=${profile.reference.width}, height=${profile.reference.height}}`;
  return `return {negative=${String(negative)}, run_id=${JSON.stringify(runId)}, simulation_mods={${mods}}, viewport=${viewport}, markers=${markers}, reference=${reference}}\n`;
}
