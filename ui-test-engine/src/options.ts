export interface Options {
  readonly negative: boolean;
  readonly timeoutMs: number;
  readonly help: boolean;
}

export const USAGE = 'npm run test:ui:poc -- [--negative] [--timeout <seconds>]';

export function parseOptions(args: readonly string[]): Options {
  let negative = false;
  let timeoutMs = 90_000;
  let help = false;
  const seen = new Set<string>();
  for (let i = 0; i < args.length; i += 1) {
    const arg = args[i] ?? '';
    if (seen.has(arg)) throw new Error(`[arguments] repeated ${arg}`);
    seen.add(arg);
    if (arg === '--negative') negative = true;
    else if (arg === '--help') help = true;
    else if (arg === '--timeout') {
      const value = args[++i] ?? '';
      if (!/^\d+$/.test(value) || Number(value) < 1 || Number(value) > 600) {
        throw new Error('[arguments] --timeout requires 1–600 seconds');
      }
      timeoutMs = Number(value) * 1000;
    } else throw new Error(`[arguments] unknown ${arg}; ${USAGE}`);
  }
  return { negative, timeoutMs, help };
}

export function gameVersion(text: string): string {
  const version = /^Version: (2\.1\.\d+)\b/m.exec(text)?.[1];
  if (version === undefined) throw new Error('[version] Factorio 2.1 is required');
  return version;
}
