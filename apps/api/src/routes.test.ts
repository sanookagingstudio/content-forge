import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import Fastify from 'fastify';
import { registerRoutes } from './routes';
import { PrismaClient } from '@prisma/client';
import { prisma } from './db';

describe('API Routes', () => {
  let app: ReturnType<typeof Fastify>;

  beforeEach(async () => {
    app = Fastify({ logger: false });
    await app.register(registerRoutes);
    await app.ready();
  });

  afterEach(async () => {
    await app.close();
  });

  it('GET /health returns 200 with ok:true', async () => {
    const response = await app.inject({
      method: 'GET',
      url: '/health'
    });

    expect(response.statusCode).toBe(200);
    const body = JSON.parse(response.body);
    expect(body.ok).toBe(true);
    expect(body.service).toBe('api');
    expect(body.ts).toBeDefined();
  });

  it('GET /v1/brands returns 200 with ok:true', async () => {
    const response = await app.inject({
      method: 'GET',
      url: '/v1/brands'
    });

    expect(response.statusCode).toBe(200);
    const body = JSON.parse(response.body);
    expect(body.ok).toBe(true);
    expect(Array.isArray(body.data)).toBe(true);
  });
});

