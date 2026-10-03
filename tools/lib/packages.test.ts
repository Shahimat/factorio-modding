import assert from 'node:assert/strict';
import { mkdtemp, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { test } from 'node:test';
import { deflateSync } from 'node:zlib';

import { THUMBNAIL_SIZE } from './conventions.ts';
import {
  fileExists,
  isExpectedThumbnailSize,
  readPngSize,
} from './packages.ts';

/** Минимальный валидный PNG заданного размера. */
function png(width: number, height: number): Buffer {
  const crcTable: number[] = [];
  for (let n = 0; n < 256; n += 1) {
    let c = n;
    for (let k = 0; k < 8; k += 1) {
      c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
    }
    crcTable[n] = c >>> 0;
  }
  const crc32 = (buf: Buffer): number => {
    let c = 0xffffffff;
    for (const byte of buf) {
      c = (crcTable[(c ^ byte) & 0xff] ?? 0) ^ (c >>> 8);
    }
    return (c ^ 0xffffffff) >>> 0;
  };
  const chunk = (type: string, data: Buffer): Buffer => {
    const len = Buffer.alloc(4);
    len.writeUInt32BE(data.length);
    const body = Buffer.concat([Buffer.from(type, 'ascii'), data]);
    const crc = Buffer.alloc(4);
    crc.writeUInt32BE(crc32(body));
    return Buffer.concat([len, body, crc]);
  };

  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(width, 0);
  ihdr.writeUInt32BE(height, 4);
  ihdr[8] = 8;
  ihdr[9] = 2;
  const rows = Buffer.alloc(height * (1 + width * 3));
  return Buffer.concat([
    Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
    chunk('IHDR', ihdr),
    chunk('IDAT', deflateSync(rows)),
    chunk('IEND', Buffer.alloc(0)),
  ]);
}

test('isExpectedThumbnailSize требует ровно нужный квадрат', () => {
  const n = THUMBNAIL_SIZE;
  assert.equal(isExpectedThumbnailSize({ width: n, height: n }), true);
  assert.equal(isExpectedThumbnailSize({ width: n, height: n + 1 }), false);
  assert.equal(isExpectedThumbnailSize({ width: 64, height: 64 }), false);
});

test('readPngSize читает размеры из IHDR и отбивает не-PNG', async () => {
  const dir = await mkdtemp(join(tmpdir(), 'fm-pkg-'));
  try {
    const good = join(dir, 'good.png');
    await writeFile(good, png(THUMBNAIL_SIZE, THUMBNAIL_SIZE));
    assert.deepEqual(await readPngSize(good), {
      width: THUMBNAIL_SIZE,
      height: THUMBNAIL_SIZE,
    });

    const odd = join(dir, 'odd.png');
    await writeFile(odd, png(32, 64));
    assert.deepEqual(await readPngSize(odd), { width: 32, height: 64 });

    const notPng = join(dir, 'bad.png');
    await writeFile(notPng, 'not a png at all, just text');
    assert.equal(await readPngSize(notPng), null);

    const tooShort = join(dir, 'short.png');
    await writeFile(tooShort, Buffer.from([0x89, 0x50]));
    assert.equal(await readPngSize(tooShort), null);

    assert.equal(await readPngSize(join(dir, 'missing.png')), null);
  } finally {
    await rm(dir, { recursive: true, force: true });
  }
});

test('fileExists различает файл, каталог и отсутствие', async () => {
  const dir = await mkdtemp(join(tmpdir(), 'fm-pkg-'));
  try {
    const file = join(dir, 'x.txt');
    await writeFile(file, 'x');
    assert.equal(await fileExists(file), true);
    assert.equal(await fileExists(dir), false);
    assert.equal(await fileExists(join(dir, 'nope.txt')), false);
  } finally {
    await rm(dir, { recursive: true, force: true });
  }
});
