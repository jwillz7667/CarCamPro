/**
 * CLI: dump the live OpenAPI spec to stdout (or `--out <file>`).
 *
 * Used by CI to generate a committed `openapi.json` artifact, by the iOS
 * client to regenerate its APIClient stubs, and by contract-test suites that
 * diff the spec between commits to detect accidental breaking changes.
 *
 *   pnpm openapi:emit                 → writes to stdout
 *   pnpm openapi:emit --out spec.json → writes to file
 */
import { writeFile } from 'node:fs/promises';

import { buildApp } from '../src/app.js';

const main = async () => {
  const outIdx = process.argv.indexOf('--out');
  const outPath = outIdx !== -1 ? process.argv[outIdx + 1] : null;

  const app = await buildApp();
  const spec = app.swagger();
  const json = JSON.stringify(spec, null, 2);

  if (outPath) {
    await writeFile(outPath, json, 'utf8');
    // eslint-disable-next-line no-console
    console.error(`wrote ${json.length} bytes → ${outPath}`);
  } else {
    // eslint-disable-next-line no-console
    console.log(json);
  }

  await app.close();
  process.exit(0);
};

void main().catch((err) => {
  // eslint-disable-next-line no-console
  console.error('openapi:emit failed', err);
  process.exit(1);
});
