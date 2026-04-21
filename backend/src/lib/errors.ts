/**
 * Typed application errors. Every route handler throws one of these and the
 * error hook in `app.ts` renders them as a JSON envelope:
 *
 *   { error: { code, message, details? }, requestId }
 *
 * Unknown errors are caught and mapped to `INTERNAL` so we never leak stack
 * traces or Prisma error messages to the client.
 */

export type ErrorCode =
  | 'BAD_REQUEST'
  | 'UNAUTHORIZED'
  | 'FORBIDDEN'
  | 'NOT_FOUND'
  | 'CONFLICT'
  | 'GONE'
  | 'UNPROCESSABLE'
  | 'RATE_LIMITED'
  | 'PAYMENT_REQUIRED'
  | 'INTERNAL'
  | 'UPSTREAM';

export class AppError extends Error {
  readonly code: ErrorCode;
  readonly statusCode: number;
  readonly details?: unknown;

  constructor(params: { code: ErrorCode; message: string; statusCode: number; details?: unknown }) {
    super(params.message);
    this.name = 'AppError';
    this.code = params.code;
    this.statusCode = params.statusCode;
    this.details = params.details;
  }
}

export const Errors = {
  badRequest: (message: string, details?: unknown) =>
    new AppError({ code: 'BAD_REQUEST', message, statusCode: 400, details }),

  unauthorized: (message = 'Authentication required') =>
    new AppError({ code: 'UNAUTHORIZED', message, statusCode: 401 }),

  forbidden: (message = 'Forbidden') =>
    new AppError({ code: 'FORBIDDEN', message, statusCode: 403 }),

  notFound: (resource: string) =>
    new AppError({ code: 'NOT_FOUND', message: `${resource} not found`, statusCode: 404 }),

  conflict: (message: string) => new AppError({ code: 'CONFLICT', message, statusCode: 409 }),

  gone: (message: string) => new AppError({ code: 'GONE', message, statusCode: 410 }),

  unprocessable: (message: string, details?: unknown) =>
    new AppError({ code: 'UNPROCESSABLE', message, statusCode: 422, details }),

  rateLimited: (retryAfterSeconds: number) =>
    new AppError({
      code: 'RATE_LIMITED',
      message: 'Too many requests',
      statusCode: 429,
      details: { retryAfterSeconds },
    }),

  paymentRequired: (message = 'Active subscription required') =>
    new AppError({ code: 'PAYMENT_REQUIRED', message, statusCode: 402 }),

  internal: (message = 'Internal server error') =>
    new AppError({ code: 'INTERNAL', message, statusCode: 500 }),

  upstream: (message: string) =>
    new AppError({ code: 'UPSTREAM', message, statusCode: 502 }),
};
