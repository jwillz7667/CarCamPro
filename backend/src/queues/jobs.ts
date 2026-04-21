import { z } from 'zod';

/**
 * Job payload schemas — validated at both enqueue and dequeue time. BullMQ
 * round-trips payloads through Redis as JSON, so a bad shape in either
 * direction is caught before it reaches business logic.
 *
 * Each job gets a dedicated schema and an inferred TS type. Keep payloads
 * small (IDs, not full rows) — the worker re-fetches fresh state from the DB
 * to avoid acting on a stale snapshot that was serialized minutes or hours
 * ago.
 */

// ─── carcam.incident.report ─────────────────────────────────
export const IncidentReportJobSchema = z.object({
  reportId: z.string().length(26),
  userId: z.string().length(26),
  clipId: z.string().length(26),
  /// Monotonic attempt counter — incremented on retries. Lets the renderer
  /// escalate logging on later attempts.
  attempt: z.number().int().min(1).default(1),
});
export type IncidentReportJob = z.infer<typeof IncidentReportJobSchema>;

// ─── carcam.gdpr.hard_purge ────────────────────────────────
export const HardPurgeJobSchema = z.object({
  /// When `userId` is present, purge just that user (admin-triggered).
  /// Otherwise, the worker runs a batched scan for *all* eligible users
  /// whose 30-day cooldown has elapsed.
  userId: z.string().length(26).optional(),
  /// Upper bound on users to touch in a single pass; keeps a scan from
  /// monopolizing the worker if a backlog builds up.
  batchSize: z.number().int().positive().max(500).default(50),
});
export type HardPurgeJob = z.infer<typeof HardPurgeJobSchema>;

// ─── carcam.hazard.expiry ──────────────────────────────────
export const HazardExpiryJobSchema = z.object({
  batchSize: z.number().int().positive().max(5000).default(1000),
});
export type HazardExpiryJob = z.infer<typeof HazardExpiryJobSchema>;
