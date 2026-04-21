import { describe, expect, it } from 'vitest';

import {
  HardPurgeJobSchema,
  HazardExpiryJobSchema,
  IncidentReportJobSchema,
} from '../src/queues/jobs.js';

describe('queue job schemas', () => {
  describe('IncidentReportJobSchema', () => {
    it('accepts a well-formed payload', () => {
      const id = 'A'.repeat(26);
      const parsed = IncidentReportJobSchema.parse({
        reportId: id,
        userId: id,
        clipId: id,
        attempt: 2,
      });
      expect(parsed.attempt).toBe(2);
    });

    it('defaults attempt to 1 when omitted', () => {
      const id = 'B'.repeat(26);
      const parsed = IncidentReportJobSchema.parse({
        reportId: id,
        userId: id,
        clipId: id,
      });
      expect(parsed.attempt).toBe(1);
    });

    it('rejects short IDs (prevents typo-triggered cross-row writes)', () => {
      expect(() =>
        IncidentReportJobSchema.parse({
          reportId: 'too-short',
          userId: 'A'.repeat(26),
          clipId: 'A'.repeat(26),
        }),
      ).toThrow();
    });
  });

  describe('HardPurgeJobSchema', () => {
    it('accepts the batch-scan shape', () => {
      const parsed = HardPurgeJobSchema.parse({});
      expect(parsed.batchSize).toBe(50);
      expect(parsed.userId).toBeUndefined();
    });

    it('accepts the targeted-user shape', () => {
      const id = 'C'.repeat(26);
      const parsed = HardPurgeJobSchema.parse({ userId: id, batchSize: 1 });
      expect(parsed.userId).toBe(id);
      expect(parsed.batchSize).toBe(1);
    });

    it('caps batchSize at 500 to bound worker latency', () => {
      expect(() => HardPurgeJobSchema.parse({ batchSize: 5000 })).toThrow();
    });
  });

  describe('HazardExpiryJobSchema', () => {
    it('defaults batchSize to 1000', () => {
      const parsed = HazardExpiryJobSchema.parse({});
      expect(parsed.batchSize).toBe(1000);
    });

    it('rejects zero or negative batchSize', () => {
      expect(() => HazardExpiryJobSchema.parse({ batchSize: 0 })).toThrow();
      expect(() => HazardExpiryJobSchema.parse({ batchSize: -1 })).toThrow();
    });
  });
});
