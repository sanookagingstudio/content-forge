import { FastifyInstance } from 'fastify';
import { prisma } from './db';
import { apiError, fromZod } from './errors';
import { ZodError } from 'zod';
import {
  BrandCreateSchema,
  PersonaCreateSchema,
  PlanCreateSchema,
  PlanListQuerySchema,
  JobGenerateSchema
} from './schemas';
import { generateDeterministic } from './generator';
import { generateContentV3 } from './generator-v3';
import { analyzeInputs } from './jarvis';
import fs from 'node:fs';
import path from 'node:path';

export async function registerRoutes(app: FastifyInstance) {
  app.get('/health', async () => {
    return { ok: true, service: 'api', ts: new Date().toISOString() };
  });

  // Brands
  app.get('/v1/brands', async () => {
    const brands = await prisma.brand.findMany({ orderBy: { createdAt: 'desc' } });
    return { ok: true, data: brands.map(b => ({ ...b, channels: safeJson(b.channelsJson, []) })) };
  });

  app.post('/v1/brands', async (req, reply) => {
    try {
      const body = BrandCreateSchema.parse(req.body ?? {});
      const created = await prisma.brand.create({
        data: {
          name: body.name,
          voiceTone: body.voiceTone,
          prohibitedTopics: body.prohibitedTopics,
          targetAudience: body.targetAudience,
          channelsJson: JSON.stringify(body.channels),
        }
      });
      reply.code(201);
      return { ok: true, data: { ...created, channels: body.channels } };
    } catch (e: any) {
      reply.code(400);
      if (e instanceof Error && e.name === 'ZodError') {
        return fromZod(e);
      }
      // Log actual error for debugging
      app.log.error({ error: e, message: e?.message, stack: e?.stack }, 'Brand creation error');
      return apiError('UNKNOWN_ERROR', e?.message || 'Unexpected error', e);
    }
  });

  // Personas
  app.get('/v1/personas', async () => {
    const personas = await prisma.persona.findMany({ orderBy: { createdAt: 'desc' } });
    return { ok: true, data: personas.map(p => ({
      ...p,
      doDont: safeJson(p.doDontJson, { do: [], dont: [] }),
      examples: safeJson(p.examplesJson, []),
    })) };
  });

  app.post('/v1/personas', async (req, reply) => {
    try {
      const body = PersonaCreateSchema.parse(req.body ?? {});
      const brand = await prisma.brand.findUnique({ where: { id: body.brandId } });
      if (!brand) {
        reply.code(404);
        return apiError('NOT_FOUND', 'Brand not found');
      }
      const created = await prisma.persona.create({
        data: {
          brandId: body.brandId,
          name: body.name,
          styleGuide: body.styleGuide,
          doDontJson: JSON.stringify(body.doDont),
          examplesJson: JSON.stringify(body.examples),
        }
      });
      reply.code(201);
      return { ok: true, data: { ...created, doDont: body.doDont, examples: body.examples } };
    } catch (e) {
      reply.code(400);
      return fromZod(e);
    }
  });

  // Plans
  app.get('/v1/plans', async (req, reply) => {
    try {
      const q = PlanListQuerySchema.parse((req.query ?? {}) as any);
      const where: any = {};
      if (q.channel) where.channel = q.channel;
      if (q.from || q.to) {
        where.scheduledAt = {};
        if (q.from) where.scheduledAt.gte = new Date(q.from);
        if (q.to) where.scheduledAt.lte = new Date(q.to);
      }
      const plans = await prisma.contentPlan.findMany({
        where,
        orderBy: { scheduledAt: 'asc' },
        include: { series: true, brand: true }
      });
      return { ok: true, data: plans };
    } catch (e) {
      reply.code(400);
      return fromZod(e);
    }
  });

  app.post('/v1/plans', async (req, reply) => {
    try {
      const body = PlanCreateSchema.parse(req.body ?? {});
      const brand = await prisma.brand.findUnique({ where: { id: body.brandId } });
      if (!brand) {
        reply.code(404);
        return apiError('NOT_FOUND', 'Brand not found');
      }
      const created = await prisma.contentPlan.create({
        data: {
          brandId: body.brandId,
          scheduledAt: new Date(body.scheduledAt),
          channel: body.channel,
          seriesId: body.seriesId ?? null,
          objective: body.objective,
          cta: body.cta,
          assetRequirements: body.assetRequirements,
        }
      });
      reply.code(201);
      return { ok: true, data: created };
    } catch (e) {
      reply.code(400);
      return fromZod(e);
    }
  });

  // Jobs
  app.post('/v1/jobs/generate', async (req, reply) => {
    try {
      const body = JobGenerateSchema.parse(req.body ?? {});
      
      // Support both planId-based and direct brandId-based generation
      let brand;
      let plan = null;
      let persona = null;

      if (body.planId) {
        plan = await prisma.contentPlan.findUnique({
          where: { id: body.planId },
          include: { brand: true, series: true }
        });
        if (!plan) {
          reply.code(404);
          return apiError('NOT_FOUND', 'Plan not found');
        }
        brand = plan.brand;
      } else if (body.brandId) {
        brand = await prisma.brand.findUnique({ where: { id: body.brandId } });
        if (!brand) {
          reply.code(404);
          return apiError('NOT_FOUND', 'Brand not found');
        }
      } else {
        reply.code(400);
        return apiError('VALIDATION_ERROR', 'Either planId or brandId must be provided');
      }

      if (body.personaId) {
        persona = await prisma.persona.findUnique({ where: { id: body.personaId } });
      }

      // Run Jarvis advisory
      const advisory = analyzeInputs({
        brandName: brand.name,
        voiceTone: brand.voiceTone,
        topic: body.topic,
        objective: body.objective,
        personaName: persona?.name,
        platforms: body.platforms,
      });

      // Create job
      const job = await prisma.contentJob.create({
        data: {
          planId: plan?.id || 'direct',
          status: 'queued',
          inputsJson: JSON.stringify(body),
          outputsJson: JSON.stringify({}),
          advisoryJson: JSON.stringify(advisory),
          costJson: JSON.stringify({ tokens: 0, currency: 'N/A' }),
          logsJson: JSON.stringify([{ at: new Date().toISOString(), msg: 'Queued' }]),
        }
      });

      // Generate content (V3 - structured output)
      const seed = body.options?.deterministicSeed ?? job.id;
      const generatedContent = generateContentV3({
        brandName: brand.name,
        voiceTone: brand.voiceTone,
        prohibitedTopics: brand.prohibitedTopics,
        targetAudience: brand.targetAudience,
        topic: body.topic,
        objective: body.objective,
        cta: plan?.cta || '',
        platforms: body.platforms,
        language: body.options?.language ?? 'th',
        seed,
        personaName: persona?.name,
      });

      // Save artifact
      const artifactsDir = path.join(process.cwd(), 'artifacts', 'jobs');
      fs.mkdirSync(artifactsDir, { recursive: true });
      const artifactPath = path.join(artifactsDir, `${job.id}.json`);
      fs.writeFileSync(artifactPath, JSON.stringify({
        jobId: job.id,
        planId: plan?.id || null,
        createdAt: new Date().toISOString(),
        advisory,
        outputs: generatedContent,
      }, null, 2), 'utf8');

      // Update job with outputs
      const updated = await prisma.contentJob.update({
        where: { id: job.id },
        data: {
          status: 'succeeded',
          outputsJson: JSON.stringify(generatedContent),
          logsJson: JSON.stringify([
            { at: new Date().toISOString(), msg: 'Queued' },
            { at: new Date().toISOString(), msg: 'Generated content (V3)', artifactPath },
          ]),
        }
      });

      reply.code(201);
      return { 
        ok: true, 
        data: { 
          ...updated, 
          advisory,
          outputs: generatedContent, 
          artifactPath 
        } 
      };
    } catch (e: any) {
      reply.code(400);
      if (e instanceof Error && e.name === 'ZodError') {
        return fromZod(e);
      }
      app.log.error({ error: e, message: e?.message, stack: e?.stack }, 'Job generation error');
      return apiError('UNKNOWN_ERROR', e?.message || 'Unexpected error', e);
    }
  });

  app.get('/v1/jobs/:id', async (req, reply) => {
    const id = (req.params as any)?.id as string;
    const job = await prisma.contentJob.findUnique({ 
      where: { id }, 
      include: { plan: { include: { brand: true, series: true } }, assets: true } 
    });
    if (!job) {
      reply.code(404);
      return apiError('NOT_FOUND', 'Job not found');
    }
    return {
      ok: true,
      data: {
        ...job,
        inputs: safeJson(job.inputsJson, {}),
        outputs: safeJson(job.outputsJson, {}),
        advisory: safeJson(job.advisoryJson, { warnings: [], suggestions: [] }),
        cost: safeJson(job.costJson, {}),
        logs: safeJson(job.logsJson, []),
      }
    };
  });
}

function safeJson<T>(s: string, fallback: T): T {
  try { return JSON.parse(s) as T; } catch { return fallback; }
}