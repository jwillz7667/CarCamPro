/**
 * Minimal CIDR matcher. Handles exact IPv4/IPv6 matches and IPv4 prefix
 * ranges (`a.b.c.d/N`). IPv6 CIDR expansion is intentionally unimplemented —
 * operators who need per-subnet IPv6 should run behind a load balancer that
 * emits a normalized client IP via `X-Forwarded-For`.
 */
export const isIpInAllowlist = (ip: string, allow: readonly string[]): boolean => {
  for (const rule of allow) {
    if (rule === ip) return true;
    const slash = rule.indexOf('/');
    if (slash === -1) continue;
    const base = rule.slice(0, slash);
    const prefix = Number(rule.slice(slash + 1));
    if (Number.isFinite(prefix) && ipv4InCidr(ip, base, prefix)) return true;
  }
  return false;
};

export const ipv4InCidr = (ip: string, base: string, prefix: number): boolean => {
  const a = ipv4ToInt(ip);
  const b = ipv4ToInt(base);
  if (a === null || b === null) return false;
  if (prefix <= 0) return true;
  if (prefix > 32) return false;
  const mask = prefix === 32 ? 0xffffffff : (~0 << (32 - prefix)) >>> 0;
  return (a & mask) === (b & mask);
};

export const ipv4ToInt = (ip: string): number | null => {
  const parts = ip.split('.');
  if (parts.length !== 4) return null;
  let n = 0;
  for (const part of parts) {
    const octet = Number(part);
    if (!Number.isFinite(octet) || octet < 0 || octet > 255) return null;
    n = (n << 8) | octet;
  }
  return n >>> 0;
};
