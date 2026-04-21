import { describe, expect, it } from 'vitest';

import {
  renderIncidentReportPdf,
  type IncidentReportPayload,
} from '../src/workers/incidentReport/renderer.js';

const fixture = (): IncidentReportPayload => ({
  clip: {
    id: '01HK2G7VN3C6JZC1M3YT1FAKE1',
    startedAt: '2026-04-01T14:22:10.000Z',
    endedAt: '2026-04-01T14:23:10.000Z',
    durationSeconds: 60.25,
    resolution: '1080p',
    codec: 'HEVC',
  },
  telemetry: {
    peakGForce: 4.72,
    severity: 'moderate',
    startLatitude: 37.774929,
    startLongitude: -122.419416,
    endLatitude: 37.780000,
    endLongitude: -122.410000,
    averageSpeedMPH: 32.5,
  },
  user: {
    id: '01HK2G7VN3C6JZC1M3YT1USER1',
    email: 'driver@example.com',
    displayName: 'Test Driver',
  },
  device: {
    id: '01HK2G7VN3C6JZC1M3YT1DEV01',
    name: 'iPhone 16 Pro',
    model: 'iPhone16,1',
    osVersion: '26.0',
    appVersion: '1.0.0',
  },
  generatedAt: '2026-04-20T09:00:00.000Z',
});

describe('renderIncidentReportPdf', () => {
  it('produces a non-empty PDF with the standard magic header', async () => {
    const { bytes, sizeBytes } = await renderIncidentReportPdf(fixture());
    expect(sizeBytes).toBe(bytes.byteLength);
    expect(bytes.byteLength).toBeGreaterThan(1024);
    // "%PDF-" (0x25, 0x50, 0x44, 0x46, 0x2D)
    expect(bytes.subarray(0, 5).toString('ascii')).toBe('%PDF-');
  });

  it('gracefully renders when nullable fields are missing', async () => {
    const payload = fixture();
    payload.telemetry.peakGForce = null;
    payload.telemetry.averageSpeedMPH = null;
    payload.telemetry.severity = null;
    payload.telemetry.startLatitude = null;
    payload.telemetry.startLongitude = null;
    payload.telemetry.endLatitude = null;
    payload.telemetry.endLongitude = null;
    payload.device = null;

    const { bytes } = await renderIncidentReportPdf(payload);
    expect(bytes.byteLength).toBeGreaterThan(1024);
  });
});
