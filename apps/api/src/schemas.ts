import { z } from 'zod';

export const BrandCreateSchema = z.object({
  name: z.string().min(1),
  voiceTone: z.string().default('Clear, warm, professional'),
  prohibitedTopics: z.string().default(''),
  targetAudience: z.string().default('General'),
  channels: z.array(z.string()).default(['FB','IG']),
});

export const PersonaCreateSchema = z.object({
  brandId: z.string().min(1),
  name: z.string().min(1),
  styleGuide: z.string().default(''),
  doDont: z.object({
    do: z.array(z.string()).default([]),
    dont: z.array(z.string()).default([]),
  }).default({ do: [], dont: [] }),
  examples: z.array(z.string()).default([]),
});

export const PlanCreateSchema = z.object({
  brandId: z.string().min(1),
  scheduledAt: z.string().datetime(),
  channel: z.string().min(1),
  seriesId: z.string().optional(),
  objective: z.string().min(1),
  cta: z.string().default(''),
  assetRequirements: z.string().default(''),
});

export const PlanListQuerySchema = z.object({
  from: z.string().datetime().optional(),
  to: z.string().datetime().optional(),
  channel: z.string().optional(),
});

export const JobGenerateSchema = z.object({
  planId: z.string().optional(),
  brandId: z.string().min(1).optional(),
  personaId: z.string().optional(),
  topic: z.string().min(1),
  objective: z.string().min(1),
  platforms: z.array(z.enum(['facebook', 'instagram', 'tiktok', 'youtube'])).default(['facebook']),
  options: z.object({
    language: z.enum(['th','en']).default('th'),
    deterministicSeed: z.string().optional(),
    tone: z.string().optional(),
    length: z.enum(['short', 'medium', 'long']).optional(),
  }).default({ language: 'th' }),
});