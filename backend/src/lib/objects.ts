/**
 * Returns a shallow copy of `input` with `undefined` property values removed.
 * Useful when passing Zod-parsed bodies directly into Prisma `update` / `upsert`
 * calls — under `exactOptionalPropertyTypes: true`, Prisma rejects explicit
 * `undefined` on columns whose schema type doesn't include it, even though the
 * Prisma client would happily ignore the key at runtime. This bridges the gap
 * without duplicating per-field conditionals across routes.
 */
export const stripUndefined = <T extends Record<string, unknown>>(
  input: T,
): { [K in keyof T]-?: Exclude<T[K], undefined> } => {
  const out: Record<string, unknown> = {};
  for (const key of Object.keys(input)) {
    const value = input[key];
    if (value !== undefined) out[key] = value;
  }
  return out as { [K in keyof T]-?: Exclude<T[K], undefined> };
};
