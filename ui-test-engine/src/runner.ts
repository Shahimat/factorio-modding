import { execFileSync } from 'node:child_process';
import { cp, mkdir, mkdtemp, readFile, writeFile } from 'node:fs/promises';
import { basename, dirname, join, relative, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

import { PNG } from 'pngjs';

import { findGameBinary, gameReadData } from '../../tools/lib/game-install.ts';
import { STEAM_APP_ID } from '../../tools/lib/ingame-config.ts';
import { gameVersion, parseOptions, USAGE } from './options.ts';
import { runProcess } from './process.ts';
import { modList, profileFor, runOptions } from './profiles.ts';
import { checkTrace, parseEvent, type Check, type NativeEvent } from './protocol.ts';
import { checkImages, checkWindowImages, crop, type Bounds, type FrameProof, type Raster, type WindowProof } from './visual.ts';

const ENGINE_ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const REPO_ROOT = resolve(ENGINE_ROOT, '..');

async function saveCrop(output: string, role: string, image: Raster, proof: FrameProof): Promise<void> {
  if (proof.anchor === undefined || proof.region === undefined) return;
  const bounds: Bounds = {
    x: proof.anchor.x, y: proof.anchor.y,
    width: proof.region.width, height: proof.anchor.height + proof.region.height,
  };
  await saveBounds(output, role, image, bounds);
}

async function saveBounds(output: string, role: string, image: Raster, bounds: Bounds | undefined): Promise<void> {
  if (bounds === undefined) return;
  const clipped = crop(image, bounds);
  const png = new PNG({ width: clipped.width, height: clipped.height });
  png.data = Buffer.from(clipped.data);
  await writeFile(join(output, `${role}-ui.png`), PNG.sync.write(png));
}

export async function runPoc(args: readonly string[]): Promise<number> {
  const options = parseOptions(args);
  if (options.help) { console.log(USAGE); return 0; }
  const profile = profileFor(options.scenario);
  const binary = findGameBinary();
  const readData = gameReadData(binary);
  const version = gameVersion(execFileSync(binary, ['--version'], { encoding: 'utf8', timeout: 10_000 }));
  const parent = join(REPO_ROOT, '.work', 'ui-test-engine');
  await mkdir(parent, { recursive: true });
  const output = await mkdtemp(join(parent, 'run-'));
  const runId = basename(output);
  const mods = join(output, 'mods');
  const driver = join(mods, 'shm-ui-test-engine');
  await mkdir(mods);
  await cp(join(ENGINE_ROOT, 'native'), driver, { recursive: true });
  for (const mod of profile.mods) await cp(join(REPO_ROOT, mod.source), join(mods, mod.name), { recursive: true });
  await cp(join(ENGINE_ROOT, 'scenarios', `${profile.name}.lua`), join(driver, 'scenario.lua'));
  await writeFile(join(driver, 'run-options.lua'), runOptions(profile, runId, options.negative));
  await writeFile(join(mods, 'mod-list.json'), JSON.stringify(modList(profile), null, 2));
  await writeFile(join(output, 'steam_appid.txt'), `${STEAM_APP_ID}\n`);
  const config = join(output, 'config.ini');
  await writeFile(config, `[path]\nread-data=${readData}\nwrite-data=${output}\n\n[general]\nlocale=en\n\n[other]\ncheck-updates=false\nenable-blueprint-storage-cloud-sync=false\n\n[interface]\nautomatic-ui-scale=false\ncustom-ui-scale=1\n`);
  console.log(`Factorio ${version}; ${profile.name}${options.negative ? ' (disabled-button negative case)' : ''}`);
  console.log(`Артефакты: ${relative(REPO_ROOT, output)}`);

  const events: NativeEvent[] = [];
  const processResult = await runProcess({
    binary,
    args: ['--config', config, '--mod-directory', mods, '--disable-audio', '--window-size', profile.window, '--load-scenario', 'shm-ui-test-engine/host'],
    cwd: output,
    timeoutMs: options.timeoutMs,
    onLine: (line) => {
      const event = parseEvent(line);
      if (event === undefined) return undefined;
      if (event.run_id !== runId) throw new Error('[protocol] wrong run identity');
      events.push(event);
      console.log(`native: ${event.type}${event.type === 'capture' ? ` ${event.role}` : ''}`);
      if (event.type === 'error') return 'native-error';
      return event.type === 'complete' ? 'complete' : undefined;
    },
  });
  await writeFile(join(output, 'process.log'), processResult.log);
  const checks: Check[] = [
    { name: 'process completed', passed: processResult.reason === 'complete' && (processResult.code === 0 || processResult.signal === 'SIGTERM'), detail: `${processResult.reason}; code=${processResult.code}; signal=${processResult.signal}` },
    ...processResult.diagnostics.map((detail): Check => ({ name: 'process diagnostic', passed: false, detail })),
    ...checkTrace(events, runId, profile),
  ];
  let images: { before: FrameProof | WindowProof; after: FrameProof | WindowProof } | undefined;
  try {
    const directory = join(output, 'script-output', 'ui-test');
    const before = PNG.sync.read(await readFile(join(directory, 'before.png')));
    const after = PNG.sync.read(await readFile(join(directory, 'after.png')));
    if (profile.viewport === undefined) {
      const proof = checkImages(before, after);
      images = { before: proof.before, after: proof.after };
      checks.push(...proof.checks);
      await saveCrop(output, 'before', before, proof.before);
      await saveCrop(output, 'after', after, proof.after);
    } else {
      const first = events.find((event) => event.type === 'checkpoint');
      const last = events.find((event) => event.type === 'result');
      if (first?.type !== 'checkpoint' || last?.type !== 'result' || last.frame === undefined) throw new Error('[image] missing production frame geometry');
      if (profile.reference === undefined) throw new Error('[image] missing title reference configuration');
      const proof = checkWindowImages(before, after, first.frame, last.frame, profile.viewport, profile.reference);
      images = { before: proof.before, after: proof.after };
      checks.push(...proof.checks);
      await saveBounds(output, 'before', before, proof.before.crop);
      await saveBounds(output, 'after', after, proof.after.crop);
    }
  } catch (cause: unknown) {
    checks.push({ name: 'screenshots decode', passed: false, detail: cause instanceof Error ? cause.message : String(cause) });
  }
  const passed = checks.every((check) => check.passed);
  const report = {
    schema: 1, runId, scenario: profile.name, negative: options.negative,
    factorio: version, platform: process.platform, arch: process.arch,
    passed, checks, events, images,
    process: { reason: processResult.reason, code: processResult.code, signal: processResult.signal },
    artifacts: { before: 'script-output/ui-test/before.png', after: 'script-output/ui-test/after.png', log: 'process.log' },
  };
  await writeFile(join(output, 'report.json'), `${JSON.stringify(report, null, 2)}\n`);
  for (const check of checks) console.log(`${check.passed ? 'PASS' : 'FAIL'} ${check.name}: ${check.detail}`);
  console.log(`${passed ? 'PASS' : 'FAIL'} — ${relative(REPO_ROOT, join(output, 'report.json'))}`);
  return passed ? 0 : 1;
}
