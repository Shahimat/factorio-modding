#!/usr/bin/env node
import { runPoc } from './runner.ts';

try {
  process.exitCode = await runPoc(process.argv.slice(2));
} catch (cause: unknown) {
  console.error(cause instanceof Error ? cause.message : String(cause));
  process.exitCode = 1;
}
