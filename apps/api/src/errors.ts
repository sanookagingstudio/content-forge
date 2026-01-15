import { ZodError } from 'zod';

export type ApiErrorShape = {
  ok: false;
  error: {
    code: string;
    message: string;
    details?: unknown;
  };
};

export function apiError(code: string, message: string, details?: unknown): ApiErrorShape {
  return { ok: false, error: { code, message, details } };
}

export function fromZod(err: unknown): ApiErrorShape {
  if (err instanceof ZodError) {
    return apiError('VALIDATION_ERROR', 'Invalid request', err.flatten());
  }
  return apiError('UNKNOWN_ERROR', 'Unexpected error');
}