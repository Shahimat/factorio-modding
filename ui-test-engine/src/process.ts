import { spawn } from 'node:child_process';
import { StringDecoder } from 'node:string_decoder';

export type StopReason = 'complete' | 'native-error' | 'protocol-error' | 'timeout' | 'interrupted' | 'exit' | 'spawn-error';
export interface ProcessResult {
  readonly reason: StopReason;
  readonly code: number | null;
  readonly signal: NodeJS.Signals | null;
  readonly diagnostics: readonly string[];
  readonly log: string;
}

/** Chunk boundaries (including UTF-8 characters) are not protocol boundaries. */
export class Lines {
  private decoder = new StringDecoder('utf8');
  private pending = '';
  private readonly consume: (line: string) => void;

  constructor(consume: (line: string) => void) { this.consume = consume; }

  push(chunk: Buffer): void {
    this.pending += this.decoder.write(chunk);
    this.drain();
  }

  finish(): void {
    this.pending += this.decoder.end();
    this.drain();
    if (this.pending !== '') this.consume(this.pending);
    this.pending = '';
  }

  private drain(): void {
    let at: number;
    while ((at = this.pending.indexOf('\n')) !== -1) {
      this.consume(this.pending.slice(0, at).replace(/\r$/, ''));
      this.pending = this.pending.slice(at + 1);
    }
  }
}

export interface ProcessOptions {
  readonly binary: string;
  readonly args: readonly string[];
  readonly cwd: string;
  readonly timeoutMs: number;
  readonly killGraceMs?: number;
  readonly onLine: (line: string) => 'complete' | 'native-error' | undefined;
}

/** POSIX: owns its new process group, never an existing game or Steam client. */
export async function runProcess(options: ProcessOptions): Promise<ProcessResult> {
  const grouped = process.platform !== 'win32';
  const child = spawn(options.binary, [...options.args], {
    cwd: options.cwd, stdio: ['ignore', 'pipe', 'pipe'], detached: grouped,
  });
  let reason: StopReason | undefined;
  let killer: ReturnType<typeof setTimeout> | undefined;
  let pipeDeadline: ReturnType<typeof setTimeout> | undefined;
  let hardDeadline: ReturnType<typeof setTimeout> | undefined;
  let exited: { code: number | null; signal: NodeJS.Signals | null } | undefined;
  let finished = false;
  let resolveResult: (result: ProcessResult) => void = () => {};
  let log = '';
  const diagnostics: string[] = [];
  const grace = options.killGraceMs ?? 5000;
  const signal = (value: NodeJS.Signals): void => {
    try {
      if (grouped && child.pid !== undefined) process.kill(-child.pid, value);
      else child.kill(value);
    } catch (cause: unknown) {
      if (!(cause instanceof Error && 'code' in cause && cause.code === 'ESRCH')) {
        diagnostics.push(cause instanceof Error ? cause.message : String(cause));
      }
    }
  };
  const stop = (why: StopReason): void => {
    if (finished || reason !== undefined) return;
    reason = why;
    signal('SIGTERM');
    killer = setTimeout(() => {
      signal('SIGKILL');
      child.stdout.destroy(); child.stderr.destroy();
      // A re-parented/escaped descendant may still own pipe descriptors. Never
      // rely solely on `close` after the watchdog has expired.
      hardDeadline = setTimeout(() => {
        diagnostics.push('[process] forced end of output wait');
        child.unref();
        finish(exited?.code ?? null, exited?.signal ?? null);
      }, 100);
    }, grace);
  };
  const accept = (line: string): void => {
    log += `${line}\n`;
    try {
      const terminal = options.onLine(line);
      if (terminal !== undefined) stop(terminal);
    } catch (cause: unknown) {
      diagnostics.push(cause instanceof Error ? cause.message : String(cause));
      stop('protocol-error');
    }
  };
  const stdout = new Lines(accept);
  const stderr = new Lines(accept);
  const finish = (code: number | null, exitSignal: NodeJS.Signals | null): void => {
    if (finished) return;
    stdout.finish(); stderr.finish();
    finished = true;
    resolveResult({ reason: reason ?? 'exit', code, signal: exitSignal, diagnostics, log });
  };
  child.stdout.on('data', (chunk: Buffer) => { stdout.push(chunk); });
  child.stderr.on('data', (chunk: Buffer) => { stderr.push(chunk); });
  const interrupt = (): void => stop('interrupted');
  process.once('SIGINT', interrupt);
  process.once('SIGTERM', interrupt);
  const deadline = setTimeout(() => stop('timeout'), options.timeoutMs);
  try {
    return await new Promise<ProcessResult>((done) => {
      resolveResult = done;
      child.on('error', (cause: Error) => {
        reason = 'spawn-error';
        diagnostics.push(cause.message);
      });
      child.on('close', (code, exitSignal) => {
        // Closed leader pipes do not imply that descendants are gone: a child
        // with stdio=ignore can ignore SIGTERM. The leader has exited, so no
        // useful group work remains; finish cleanup before cancelling timers.
        if (grouped) signal('SIGKILL');
        finish(code, exitSignal);
      });
      child.on('exit', (code, signal) => {
        exited = { code, signal };
        // A subprocess can exit while a descendant keeps stdout/stderr alive.
        pipeDeadline = setTimeout(() => {
          diagnostics.push('[process] output pipes still open after exit');
          stop('exit');
        }, grace);
      });
    });
  } finally {
    clearTimeout(deadline);
    if (killer !== undefined) clearTimeout(killer);
    if (pipeDeadline !== undefined) clearTimeout(pipeDeadline);
    if (hardDeadline !== undefined) clearTimeout(hardDeadline);
    process.removeListener('SIGINT', interrupt);
    process.removeListener('SIGTERM', interrupt);
  }
}
