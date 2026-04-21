/**
 * Queue names are referenced from both producers (API) and consumers (worker),
 * so they live in their own module to avoid circular imports and to keep
 * renames contained to a single file.
 *
 * Naming convention: `carcam.<domain>.<action>`. The `carcam.` prefix keeps
 * us from stepping on any other tenants in a shared Redis instance.
 */
export const QueueNames = {
  incidentReport: 'carcam.incident.report',
  hardPurge:     'carcam.gdpr.hard_purge',
  hazardExpiry:  'carcam.hazard.expiry',
} as const;

export type QueueName = (typeof QueueNames)[keyof typeof QueueNames];
