import { Buffer } from 'node:buffer';
import { PassThrough } from 'node:stream';

import PDFDocument from 'pdfkit';

/**
 * Structured payload the renderer consumes. Deliberately duplicated (not
 * imported from Prisma types) so the PDF template stays stable even if the
 * DB schema evolves — the snapshot stored on `incident_reports.payloadJson`
 * conforms to this shape.
 */
export interface IncidentReportPayload {
  clip: {
    id: string;
    startedAt: string;
    endedAt: string;
    durationSeconds: number;
    resolution: string;
    codec: string;
  };
  telemetry: {
    peakGForce: number | null;
    severity: string | null;
    startLatitude: unknown;
    startLongitude: unknown;
    endLatitude: unknown;
    endLongitude: unknown;
    averageSpeedMPH: number | null;
  };
  user: {
    id: string;
    email: string | null;
    displayName: string | null;
  };
  device: {
    id: string;
    name: string;
    model: string | null;
    osVersion: string | null;
    appVersion: string | null;
  } | null;
  generatedAt: string;
}

/**
 * Render a branded PDF incident report. Returns the raw bytes plus the
 * measured size in bytes — we need both: size for DB bookkeeping, bytes for
 * the S3 upload.
 *
 * Layout notes:
 *   • Letter size, 1" margins. Keeps the template printable on standard
 *     paper for insurance / legal filings.
 *   • All metric lookup is null-safe; missing fields render as "—" rather
 *     than crashing the render (older clips may not have GPS).
 *   • No external font files — relying on pdfkit's Helvetica built-in keeps
 *     the image small and avoids a licensing surface we'd rather not own.
 */
export const renderIncidentReportPdf = async (
  payload: IncidentReportPayload,
): Promise<{ bytes: Buffer; sizeBytes: number }> => {
  const doc = new PDFDocument({
    size: 'LETTER',
    margins: { top: 72, bottom: 72, left: 72, right: 72 },
    info: {
      Title: `CarCam Pro Incident Report ${payload.clip.id}`,
      Author: 'CarCam Pro',
      Subject: 'Incident Report',
      CreationDate: new Date(payload.generatedAt),
    },
  });

  const stream = new PassThrough();
  const chunks: Buffer[] = [];
  stream.on('data', (chunk: Buffer) => chunks.push(chunk));
  const finished = new Promise<void>((resolve, reject) => {
    stream.on('end', () => resolve());
    stream.on('error', reject);
  });
  doc.pipe(stream);

  drawHeader(doc, payload);
  doc.moveDown(1.5);
  drawClipSection(doc, payload);
  doc.moveDown();
  drawTelemetrySection(doc, payload);
  doc.moveDown();
  drawLocationSection(doc, payload);
  doc.moveDown();
  drawDeviceSection(doc, payload);
  drawFooter(doc, payload);

  doc.end();
  await finished;

  const bytes = Buffer.concat(chunks);
  return { bytes, sizeBytes: bytes.byteLength };
};

// ─────────────────────────────────────────────────────────────
// Layout helpers — each draws one section; they assume the cursor is at the
// intended start position and leave it just below their last rendered line.
// ─────────────────────────────────────────────────────────────

const drawHeader = (doc: PDFKit.PDFDocument, payload: IncidentReportPayload) => {
  doc.fillColor('#0A0A0A').font('Helvetica-Bold').fontSize(22).text('CarCam Pro');
  doc.font('Helvetica').fontSize(11).fillColor('#666')
    .text('Incident Report — Confidential');
  doc.moveDown(0.5);
  doc.moveTo(doc.page.margins.left, doc.y)
    .lineTo(doc.page.width - doc.page.margins.right, doc.y)
    .lineWidth(0.5)
    .strokeColor('#CCCCCC')
    .stroke();
  doc.moveDown(0.5);

  doc.fillColor('#0A0A0A').font('Helvetica-Bold').fontSize(10)
    .text(`Report generated ${formatDateTime(payload.generatedAt)}`, { align: 'right' });
  doc.font('Helvetica').fontSize(9).fillColor('#666')
    .text(`Report ID · ${truncate(payload.clip.id)}`, { align: 'right' });
};

const drawClipSection = (doc: PDFKit.PDFDocument, payload: IncidentReportPayload) => {
  sectionHeading(doc, 'Recording');
  fieldRow(doc, 'Clip ID', payload.clip.id);
  fieldRow(doc, 'Started', formatDateTime(payload.clip.startedAt));
  fieldRow(doc, 'Ended', formatDateTime(payload.clip.endedAt));
  fieldRow(doc, 'Duration', formatDuration(payload.clip.durationSeconds));
  fieldRow(doc, 'Resolution', payload.clip.resolution);
  fieldRow(doc, 'Codec', payload.clip.codec);
};

const drawTelemetrySection = (doc: PDFKit.PDFDocument, payload: IncidentReportPayload) => {
  sectionHeading(doc, 'Incident Telemetry');
  fieldRow(
    doc,
    'Peak g-force',
    payload.telemetry.peakGForce !== null
      ? `${payload.telemetry.peakGForce.toFixed(2)} g`
      : '—',
  );
  fieldRow(doc, 'Severity', capitalize(payload.telemetry.severity) ?? '—');
  fieldRow(
    doc,
    'Avg speed',
    payload.telemetry.averageSpeedMPH !== null
      ? `${payload.telemetry.averageSpeedMPH.toFixed(1)} mph`
      : '—',
  );
};

const drawLocationSection = (doc: PDFKit.PDFDocument, payload: IncidentReportPayload) => {
  sectionHeading(doc, 'Location');
  fieldRow(
    doc,
    'Start coordinates',
    formatCoords(payload.telemetry.startLatitude, payload.telemetry.startLongitude),
  );
  fieldRow(
    doc,
    'End coordinates',
    formatCoords(payload.telemetry.endLatitude, payload.telemetry.endLongitude),
  );
};

const drawDeviceSection = (doc: PDFKit.PDFDocument, payload: IncidentReportPayload) => {
  sectionHeading(doc, 'Device');
  fieldRow(doc, 'Name', payload.device?.name ?? '—');
  fieldRow(doc, 'Model', payload.device?.model ?? '—');
  fieldRow(doc, 'iOS version', payload.device?.osVersion ?? '—');
  fieldRow(doc, 'App version', payload.device?.appVersion ?? '—');
  fieldRow(doc, 'Account', payload.user.displayName ?? payload.user.email ?? truncate(payload.user.id));
};

const drawFooter = (doc: PDFKit.PDFDocument, payload: IncidentReportPayload) => {
  const bottom = doc.page.height - doc.page.margins.bottom + 12;
  doc.fontSize(8).fillColor('#999').font('Helvetica')
    .text(
      `This report is generated from on-device telemetry captured by CarCam Pro. ` +
      `All timestamps are in UTC. Report ID ${truncate(payload.clip.id)}.`,
      doc.page.margins.left,
      bottom,
      { width: doc.page.width - doc.page.margins.left - doc.page.margins.right, align: 'center' },
    );
};

const sectionHeading = (doc: PDFKit.PDFDocument, label: string) => {
  doc.moveDown(0.8);
  doc.font('Helvetica-Bold').fontSize(13).fillColor('#0A0A0A').text(label.toUpperCase(), {
    characterSpacing: 0.8,
  });
  doc.moveTo(doc.page.margins.left, doc.y + 2)
    .lineTo(doc.page.width - doc.page.margins.right, doc.y + 2)
    .lineWidth(0.25).strokeColor('#DDDDDD').stroke();
  doc.moveDown(0.5);
};

const fieldRow = (doc: PDFKit.PDFDocument, label: string, value: string) => {
  const labelWidth = 140;
  const y = doc.y;
  doc.font('Helvetica').fontSize(10).fillColor('#666')
    .text(label, doc.page.margins.left, y, { width: labelWidth });
  doc.font('Helvetica').fontSize(10).fillColor('#0A0A0A')
    .text(value, doc.page.margins.left + labelWidth, y, {
      width: doc.page.width - doc.page.margins.left - doc.page.margins.right - labelWidth,
    });
};

// ─────────────────────────────────────────────────────────────
// Formatting helpers
// ─────────────────────────────────────────────────────────────

const formatDateTime = (iso: string): string => {
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return '—';
  return d.toISOString().replace('T', ' ').slice(0, 19) + ' UTC';
};

const formatDuration = (seconds: number): string => {
  if (!Number.isFinite(seconds) || seconds <= 0) return '—';
  const s = Math.round(seconds);
  const m = Math.floor(s / 60);
  const r = s % 60;
  return m > 0 ? `${m}m ${r}s` : `${r}s`;
};

const formatCoords = (lat: unknown, lng: unknown): string => {
  const a = coerceNumber(lat);
  const b = coerceNumber(lng);
  if (a === null || b === null) return '—';
  return `${a.toFixed(6)}, ${b.toFixed(6)}`;
};

const coerceNumber = (value: unknown): number | null => {
  if (value === null || value === undefined) return null;
  const n = typeof value === 'number' ? value : Number(value);
  return Number.isFinite(n) ? n : null;
};

const capitalize = (v: string | null): string | null =>
  v ? v.charAt(0).toUpperCase() + v.slice(1) : null;

/** Shorten a ULID to the canonical first-7 / last-4 split for display. */
const truncate = (s: string): string =>
  s.length <= 12 ? s : `${s.slice(0, 7)}…${s.slice(-4)}`;
