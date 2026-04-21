import { describe, expect, it } from 'vitest';

import { ipv4InCidr, ipv4ToInt, isIpInAllowlist } from '../src/lib/cidr.js';

describe('cidr', () => {
  describe('ipv4ToInt', () => {
    it('parses canonical dotted-quad', () => {
      expect(ipv4ToInt('127.0.0.1')).toBe(0x7f000001);
      expect(ipv4ToInt('10.0.0.0')).toBe(0x0a000000);
      expect(ipv4ToInt('255.255.255.255')).toBe(0xffffffff);
    });

    it('rejects malformed input', () => {
      expect(ipv4ToInt('not-an-ip')).toBeNull();
      expect(ipv4ToInt('1.2.3')).toBeNull();
      expect(ipv4ToInt('1.2.3.4.5')).toBeNull();
      expect(ipv4ToInt('256.0.0.0')).toBeNull();
      expect(ipv4ToInt('-1.0.0.0')).toBeNull();
    });
  });

  describe('ipv4InCidr', () => {
    it('matches within /24', () => {
      expect(ipv4InCidr('10.0.0.5', '10.0.0.0', 24)).toBe(true);
      expect(ipv4InCidr('10.0.1.5', '10.0.0.0', 24)).toBe(false);
    });

    it('matches /32 exact', () => {
      expect(ipv4InCidr('10.0.0.5', '10.0.0.5', 32)).toBe(true);
      expect(ipv4InCidr('10.0.0.6', '10.0.0.5', 32)).toBe(false);
    });

    it('treats /0 as match-all', () => {
      expect(ipv4InCidr('1.2.3.4', '0.0.0.0', 0)).toBe(true);
    });

    it('rejects invalid prefix lengths', () => {
      expect(ipv4InCidr('10.0.0.1', '10.0.0.0', 33)).toBe(false);
    });
  });

  describe('isIpInAllowlist', () => {
    it('returns false for empty allowlist', () => {
      expect(isIpInAllowlist('10.0.0.5', [])).toBe(false);
    });

    it('matches exact literal rules', () => {
      expect(isIpInAllowlist('10.0.0.5', ['10.0.0.5'])).toBe(true);
      expect(isIpInAllowlist('10.0.0.6', ['10.0.0.5'])).toBe(false);
    });

    it('matches CIDR rules among literals', () => {
      expect(isIpInAllowlist('192.168.1.50', ['10.0.0.0/8', '192.168.1.0/24'])).toBe(true);
      expect(isIpInAllowlist('192.168.2.50', ['10.0.0.0/8', '192.168.1.0/24'])).toBe(false);
    });

    it('short-circuits on first match', () => {
      expect(isIpInAllowlist('10.0.0.1', ['10.0.0.1', 'bogus-rule'])).toBe(true);
    });
  });
});
