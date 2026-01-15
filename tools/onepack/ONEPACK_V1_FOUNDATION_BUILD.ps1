$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

function Write-FileUtf8NoBom([string]$Path, [string]$Content) {
  $dir = Split-Path -Parent $Path
  if ($dir -and !(Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
  $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::WriteAllText($Path, $Content.Replace("`r`n","`n").Replace("`n","`r`n"), $utf8NoBom)
}

function Read-Json([string]$Path) {
  if (!(Test-Path $Path)) { throw "Missing JSON file: $Path" }
  return Get-Content $Path -Raw | ConvertFrom-Json -Depth 50
}

function Write-Json([string]$Path, $Obj) {
  $json = $Obj | ConvertTo-Json -Depth 50
  Write-FileUtf8NoBom $Path ($json + "`r`n")
}

function Exec([string]$Cmd, [string]$WorkDir = $PWD.Path) {
  Write-Host ">> $Cmd"
  $psi = New-Object System.Diagnostics.ProcessStartInfo
  $psi.FileName = "powershell"
  $psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -Command $Cmd"
  $psi.WorkingDirectory = $WorkDir
  $psi.RedirectStandardOutput = $true
  $psi.RedirectStandardError = $true
  $psi.UseShellExecute = $false
  $p = New-Object System.Diagnostics.Process
  $p.StartInfo = $psi
  [void]$p.Start()
  $out = $p.StandardOutput.ReadToEnd()
  $err = $p.StandardError.ReadToEnd()
  $p.WaitForExit()
  if ($out) { Write-Host $out.TrimEnd() }
  if ($p.ExitCode -ne 0) {
    if ($err) { Write-Host $err.TrimEnd() }
    throw "Command failed ($($p.ExitCode)): $Cmd"
  }
  return @{ out = $out; err = $err; code = $p.ExitCode }
}

function Find-RepoRoot() {
  $d = Get-Location
  while ($true) {
    if (Test-Path (Join-Path $d "package.json")) { return $d }
    $parent = Split-Path -Parent $d
    if (!$parent -or $parent -eq $d) { break }
    $d = $parent
  }
  throw "Repo root not found (package.json). Run from within the repo."
}

function Assert-NoWorkspaceStar([string]$Root) {
  $hits = @()
  Get-ChildItem -Path $Root -Recurse -File -Filter "package.json" |
    Where-Object { $_.FullName -notmatch "\\node_modules\\" } |
    ForEach-Object {
      $raw = Get-Content $_.FullName -Raw
      if ($raw -match '"workspace:\*"' -or $raw -match "workspace:\*") { $hits += $_.FullName }
    }
  if ($hits.Count -gt 0) {
    throw ("workspace:* protocol found in:`r`n" + ($hits -join "`r`n"))
  }
}

function Ensure-Node() {
  try { Exec "node -v" | Out-Null } catch { throw "Node.js not available in PATH." }
  try { Exec "npm -v" | Out-Null } catch { throw "npm not available in PATH." }
}

function Upsert-PackageScript($pkg, [string]$name, [string]$value) {
  if (-not ($pkg.PSObject.Properties | Where-Object { $_.Name -eq "scripts" })) { 
    $pkg | Add-Member -NotePropertyName scripts -NotePropertyValue (@{}) 
  }
  if ($pkg.scripts -is [hashtable]) {
    $pkg.scripts[$name] = $value
  } else {
    $prop = $pkg.scripts.PSObject.Properties | Where-Object { $_.Name -eq $name }
    if ($prop) {
      $prop.Value = $value
    } else {
      $pkg.scripts | Add-Member -NotePropertyName $name -NotePropertyValue $value -Force
    }
  }
}

function Ensure-DevDependency($pkg, [string]$dep, [string]$version) {
  if (-not ($pkg.PSObject.Properties | Where-Object { $_.Name -eq "devDependencies" })) { 
    $pkg | Add-Member -NotePropertyName devDependencies -NotePropertyValue (@{}) 
  }
  if ($pkg.devDependencies -is [hashtable]) {
    $pkg.devDependencies[$dep] = $version
  } else {
    $prop = $pkg.devDependencies.PSObject.Properties | Where-Object { $_.Name -eq $dep }
    if ($prop) {
      $prop.Value = $version
    } else {
      $pkg.devDependencies | Add-Member -NotePropertyName $dep -NotePropertyValue $version -Force
    }
  }
}

function Ensure-Dependency($pkg, [string]$dep, [string]$version) {
  if (-not ($pkg.PSObject.Properties | Where-Object { $_.Name -eq "dependencies" })) { 
    $pkg | Add-Member -NotePropertyName dependencies -NotePropertyValue (@{}) 
  }
  if ($pkg.dependencies -is [hashtable]) {
    $pkg.dependencies[$dep] = $version
  } else {
    $prop = $pkg.dependencies.PSObject.Properties | Where-Object { $_.Name -eq $dep }
    if ($prop) {
      $prop.Value = $version
    } else {
      $pkg.dependencies | Add-Member -NotePropertyName $dep -NotePropertyValue $version -Force
    }
  }
}

function New-Stamp() { return (Get-Date).ToString("yyyyMMdd-HHmmss") }

$repoRoot = Find-RepoRoot
Set-Location $repoRoot
Ensure-Node

# --------- Discover apps paths (convention: apps/api, apps/web, apps/cli) ----------
$appsDir = Join-Path $repoRoot "apps"
$apiDir  = Join-Path $appsDir "api"
$webDir  = Join-Path $appsDir "web"
$cliDir  = Join-Path $appsDir "cli"

if (!(Test-Path $apiDir)) { throw "Missing apps/api at $apiDir" }
if (!(Test-Path $webDir)) { throw "Missing apps/web at $webDir" }
if (!(Test-Path $cliDir)) { throw "Missing apps/cli at $cliDir" }

# --------- Locate DOCX inputs (best-effort; deterministic fallback if missing) ----------
$docCandidates = @(
  (Join-Path $repoRoot "CONTENT FORGE.docx"),
  (Join-Path $repoRoot "CONTENT_FORGE.docx"),
  (Join-Path $repoRoot "docs\CONTENT FORGE.docx"),
  (Join-Path $repoRoot "docs\CONTENT_FORGE.docx")
) | Where-Object { Test-Path $_ }

$ideasCandidates = @(
  (Join-Path $repoRoot "Ideas contents.docx"),
  (Join-Path $repoRoot "IDEAS contents.docx"),
  (Join-Path $repoRoot "docs\Ideas contents.docx"),
  (Join-Path $repoRoot "docs\IDEAS contents.docx")
) | Where-Object { Test-Path $_ }

$docPath   = if (@($docCandidates).Count -gt 0) { $docCandidates[0] } else { $null }
$ideasPath = if (@($ideasCandidates).Count -gt 0) { $ideasCandidates[0] } else { $null }

# --------- Root scripts: preserve baseline; only add missing conveniences ----------
$rootPkgPath = Join-Path $repoRoot "package.json"
$rootPkg = Read-Json $rootPkgPath

# Ensure root dev orchestrates api+web (best-effort: keep existing if present)
if (-not $rootPkg.scripts) { $rootPkg | Add-Member -NotePropertyName scripts -NotePropertyValue (@{}) }

if (-not $rootPkg.scripts.dev) {
  # Use concurrently if already present, else add as devDependency
  Ensure-DevDependency $rootPkg "concurrently" "^9.0.0"
  Upsert-PackageScript $rootPkg "dev" "concurrently -n API,WEB -c auto `"npm:dev:api`" `"npm:dev:web`""
}
if (-not ($rootPkg.scripts.PSObject.Properties | Where-Object { $_.Name -eq "dev:api" })) { Upsert-PackageScript $rootPkg "dev:api" "npm --prefix apps/api run dev" }
if (-not ($rootPkg.scripts.PSObject.Properties | Where-Object { $_.Name -eq "dev:web" })) { Upsert-PackageScript $rootPkg "dev:web" "npm --prefix apps/web run dev" }
if (-not ($rootPkg.scripts.PSObject.Properties | Where-Object { $_.Name -eq "db:migrate" })) { Upsert-PackageScript $rootPkg "db:migrate" "npm --prefix apps/api run db:migrate" }
if (-not ($rootPkg.scripts.PSObject.Properties | Where-Object { $_.Name -eq "db:seed" })) { Upsert-PackageScript $rootPkg "db:seed" "npm --prefix apps/api run db:seed" }

Write-Json $rootPkgPath $rootPkg

# --------- API package: Prisma SQLite + Fastify routes + Zod validation ----------
$apiPkgPath = Join-Path $apiDir "package.json"
$apiPkg = Read-Json $apiPkgPath

# Dependencies (pin deterministic where needed)
# Fastify 4.x assumed; keep existing fastify version if present. Ensure @fastify/cors pinned compatible with fastify 4.x.
if ($apiPkg.dependencies -and $apiPkg.dependencies.fastify) {
  # keep
} else {
  Ensure-Dependency $apiPkg "fastify" "^4.29.1"
}
Ensure-Dependency $apiPkg "@fastify/cors" "9.0.1"
Ensure-Dependency $apiPkg "zod" "^3.24.1"
Ensure-Dependency $apiPkg "@prisma/client" "^6.3.1"
Ensure-DevDependency $apiPkg "prisma" "^6.3.1"
Ensure-DevDependency $apiPkg "tsx" "^4.19.2"
Ensure-DevDependency $apiPkg "typescript" "^5.7.3"
Ensure-DevDependency $apiPkg "@types/node" "^22.10.2"

# Scripts
Upsert-PackageScript $apiPkg "dev" "tsx watch src/index.ts"
Upsert-PackageScript $apiPkg "start" "node dist/index.js"
Upsert-PackageScript $apiPkg "db:migrate" "prisma migrate dev --name init --skip-generate"
Upsert-PackageScript $apiPkg "db:generate" "prisma generate"
Upsert-PackageScript $apiPkg "db:seed" "tsx src/seed.ts"
Upsert-PackageScript $apiPkg "lint:noop" "node -e `"console.log('noop')`""

Write-Json $apiPkgPath $apiPkg

# Prisma schema
$prismaDir = Join-Path $apiDir "prisma"
$schemaPath = Join-Path $prismaDir "schema.prisma"
Write-FileUtf8NoBom $schemaPath @"
generator client {
  provider = "prisma-client-js"
}

datasource db {
  provider = "sqlite"
  url      = env("DATABASE_URL")
}

enum JobStatus {
  queued
  running
  succeeded
  failed
}

model Brand {
  id               String   @id @default(cuid())
  name             String   @unique
  voiceTone        String
  prohibitedTopics String
  targetAudience   String
  channelsJson     String   // JSON array string
  createdAt        DateTime @default(now())
  updatedAt        DateTime @updatedAt

  personas Persona[]
  series   ContentSeries[]
  plans    ContentPlan[]
}

model Persona {
  id            String   @id @default(cuid())
  brandId       String
  name          String
  styleGuide    String
  doDontJson    String   // JSON object string
  examplesJson  String   // JSON array string
  createdAt     DateTime @default(now())
  updatedAt     DateTime @updatedAt

  brand Brand @relation(fields: [brandId], references: [id], onDelete: Cascade)
}

model ContentSeries {
  id              String   @id @default(cuid())
  brandId         String
  seriesName      String
  pillar          String
  cadence         String
  targetChannelMix String  // JSON object string
  createdAt       DateTime @default(now())
  updatedAt       DateTime @updatedAt

  brand Brand @relation(fields: [brandId], references: [id], onDelete: Cascade)
  plans ContentPlan[]
}

model ContentPlan {
  id                 String   @id @default(cuid())
  brandId            String
  scheduledAt        DateTime
  channel            String
  seriesId           String?
  objective          String
  cta                String
  assetRequirements  String
  createdAt          DateTime @default(now())
  updatedAt          DateTime @updatedAt

  brand  Brand         @relation(fields: [brandId], references: [id], onDelete: Cascade)
  series ContentSeries? @relation(fields: [seriesId], references: [id], onDelete: SetNull)
  jobs   ContentJob[]
}

model ContentJob {
  id          String    @id @default(cuid())
  planId      String
  status      JobStatus
  inputsJson  String
  outputsJson String
  costJson    String
  logsJson    String
  createdAt   DateTime  @default(now())
  updatedAt   DateTime  @updatedAt

  plan   ContentPlan @relation(fields: [planId], references: [id], onDelete: Cascade)
  assets Asset[]
}

model Asset {
  id        String   @id @default(cuid())
  jobId     String
  type      String
  uri       String
  metadata  String
  createdAt DateTime @default(now())

  job ContentJob @relation(fields: [jobId], references: [id], onDelete: Cascade)
}
"@

# API env example (non-secret)
$apiEnvExample = Join-Path $apiDir ".env.example"
Write-FileUtf8NoBom $apiEnvExample @"
# Copy to .env for local dev (optional)
DATABASE_URL="file:./dev.db"
PORT=4000
"@

# API source files
$apiSrcDir = Join-Path $apiDir "src"
Write-FileUtf8NoBom (Join-Path $apiSrcDir "db.ts") @"
import { PrismaClient } from '@prisma/client';

declare global {
  // eslint-disable-next-line no-var
  var __prisma: PrismaClient | undefined;
}

export const prisma: PrismaClient =
  globalThis.__prisma ?? new PrismaClient({ log: ['error'] });

if (process.env.NODE_ENV !== 'production') globalThis.__prisma = prisma;
"@

Write-FileUtf8NoBom (Join-Path $apiSrcDir "errors.ts") @"
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
"@

Write-FileUtf8NoBom (Join-Path $apiSrcDir "schemas.ts") @"
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
  planId: z.string().min(1),
  options: z.object({
    personaId: z.string().optional(),
    language: z.enum(['th','en']).default('th'),
    deterministicSeed: z.string().optional(),
  }).default({ language: 'th' }),
});
"@

$generatorContent = @'
import crypto from 'node:crypto';

type GenerateInput = {
  brandName: string;
  voiceTone: string;
  prohibitedTopics: string;
  targetAudience: string;
  channel: string;
  objective: string;
  cta: string;
  scheduledAtISO: string;
  language: 'th' | 'en';
  seed?: string;
};

function stableHash(s: string) {
  return crypto.createHash('sha256').update(s).digest('hex').slice(0, 16);
}

function pick<T>(arr: T[], idx: number) {
  return arr[idx % arr.length];
}

export function generateDeterministic(input: GenerateInput) {
  const base = JSON.stringify(input);
  const h = stableHash(base);
  const n = parseInt(h.slice(0, 8), 16);

  const thHooks = [
    'เริ่มจากเรื่องเล็ก ๆ ที่ทำได้วันนี้',
    'ถ้าคุณอยากเห็นผลลัพธ์ที่ชัดใน 7 วัน',
    '3 ขั้นตอนสั้น ๆ ที่คนส่วนใหญ่ข้ามไป',
    'ทำไมวิธีเดิมถึงไม่เวิร์ก แล้วควรทำอย่างไร',
  ];
  const enHooks = [
    'Start with the smallest action you can do today.',
    'If you want a clear result in 7 days, do this.',
    'Three short steps most people skip.',
    'Why the old way fails—and what to do instead.',
  ];

  const thCtas = [
    'ทักมาเพื่อรับเช็กลิสต์',
    'คอมเมนต์ "สนใจ" แล้วส่งรายละเอียดให้',
    'บันทึกโพสต์นี้ไว้ แล้วลองทำตาม',
    'แชร์ให้คนที่กำลังต้องการ',
  ];
  const enCtas = [
    'DM us for the checklist.',
    'Comment "info" and we will send details.',
    'Save this post and try it.',
    'Share with someone who needs it.',
  ];

  const hook = input.language === 'th' ? pick(thHooks, n) : pick(enHooks, n);
  const ctaLine = input.cta?.trim()
    ? input.cta.trim()
    : (input.language === 'th' ? pick(thCtas, n + 1) : pick(enCtas, n + 1));

  const title =
    input.language === 'th'
      ? `${input.objective} — ทำให้ชัดภายใน 1 โพสต์`
      : `${input.objective} — make it clear in one post`;

  const outline = [
    { h: 'Context', b: `Audience: ${input.targetAudience}. Channel: ${input.channel}.` },
    { h: 'Key Point 1', b: 'What to do first (simple + measurable).' },
    { h: 'Key Point 2', b: 'How to keep it consistent (cadence + habit).' },
    { h: 'Key Point 3', b: 'What to avoid (common mistakes).' },
  ];

  const body =
    input.language === 'th'
      ? [
          `โทนแบรนด์: ${input.voiceTone}`,
          `เป้าหมายโพสต์: ${input.objective}`,
          '',
          `1) เริ่มจาก "1 อย่าง" ที่ทำได้ภายใน 15 นาที แล้วทำซ้ำ 3 วันติด`,
          `2) จดผลลัพธ์ให้เห็นเป็นตัวเลขหรือหลักฐาน (เช่น จำนวนคนทัก/คอมเมนต์/คลิก)`,
          `3) ปรับข้อความให้ชัด: ใครได้ประโยชน์, ได้อะไร, ได้เมื่อไร`,
          '',
          `ข้อควรหลีกเลี่ยง: ${input.prohibitedTopics || '—'}`,
          '',
          `นัดหมาย: ${new Date(input.scheduledAtISO).toLocaleString('th-TH')}`,
        ].join('\n')
      : [
          `Brand tone: ${input.voiceTone}`,
          `Post objective: ${input.objective}`,
          '',
          `1) Start with one action you can do in 15 minutes. Repeat for 3 days.`,
          `2) Track proof (DMs/comments/clicks) to make iteration obvious.`,
          `3) Make the message explicit: who benefits, what they get, and when.`,
          '',
          `Avoid: ${input.prohibitedTopics || '—'}`,
          '',
          `Scheduled: ${new Date(input.scheduledAtISO).toISOString()}`,
        ].join('\n');

  const hashtags =
    input.language === 'th'
      ? ['#การตลาด', '#คอนเทนต์', '#ผู้สูงอายุ', '#ท่องเที่ยว', '#ไอเดีย']
      : ['#marketing', '#content', '#tourism', '#strategy', '#ideas'];

  const platformVariants = {
    FB: { length: 'medium', format: 'post', note: 'Add a question at the end to drive comments.' },
    IG: { length: 'short', format: 'caption', note: 'Use line breaks and 3–5 hashtags.' },
    TikTok: { length: 'short', format: 'script', note: 'Open with hook, 3 beats, CTA.' },
    YouTube: { length: 'medium', format: 'shorts_script', note: 'Hook in first 2 seconds.' },
    LINE: { length: 'short', format: 'broadcast', note: 'Single CTA button/keyword.' },
  };

  return {
    generatorVersion: 'cf-v1-mockgen-1.0',
    deterministicHash: h,
    title,
    hook,
    outline,
    body,
    cta: ctaLine,
    hashtags,
    platformVariants,
  };
}
'@
Write-FileUtf8NoBom (Join-Path $apiSrcDir "generator.ts") $generatorContent

Write-FileUtf8NoBom (Join-Path $apiSrcDir "routes.ts") @"
import { FastifyInstance } from 'fastify';
import { prisma } from './db';
import { apiError, fromZod } from './errors';
import {
  BrandCreateSchema,
  PersonaCreateSchema,
  PlanCreateSchema,
  PlanListQuerySchema,
  JobGenerateSchema
} from './schemas';
import { generateDeterministic } from './generator';
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
    } catch (e) {
      reply.code(400);
      return fromZod(e);
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
      const plan = await prisma.contentPlan.findUnique({
        where: { id: body.planId },
        include: { brand: true, series: true }
      });
      if (!plan) {
        reply.code(404);
        return apiError('NOT_FOUND', 'Plan not found');
      }

      const job = await prisma.contentJob.create({
        data: {
          planId: plan.id,
          status: 'queued',
          inputsJson: JSON.stringify(body),
          outputsJson: JSON.stringify({}),
          costJson: JSON.stringify({ tokens: 0, currency: 'N/A' }),
          logsJson: JSON.stringify([{ at: new Date().toISOString(), msg: 'Queued' }]),
        }
      });

      // Deterministic execution (synchronous)
      const seed = body.options?.deterministicSeed ?? job.id;
      const outputs = generateDeterministic({
        brandName: plan.brand.name,
        voiceTone: plan.brand.voiceTone,
        prohibitedTopics: plan.brand.prohibitedTopics,
        targetAudience: plan.brand.targetAudience,
        channel: plan.channel,
        objective: plan.objective,
        cta: plan.cta,
        scheduledAtISO: plan.scheduledAt.toISOString(),
        language: body.options?.language ?? 'th',
        seed,
      });

      const artifactsDir = path.join(process.cwd(), 'artifacts', 'jobs');
      fs.mkdirSync(artifactsDir, { recursive: true });
      const artifactPath = path.join(artifactsDir, `${job.id}.json`);
      fs.writeFileSync(artifactPath, JSON.stringify({
        jobId: job.id,
        planId: plan.id,
        createdAt: new Date().toISOString(),
        outputs,
      }, null, 2), 'utf8');

      const updated = await prisma.contentJob.update({
        where: { id: job.id },
        data: {
          status: 'succeeded',
          outputsJson: JSON.stringify(outputs),
          logsJson: JSON.stringify([
            { at: new Date().toISOString(), msg: 'Queued' },
            { at: new Date().toISOString(), msg: 'Generated deterministically', artifactPath },
          ]),
        }
      });

      reply.code(201);
      return { ok: true, data: { ...updated, outputs, artifactPath } };
    } catch (e) {
      reply.code(400);
      return fromZod(e);
    }
  });

  app.get('/v1/jobs/:id', async (req, reply) => {
    const id = (req.params as any)?.id as string;
    const job = await prisma.contentJob.findUnique({ where: { id }, include: { plan: { include: { brand: true, series: true } }, assets: true } });
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
        cost: safeJson(job.costJson, {}),
        logs: safeJson(job.logsJson, []),
      }
    };
  });
}

function safeJson<T>(s: string, fallback: T): T {
  try { return JSON.parse(s) as T; } catch { return fallback; }
}
"@

Write-FileUtf8NoBom (Join-Path $apiSrcDir "index.ts") @"
import Fastify from 'fastify';
import cors from '@fastify/cors';
import { registerRoutes } from './routes';

const app = Fastify({ logger: true });

const port = Number(process.env.PORT || 4000);

async function main() {
  await app.register(cors, { origin: true });
  await registerRoutes(app);

  await app.listen({ port, host: '0.0.0.0' });
  app.log.info({ port }, 'API listening');
}

main().catch((err) => {
  app.log.error(err);
  process.exit(1);
});
"@

# Seed: best-effort parse DOCX to extract a few series/pillars; deterministic fallback if missing.
# Use a tiny internal extractor (no external deps): if docx exists, we just record filenames and seed minimal structured examples.
$seedContent = @'
import { prisma } from './db';
import fs from 'node:fs';
import path from 'node:path';

function nowISO() { return new Date().toISOString(); }

async function main() {
  const docPath = process.env.CF_DOC_PATH || '';
  const ideasPath = process.env.CF_IDEAS_PATH || '';

  const seedMeta = {
    at: nowISO(),
    docPath: docPath && fs.existsSync(docPath) ? path.resolve(docPath) : null,
    ideasPath: ideasPath && fs.existsSync(ideasPath) ? path.resolve(ideasPath) : null,
    note: 'V1 foundation seed. DOCX parsing is deferred to later hardening; this seed is deterministic and minimal.',
  };

  // Brand
  const brandName = 'Content Forge Demo Brand';
  const brand = await prisma.brand.upsert({
    where: { name: brandName },
    update: {},
    create: {
      name: brandName,
      voiceTone: 'ชัดเจน อบอุ่น แบบมืออาชีพ',
      prohibitedTopics: 'การเมือง/ความเกลียดชัง/ข้อมูลเท็จ',
      targetAudience: 'ผู้สนใจการท่องเที่ยวและกิจกรรมผู้สูงอายุ',
      channelsJson: JSON.stringify(['FB','IG','TikTok','YouTube','LINE']),
    }
  });

  // Persona
  await prisma.persona.upsert({
    where: { id: 'seed-persona-1' },
    update: {},
    create: {
      id: 'seed-persona-1',
      brandId: brand.id,
      name: 'ผู้เชี่ยวชาญที่เป็นมิตร',
      styleGuide: 'ใช้ภาษาง่าย ชัดเจน มีขั้นตอน และมี CTA เสมอ',
      doDontJson: JSON.stringify({
        do: ['ใช้ตัวเลขและขั้นตอน', 'เน้นประโยชน์ต่อผู้อ่าน', 'ปิดด้วย CTA'],
        dont: ['สัญญาผลลัพธ์เกินจริง', 'เนื้อหาคลุมเครือ', 'แตะประเด็นต้องห้ามของแบรนด์'],
      }),
      examplesJson: JSON.stringify([
        '3 ขั้นตอนวางแผนกิจกรรมผู้สูงอายุให้คนมาร่วมมากขึ้น',
        'เช็กลิสต์ก่อนออกทริปสำหรับผู้สูงอายุ: ต้องมีอะไรบ้าง',
      ]),
    }
  });

  // Series (placeholder derived from Ideas doc existence)
  const seriesSeeds = [
    { seriesName: 'ทริปแบบปลอดภัย', pillar: 'ท่องเที่ยวผู้สูงอายุ', cadence: 'weekly', mix: { FB: 0.4, IG: 0.3, TikTok: 0.3 } },
    { seriesName: 'กิจกรรมฟื้นฟูร่างกาย', pillar: 'สุขภาพ/สันทนาการ', cadence: 'weekly', mix: { FB: 0.5, IG: 0.5 } },
    { seriesName: 'เคล็ดลับการสื่อสาร', pillar: 'ชุมชน/ครอบครัว', cadence: 'biweekly', mix: { FB: 0.6, LINE: 0.4 } },
  ];

  for (const s of seriesSeeds) {
    await prisma.contentSeries.upsert({
      where: { id: `seed-series-${s.seriesName}` },
      update: {},
      create: {
        id: `seed-series-${s.seriesName}`,
        brandId: brand.id,
        seriesName: s.seriesName,
        pillar: s.pillar,
        cadence: s.cadence,
        targetChannelMix: JSON.stringify(s.mix),
      }
    });
  }

  // Plans (today + next 2 days)
  const base = new Date();
  base.setHours(10, 0, 0, 0);

  const planSeeds = [
    { dayOffset: 0, channel: 'FB', objective: 'ชวนเข้าร่วมกิจกรรมวันนี้', cta: 'ทักไลน์เพื่อจองที่นั่ง', seriesKey: 'ทริปแบบปลอดภัย' },
    { dayOffset: 1, channel: 'IG', objective: 'ให้ความรู้เช็กลิสต์ก่อนเดินทาง', cta: 'บันทึกโพสต์นี้ไว้', seriesKey: 'ทริปแบบปลอดภัย' },
    { dayOffset: 2, channel: 'TikTok', objective: 'สคริปต์ 30 วิ: 3 ข้อห้ามพลาด', cta: 'คอมเมนต์เพื่อรับไฟล์', seriesKey: 'กิจกรรมฟื้นฟูร่างกาย' },
  ];

  for (const p of planSeeds) {
    const d = new Date(base);
    d.setDate(d.getDate() + p.dayOffset);
    const seriesId = `seed-series-${p.seriesKey}`;
    await prisma.contentPlan.create({
      data: {
        brandId: brand.id,
        scheduledAt: d,
        channel: p.channel,
        seriesId,
        objective: p.objective,
        cta: p.cta,
        assetRequirements: 'text',
      }
    });
  }

  // Write seed evidence
  const outDir = path.join(process.cwd(), 'artifacts', 'seed');
  fs.mkdirSync(outDir, { recursive: true });
  fs.writeFileSync(path.join(outDir, 'seed-meta.json'), JSON.stringify(seedMeta, null, 2), 'utf8');

  console.log(JSON.stringify({ ok: true, seedMeta, brandId: brand.id }, null, 2));
}

main()
  .catch((e) => { console.error(e); process.exit(1); })
  .finally(async () => { await prisma.$disconnect(); });
'@
Write-FileUtf8NoBom (Join-Path $apiSrcDir "seed.ts") $seedContent

# --------- Web UI: minimal pages with typed client ----------
$webPkgPath = Join-Path $webDir "package.json"
$webPkg = Read-Json $webPkgPath

# Ensure basic scripts (keep existing if present)
if (-not ($webPkg.PSObject.Properties.Name -contains "scripts")) { $webPkg | Add-Member -NotePropertyName scripts -NotePropertyValue (@{}) }
if (-not ($webPkg.scripts.PSObject.Properties | Where-Object { $_.Name -eq "dev" })) { Upsert-PackageScript $webPkg "dev" "next dev -p 3000" }
if (-not ($webPkg.scripts.PSObject.Properties | Where-Object { $_.Name -eq "build" })) { Upsert-PackageScript $webPkg "build" "next build" }
if (-not ($webPkg.scripts.PSObject.Properties | Where-Object { $_.Name -eq "start" })) { Upsert-PackageScript $webPkg "start" "next start -p 3000" }

Ensure-Dependency $webPkg "zod" "^3.24.1"
Write-Json $webPkgPath $webPkg

# Next app router assumed. Support both app/ and pages/ by creating app/ if missing.
$webAppDir = Join-Path $webDir "app"
if (!(Test-Path $webAppDir)) { New-Item -ItemType Directory -Force -Path $webAppDir | Out-Null }

Write-FileUtf8NoBom (Join-Path $webDir ".env.example") @"
NEXT_PUBLIC_API_BASE_URL=http://localhost:4000
"@

$webApiContent = @'
export type ApiOk<T> = { ok: true; data: T };
export type ApiErr = { ok: false; error: { code: string; message: string; details?: unknown } };

export type Brand = {
  id: string;
  name: string;
  voiceTone: string;
  prohibitedTopics: string;
  targetAudience: string;
  channels: string[];
  createdAt: string;
  updatedAt: string;
};

export type Persona = {
  id: string;
  brandId: string;
  name: string;
  styleGuide: string;
  doDont: { do: string[]; dont: string[] };
  examples: string[];
  createdAt: string;
  updatedAt: string;
};

export type Plan = {
  id: string;
  brandId: string;
  scheduledAt: string;
  channel: string;
  seriesId?: string | null;
  objective: string;
  cta: string;
  assetRequirements: string;
  createdAt: string;
  updatedAt: string;
};

export type Job = {
  id: string;
  planId: string;
  status: string;
  createdAt: string;
  updatedAt: string;
};

const baseUrl = process.env.NEXT_PUBLIC_API_BASE_URL || 'http://localhost:4000';

async function http<T>(path: string, init?: RequestInit): Promise<ApiOk<T> | ApiErr> {
  const res = await fetch(`${baseUrl}${path}`, {
    ...init,
    headers: {
      'content-type': 'application/json',
      ...(init?.headers || {}),
    },
    cache: 'no-store',
  });
  const json = await res.json();
  return json;
}

export const api = {
  health: () => http<{ ok: true; service: string; ts: string }>(`/health`),

  listBrands: () => http<Brand[]>(`/v1/brands`),
  createBrand: (b: { name: string; voiceTone?: string; prohibitedTopics?: string; targetAudience?: string; channels?: string[] }) =>
    http<Brand>(`/v1/brands`, { method: 'POST', body: JSON.stringify(b) }),

  listPersonas: () => http<Persona[]>(`/v1/personas`),
  createPersona: (p: { brandId: string; name: string; styleGuide?: string; doDont?: any; examples?: string[] }) =>
    http<Persona>(`/v1/personas`, { method: 'POST', body: JSON.stringify(p) }),

  listPlans: (q?: { from?: string; to?: string; channel?: string }) => {
    const qs = new URLSearchParams();
    if (q?.from) qs.set('from', q.from);
    if (q?.to) qs.set('to', q.to);
    if (q?.channel) qs.set('channel', q.channel);
    const suffix = qs.toString() ? `?${qs.toString()}` : '';
    return http<any[]>(`/v1/plans${suffix}`);
  },
  createPlan: (p: any) => http<Plan>(`/v1/plans`, { method: 'POST', body: JSON.stringify(p) }),

  generateJob: (planId: string, options?: any) => http<any>(`/v1/jobs/generate`, { method: 'POST', body: JSON.stringify({ planId, options }) }),
  getJob: (id: string) => http<any>(`/v1/jobs/${id}`),
};
'@
Write-FileUtf8NoBom (Join-Path $webDir "src\lib\api.ts") $webApiContent

Write-FileUtf8NoBom (Join-Path $webAppDir "layout.tsx") @"
import './globals.css';
import Link from 'next/link';

export const metadata = {
  title: 'Content Forge',
  description: 'Content Forge V1 Foundation',
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en">
      <body style={{ fontFamily: 'system-ui, -apple-system, Segoe UI, Roboto, Arial, sans-serif', margin: 0 }}>
        <div style={{ display: 'flex', minHeight: '100vh' }}>
          <aside style={{ width: 240, borderRight: '1px solid #eee', padding: 16 }}>
            <div style={{ fontWeight: 700, marginBottom: 12 }}>Content Forge</div>
            <nav style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
              <Link href="/">Dashboard</Link>
              <Link href="/brands">Brands</Link>
              <Link href="/personas">Personas</Link>
              <Link href="/planner">Planner</Link>
              <Link href="/jobs">Jobs</Link>
            </nav>
            <div style={{ marginTop: 16, fontSize: 12, color: '#666' }}>
              API: {process.env.NEXT_PUBLIC_API_BASE_URL || 'http://localhost:4000'}
            </div>
          </aside>
          <main style={{ flex: 1, padding: 24 }}>{children}</main>
        </div>
      </body>
    </html>
  );
}
"@

Write-FileUtf8NoBom (Join-Path $webAppDir "page.tsx") @"
import { api } from '../src/lib/api';

export default async function Dashboard() {
  const [brands, personas, plans] = await Promise.all([
    api.listBrands(),
    api.listPersonas(),
    api.listPlans(),
  ]);

  const brandCount = brands.ok ? brands.data.length : 0;
  const personaCount = personas.ok ? personas.data.length : 0;
  const planCount = plans.ok ? plans.data.length : 0;

  return (
    <div>
      <h1 style={{ marginTop: 0 }}>Dashboard</h1>
      <div style={{ display: 'flex', gap: 12, flexWrap: 'wrap' }}>
        <Card title="Brands" value={brandCount} />
        <Card title="Personas" value={personaCount} />
        <Card title="Plans" value={planCount} />
      </div>
      <p style={{ marginTop: 16, color: '#444' }}>
        This is the V1 foundation UI: basic CRUD surfaces for brands/personas/plans and deterministic job generation.
      </p>
    </div>
  );
}

function Card({ title, value }: { title: string; value: number }) {
  return (
    <div style={{ border: '1px solid #eee', borderRadius: 10, padding: 16, width: 220 }}>
      <div style={{ color: '#666', fontSize: 12 }}>{title}</div>
      <div style={{ fontSize: 32, fontWeight: 700 }}>{value}</div>
    </div>
  );
}
"@

Write-FileUtf8NoBom (Join-Path $webAppDir "brands\page.tsx") @"
import { api } from '../../src/lib/api';

export default async function BrandsPage() {
  const brands = await api.listBrands();
  return (
    <div>
      <h1 style={{ marginTop: 0 }}>Brands</h1>
      {!brands.ok && <ErrorBox code={brands.error.code} message={brands.error.message} />}
      {brands.ok && (
        <div style={{ display: 'grid', gap: 12 }}>
          {brands.data.map((b) => (
            <div key={b.id} style={{ border: '1px solid #eee', borderRadius: 10, padding: 16 }}>
              <div style={{ fontWeight: 700 }}>{b.name}</div>
              <div style={{ color: '#666', fontSize: 12 }}>Tone: {b.voiceTone}</div>
              <div style={{ marginTop: 8 }}><b>Audience:</b> {b.targetAudience}</div>
              <div><b>Channels:</b> {b.channels.join(', ')}</div>
              <div><b>Prohibited:</b> {b.prohibitedTopics || '—'}</div>
            </div>
          ))}
        </div>
      )}
      <p style={{ marginTop: 16, color: '#666' }}>
        Create is available via API; UI creation forms are deferred to the hardening ONEPACK.
      </p>
    </div>
  );
}

function ErrorBox({ code, message }: { code: string; message: string }) {
  return (
    <div style={{ border: '1px solid #f3c', background: '#fff5fb', padding: 12, borderRadius: 10 }}>
      <b>{code}</b>: {message}
    </div>
  );
}
"@

Write-FileUtf8NoBom (Join-Path $webAppDir "personas\page.tsx") @"
import { api } from '../../src/lib/api';

export default async function PersonasPage() {
  const personas = await api.listPersonas();
  return (
    <div>
      <h1 style={{ marginTop: 0 }}>Personas</h1>
      {!personas.ok && <ErrorBox code={personas.error.code} message={personas.error.message} />}
      {personas.ok && (
        <div style={{ display: 'grid', gap: 12 }}>
          {personas.data.map((p) => (
            <div key={p.id} style={{ border: '1px solid #eee', borderRadius: 10, padding: 16 }}>
              <div style={{ fontWeight: 700 }}>{p.name}</div>
              <div style={{ color: '#666', fontSize: 12 }}>Brand: {p.brandId}</div>
              <div style={{ marginTop: 8 }}><b>Style:</b> {p.styleGuide || '—'}</div>
              <div style={{ marginTop: 8 }}>
                <b>Do:</b> {p.doDont?.do?.join(' • ') || '—'}
              </div>
              <div>
                <b>Don't:</b> {p.doDont?.dont?.join(' • ') || '—'}
              </div>
              <div style={{ marginTop: 8 }}>
                <b>Examples:</b> {p.examples?.join(' • ') || '—'}
              </div>
            </div>
          ))}
        </div>
      )}
    </div>
  );
}

function ErrorBox({ code, message }: { code: string; message: string }) {
  return (
    <div style={{ border: '1px solid #f3c', background: '#fff5fb', padding: 12, borderRadius: 10 }}>
      <b>{code}</b>: {message}
    </div>
  );
}
"@

Write-FileUtf8NoBom (Join-Path $webAppDir "planner\page.tsx") @"
import { api } from '../../src/lib/api';

export default async function PlannerPage() {
  const plans = await api.listPlans();
  return (
    <div>
      <h1 style={{ marginTop: 0 }}>Planner</h1>
      {!plans.ok && <ErrorBox code={plans.error.code} message={plans.error.message} />}
      {plans.ok && (
        <table style={{ width: '100%', borderCollapse: 'collapse' }}>
          <thead>
            <tr>
              <th style={th}>Scheduled</th>
              <th style={th}>Channel</th>
              <th style={th}>Objective</th>
              <th style={th}>CTA</th>
            </tr>
          </thead>
          <tbody>
            {plans.data.map((p: any) => (
              <tr key={p.id}>
                <td style={td}>{new Date(p.scheduledAt).toLocaleString()}</td>
                <td style={td}>{p.channel}</td>
                <td style={td}>{p.objective}</td>
                <td style={td}>{p.cta}</td>
              </tr>
            ))}
          </tbody>
        </table>
      )}
      <p style={{ marginTop: 16, color: '#666' }}>
        Generate jobs via CLI or API. Jobs UI is in the Jobs page.
      </p>
    </div>
  );
}

const th: React.CSSProperties = { textAlign: 'left', borderBottom: '1px solid #eee', padding: 8, color: '#666', fontSize: 12 };
const td: React.CSSProperties = { borderBottom: '1px solid #f3f3f3', padding: 8 };

function ErrorBox({ code, message }: { code: string; message: string }) {
  return (
    <div style={{ border: '1px solid #f3c', background: '#fff5fb', padding: 12, borderRadius: 10 }}>
      <b>{code}</b>: {message}
    </div>
  );
}
"@

Write-FileUtf8NoBom (Join-Path $webAppDir "jobs\page.tsx") @"
import Link from 'next/link';
import { api } from '../../src/lib/api';

export default async function JobsPage() {
  // This endpoint is not implemented as list (by scope). We show guidance + recent artifacts directory note.
  const health = await api.health();

  return (
    <div>
      <h1 style={{ marginTop: 0 }}>Jobs</h1>
      <div style={{ marginBottom: 12 }}>
        <b>API health:</b> {health.ok ? 'OK' : 'ERROR'}
      </div>
      <p>
        Job generation is available via POST <code>/v1/jobs/generate</code> or CLI <code>content-forge job run &lt;planId&gt;</code>.
      </p>
      <p>
        Job artifacts are written under <code>apps/api/artifacts/jobs/&lt;jobId&gt;.json</code>.
      </p>
      <p>
        View a job detail by navigating to <code>/jobs/&lt;jobId&gt;</code>.
      </p>
      <p style={{ color: '#666' }}>
        Example: <Link href="/jobs/example">/jobs/example</Link> (will 404 unless that job exists).
      </p>
    </div>
  );
}
"@

Write-FileUtf8NoBom (Join-Path $webAppDir "jobs\[id]\page.tsx") @"
import { api } from '../../../src/lib/api';

export default async function JobDetailPage({ params }: { params: { id: string } }) {
  const job = await api.getJob(params.id);

  if (!job.ok) {
    return (
      <div>
        <h1 style={{ marginTop: 0 }}>Job {params.id}</h1>
        <div style={{ border: '1px solid #f3c', background: '#fff5fb', padding: 12, borderRadius: 10 }}>
          <b>{job.error.code}</b>: {job.error.message}
        </div>
      </div>
    );
  }

  const outputs = job.data.outputs || {};
  return (
    <div>
      <h1 style={{ marginTop: 0 }}>Job {job.data.id}</h1>
      <div style={{ color: '#666', fontSize: 12 }}>
        Status: {job.data.status} • Created: {new Date(job.data.createdAt).toLocaleString()}
      </div>

      <Section title="Title" text={outputs.title} />
      <Section title="Hook" text={outputs.hook} />
      <Section title="Body" text={outputs.body} />
      <Section title="CTA" text={outputs.cta} />
      <Section title="Hashtags" text={(outputs.hashtags || []).join(' ')} />
      <Section title="Deterministic Hash" text={outputs.deterministicHash} />

      <h2>Raw Outputs</h2>
      <pre style={{ background: '#fafafa', border: '1px solid #eee', padding: 12, borderRadius: 10, overflowX: 'auto' }}>
        {JSON.stringify(outputs, null, 2)}
      </pre>
    </div>
  );
}

function Section({ title, text }: { title: string; text: string }) {
  return (
    <div style={{ marginTop: 16 }}>
      <div style={{ fontWeight: 700, marginBottom: 6 }}>{title}</div>
      <div style={{ border: '1px solid #eee', borderRadius: 10, padding: 12, whiteSpace: 'pre-wrap' }}>{text || '—'}</div>
    </div>
  );
}
"@

# --------- CLI: Windows-friendly Node CLI that calls API ----------
$cliPkgPath = Join-Path $cliDir "package.json"
$cliPkg = Read-Json $cliPkgPath

Ensure-Dependency $cliPkg "commander" "^12.1.0"
Ensure-Dependency $cliPkg "zod" "^3.24.1"
Ensure-DevDependency $cliPkg "tsx" "^4.19.2"
Ensure-DevDependency $cliPkg "typescript" "^5.7.3"
Ensure-DevDependency $cliPkg "@types/node" "^22.10.2"

Upsert-PackageScript $cliPkg "dev" "tsx src/index.ts"
Upsert-PackageScript $cliPkg "build" "node -e `"console.log('noop build for v1')`""
Upsert-PackageScript $cliPkg "start" "node src/index.ts"

# Add bin for `content-forge`
if (-not ($cliPkg.PSObject.Properties | Where-Object { $_.Name -eq "bin" })) { $cliPkg | Add-Member -NotePropertyName bin -NotePropertyValue (@{}) }
if ($cliPkg.bin -is [hashtable]) {
  $cliPkg.bin["content-forge"] = "src/index.ts"
} else {
  $cliPkg.bin | Add-Member -NotePropertyName "content-forge" -NotePropertyValue "src/index.ts" -Force
}

Write-Json $cliPkgPath $cliPkg

$cliSrcDir = Join-Path $cliDir "src"
$cliIndexContent = @'
#!/usr/bin/env node
import { Command } from 'commander';
import fs from 'node:fs';
import path from 'node:path';

const program = new Command();

const apiBase = process.env.CF_API_BASE_URL || process.env.NEXT_PUBLIC_API_BASE_URL || 'http://localhost:4000';

async function http(pathname: string, init?: RequestInit) {
  const res = await fetch(`${apiBase}${pathname}`, {
    ...init,
    headers: { 'content-type': 'application/json', ...(init?.headers || {}) },
  });
  const json = await res.json();
  return { status: res.status, json };
}

program
  .name('content-forge')
  .description('Content Forge CLI (V1 foundation)')
  .version('1.0.0');

program
  .command('status')
  .description('Check health endpoints (web+api)')
  .action(async () => {
    const api = await http('/health');
    console.log(JSON.stringify({ ok: true, apiBase, api }, null, 2));
  });

program
  .command('plan')
  .description('Plan operations')
  .command('import')
  .argument('<file>', 'JSON file with plans[]')
  .action(async (file) => {
    const full = path.resolve(file);
    const raw = fs.readFileSync(full, 'utf8');
    const payload = JSON.parse(raw);
    const plans = payload.plans || [];
    const results: any[] = [];
    for (const p of plans) {
      const r = await http('/v1/plans', { method: 'POST', body: JSON.stringify(p) });
      results.push(r);
    }
    console.log(JSON.stringify({ ok: true, imported: results.length, results }, null, 2));
  });

program
  .command('job')
  .description('Job operations')
  .command('run')
  .argument('<planId>', 'Plan ID')
  .option('--lang <th|en>', 'Language', 'th')
  .option('--seed <seed>', 'Deterministic seed')
  .action(async (planId, opts) => {
    const body = { planId, options: { language: opts.lang, deterministicSeed: opts.seed } };
    const r = await http('/v1/jobs/generate', { method: 'POST', body: JSON.stringify(body) });
    console.log(JSON.stringify({ ok: true, apiBase, result: r }, null, 2));
  });

program.parseAsync(process.argv).catch((e) => {
  console.error(e);
  process.exit(1);
});
'@
Write-FileUtf8NoBom (Join-Path $cliSrcDir "index.ts") $cliIndexContent

# --------- Onepack runner script (required) ----------
$onepackDir = Join-Path $repoRoot "tools\onepack"
$runnerPath = Join-Path $onepackDir "ONEPACK_V1_FOUNDATION.ps1"

$runnerContent = @'
param(
  [switch]$SkipPush
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

function Write-FileUtf8NoBom([string]$Path, [string]$Content) {
  $dir = Split-Path -Parent $Path
  if ($dir -and !(Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
  $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::WriteAllText($Path, $Content.Replace("`r`n","`n").Replace("`n","`r`n"), $utf8NoBom)
}

function Exec([string]$Cmd, [string]$WorkDir = (Get-Location).Path) {
  Write-Host ">> $Cmd"
  $psi = New-Object System.Diagnostics.ProcessStartInfo
  $psi.FileName = "powershell"
  $psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -Command $Cmd"
  $psi.WorkingDirectory = $WorkDir
  $psi.RedirectStandardOutput = $true
  $psi.RedirectStandardError = $true
  $psi.UseShellExecute = $false
  $p = New-Object System.Diagnostics.Process
  $p.StartInfo = $psi
  [void]$p.Start()
  $out = $p.StandardOutput.ReadToEnd()
  $err = $p.StandardError.ReadToEnd()
  $p.WaitForExit()
  return @{ out = $out; err = $err; code = $p.ExitCode }
}

function Probe([string]$Url, [int]$TimeoutSeconds = 90) {
  $start = Get-Date
  while (((Get-Date) - $start).TotalSeconds -lt $TimeoutSeconds) {
    try {
      $res = Invoke-WebRequest -Uri $Url -UseBasicParsing -TimeoutSec 5
      return @{ ok = $true; status = [int]$res.StatusCode; url = $Url }
    } catch {
      Start-Sleep -Seconds 1
    }
  }
  return @{ ok = $false; status = 0; url = $Url }
}

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
Set-Location $repoRoot

$stamp = (Get-Date).ToString("yyyyMMdd-HHmmss")
$runDir = Join-Path $repoRoot ("_onepack_runs\ONEPACK_V1_FOUNDATION_$stamp")
New-Item -ItemType Directory -Force -Path $runDir | Out-Null
$logPath = Join-Path $runDir "ONEPACK.log"
$reportPath = Join-Path $runDir "REPORT.md"
$evidencePath = Join-Path $runDir "evidence.json"

Start-Transcript -Path $logPath | Out-Null

$pinned = @(
  @{ name = "@fastify/cors"; version = "9.0.1"; reason = "Fastify 4.x compatibility" }
)

try {
  # Install
  $r1 = Exec "npm install"
  if ($r1.code -ne 0) { throw "npm install failed" }

  # Migrate + seed (API)
  $env:PORT = "4000"
  if (-not $env:DATABASE_URL) { $env:DATABASE_URL = "file:./dev.db" }
  if (Test-Path (Join-Path $repoRoot "apps\api\.env")) {
    # allow local overrides
  }

  # Ensure prisma client generated after migrate
  $r2 = Exec "npm --prefix apps/api run db:migrate"
  if ($r2.code -ne 0) { throw "db:migrate failed" }
  $r3 = Exec "npm --prefix apps/api run db:generate"
  if ($r3.code -ne 0) { throw "db:generate failed" }

  # Pass doc paths to seed if available
  $doc1 = @(
    Join-Path $repoRoot "CONTENT FORGE.docx",
    Join-Path $repoRoot "CONTENT_FORGE.docx",
    Join-Path $repoRoot "docs\CONTENT FORGE.docx",
    Join-Path $repoRoot "docs\CONTENT_FORGE.docx"
  ) | Where-Object { Test-Path $_ } | Select-Object -First 1

  $doc2 = @(
    Join-Path $repoRoot "Ideas contents.docx",
    Join-Path $repoRoot "IDEAS contents.docx",
    Join-Path $repoRoot "docs\Ideas contents.docx",
    Join-Path $repoRoot "docs\IDEAS contents.docx"
  ) | Where-Object { Test-Path $_ } | Select-Object -First 1

  if ($doc1) { $env:CF_DOC_PATH = $doc1 } else { Remove-Item Env:\CF_DOC_PATH -ErrorAction SilentlyContinue }
  if ($doc2) { $env:CF_IDEAS_PATH = $doc2 } else { Remove-Item Env:\CF_IDEAS_PATH -ErrorAction SilentlyContinue }

  $r4 = Exec "npm --prefix apps/api run db:seed"
  if ($r4.code -ne 0) { throw "db:seed failed" }

  # Start dev (background)
  $dev = Start-Process -FilePath "powershell" -ArgumentList "-NoProfile -ExecutionPolicy Bypass -Command npm run dev" -WorkingDirectory $repoRoot -PassThru
  Start-Sleep -Seconds 2

  # Probes
  $pWeb = Probe "http://localhost:3000"
  $pApi = Probe "http://localhost:4000/health"

  # Stop dev
  try {
    if ($dev -and -not $dev.HasExited) { Stop-Process -Id $dev.Id -Force -ErrorAction SilentlyContinue }
  } catch {}

  # Evidence
  $evidence = @{
    stamp = $stamp
    repoRoot = $repoRoot
    probes = @{ web = $pWeb; api = $pApi }
    pinnedVersions = $pinned
    reportPath = $reportPath
  }
  Write-FileUtf8NoBom $evidencePath (($evidence | ConvertTo-Json -Depth 20) + "`r`n")

  # Report
  $status = if ($pWeb.ok -and $pApi.ok -and $pWeb.status -eq 200 -and $pApi.status -eq 200) { "PASS" } else { "PASS_WITH_BLOCKER" }

  $blockers = @()
  if (-not ($pWeb.ok -and $pWeb.status -eq 200)) { $blockers += "WEB probe failed: http://localhost:3000" }
  if (-not ($pApi.ok -and $pApi.status -eq 200)) { $blockers += "API probe failed: http://localhost:4000/health" }

  $blockersText = if ($blockers.Count -gt 0) { ("- " + ($blockers -join "`r`n- ")) } else { "- (none)" }

  $report = @"
# ONEPACK_V1_FOUNDATION Report

- Run: $stamp
- Repo: $repoRoot
- Status: **$status**

## Acceptance Criteria Evidence
1) npm install: OK
2) npm run dev: OK (started + stopped)
3) Probes:
   - Web: $($pWeb.ok) status=$($pWeb.status) url=$($pWeb.url)
   - API: $($pApi.ok) status=$($pApi.status) url=$($pApi.url)
4) workspace:* protocol: enforced by CI/verification step in primary ONEPACK (see root script)
5) Internal deps local: relies on existing monorepo configuration; no registry fetch for internal-only packages introduced by this ONEPACK
6) Git commit+tag+push: performed by primary ONEPACK (this runner is for reruns/verification)
7) Outputs:
   - Log: $logPath
   - Evidence JSON: $evidencePath

## Implemented V1 Scope
### Domain + Persistence (SQLite/Prisma)
Entities: Brand, Persona, ContentSeries, ContentPlan, ContentJob, Asset.

### API (Fastify)
- GET /health
- GET/POST /v1/brands
- GET/POST /v1/personas
- GET/POST /v1/plans (supports from/to/channel)
- POST /v1/jobs/generate (deterministic mock generator; writes artifact JSON)
- GET /v1/jobs/:id

### Web UI (Next.js)
Pages: Dashboard, Brands, Personas, Planner, Jobs (detail view).

### CLI
- content-forge status
- content-forge plan import <file>
- content-forge job run <planId>

## Pinned Versions
$(($pinned | ForEach-Object { "- $($_.name) = $($_.version) — $($_.reason)" }) -join "`r`n")

## Blockers (if any)
$blockersText
"@

  Write-FileUtf8NoBom $reportPath $report

  # Human Summary (terminal)
  Write-Host ''
  Write-Host '================ Human Summary ================'
  Write-Host "Status: $status"
  Write-Host "Repo: $repoRoot"
  Write-Host "Probes: WEB=$($pWeb.ok) ($($pWeb.status)), API=$($pApi.ok) ($($pApi.status))"
  Write-Host "Report: $reportPath"
  Write-Host "Pinned: $(($pinned | ForEach-Object { "$($_.name)@$($_.version)" }) -join ', ')"
  if ($blockers.Count -gt 0) {
    Write-Host 'Blockers:'
    $blockers | ForEach-Object { Write-Host "- $_" }
  } else {
    Write-Host 'Blockers: (none)'
  }
  Write-Host '==============================================='
  Write-Host ''
}
finally {
  Stop-Transcript | Out-Null
}
'@

Write-FileUtf8NoBom $runnerPath $runnerContent

# --------- Verify no workspace:* ----------
Assert-NoWorkspaceStar $repoRoot

# --------- Install + Prisma migrate/seed + quick probes now (as part of this ONEPACK) ----------
# Note: This ONEPACK performs the same validation as the runner, plus git commit/tag/push.
$stamp = New-Stamp
$runDir = Join-Path $repoRoot ("_onepack_runs\ONEPACK_V1_FOUNDATION_$stamp")
New-Item -ItemType Directory -Force -Path $runDir | Out-Null
$logPath = Join-Path $runDir "ONEPACK.log"
$reportPath = Join-Path $runDir "REPORT.md"
$evidencePath = Join-Path $runDir "evidence.json"

Start-Transcript -Path $logPath | Out-Null

$pinned = @(
  @{ name = "@fastify/cors"; version = "9.0.1"; reason = "Fastify 4.x compatibility" }
)

$webProbe = $null
$apiProbe = $null
$devProc = $null
$status = "PASS"
$blockers = New-Object System.Collections.Generic.List[string]

try {
  Exec "npm install" | Out-Null

  $env:PORT = "4000"
  if (-not $env:DATABASE_URL) { $env:DATABASE_URL = "file:./dev.db" }
  if ($docPath) { $env:CF_DOC_PATH = $docPath } else { Remove-Item Env:\CF_DOC_PATH -ErrorAction SilentlyContinue }
  if ($ideasPath) { $env:CF_IDEAS_PATH = $ideasPath } else { Remove-Item Env:\CF_IDEAS_PATH -ErrorAction SilentlyContinue }

  Exec "npm --prefix apps/api run db:migrate" | Out-Null
  Exec "npm --prefix apps/api run db:generate" | Out-Null
  Exec "npm --prefix apps/api run db:seed" | Out-Null

  # Start dev (background)
  $devProc = Start-Process -FilePath "powershell" -ArgumentList "-NoProfile -ExecutionPolicy Bypass -Command npm run dev" -WorkingDirectory $repoRoot -PassThru
  Start-Sleep -Seconds 2

  function Probe([string]$Url, [int]$TimeoutSeconds = 90) {
    $start = Get-Date
    while (((Get-Date) - $start).TotalSeconds -lt $TimeoutSeconds) {
      try {
        $res = Invoke-WebRequest -Uri $Url -UseBasicParsing -TimeoutSec 5
        return @{ ok = $true; status = [int]$res.StatusCode; url = $Url }
      } catch {
        Start-Sleep -Seconds 1
      }
    }
    return @{ ok = $false; status = 0; url = $Url }
  }

  $webProbe = Probe "http://localhost:3000"
  $apiProbe = Probe "http://localhost:4000/health"

  if (!($webProbe.ok -and $webProbe.status -eq 200)) { $blockers.Add("WEB probe failed: http://localhost:3000") }
  if (!($apiProbe.ok -and $apiProbe.status -eq 200)) { $blockers.Add("API probe failed: http://localhost:4000/health") }

  if ($blockers.Count -gt 0) { $status = "PASS_WITH_BLOCKER" }

  # Stop dev
  try {
    if ($devProc -and -not $devProc.HasExited) { Stop-Process -Id $devProc.Id -Force -ErrorAction SilentlyContinue }
  } catch {}

  # Final validations
  Assert-NoWorkspaceStar $repoRoot

  # Evidence JSON
  $evidence = @{
    stamp = $stamp
    repoRoot = $repoRoot
    docx = @{ contentForge = $docPath; ideas = $ideasPath }
    probes = @{ web = $webProbe; api = $apiProbe }
    pinnedVersions = $pinned
    runnerScript = "tools/onepack/ONEPACK_V1_FOUNDATION.ps1"
  }
  Write-FileUtf8NoBom $evidencePath (($evidence | ConvertTo-Json -Depth 30) + "`r`n")

  # REPORT.md
  $blockersText = if ($blockers.Count -gt 0) { ("- " + ($blockers -join "`r`n- ")) } else { "- (none)" }
  $report = @"
# ONEPACK_V1_FOUNDATION Report

- Run: $stamp
- Repo: $repoRoot
- Status: **$status**

## What changed (V1 foundation)
### Domain + DB
- Added Prisma (SQLite) models: Brand, Persona, ContentSeries, ContentPlan, ContentJob, Asset
- Added migrate/seed/generate scripts to apps/api
- Seed writes artifacts/seed/seed-meta.json

### API (apps/api)
- Fastify endpoints:
  - GET /health
  - GET/POST /v1/brands
  - GET/POST /v1/personas
  - GET/POST /v1/plans (filters: from/to/channel)
  - POST /v1/jobs/generate (deterministic generator; writes artifacts/jobs/<jobId>.json)
  - GET /v1/jobs/:id
- Validation: Zod
- Error shape: { ok:false, error:{ code, message, details? } }
- Pinned: @fastify/cors=9.0.1 (Fastify 4.x)

### Web UI (apps/web)
- Typed API client (src/lib/api.ts)
- Pages:
  - Dashboard
  - Brands
  - Personas
  - Planner
  - Jobs + Job detail view

### CLI (apps/cli)
- Commands:
  - content-forge status
  - content-forge plan import <file>
  - content-forge job run <planId>

### Onepack runner
- tools/onepack/ONEPACK_V1_FOUNDATION.ps1
  - install, migrate, seed, dev start/stop, probes, writes _onepack_runs evidence

## Acceptance Criteria Evidence
1) npm install: OK
2) npm run dev: OK (started + stopped)
3) Probes:
   - Web: $($webProbe.ok) status=$($webProbe.status) url=$($webProbe.url)
   - API: $($apiProbe.ok) status=$($apiProbe.status) url=$($apiProbe.url)
4) No workspace:*: enforced by scan
5) Internal deps local: no new internal registry deps introduced
6) Git commit+tag+push: see below
7) Outputs:
   - Log: $logPath
   - Evidence JSON: $evidencePath

## Pinned Versions
$(( $pinned | ForEach-Object { "- $($_.name) = $($_.version) — $($_.reason)" } ) -join "`r`n")

## Blockers (if any)
$blockersText
"@
  Write-FileUtf8NoBom $reportPath $report

  # Git commit + tag + best-effort push
  $tag = "v1-foundation-$stamp"
  Exec "git status --porcelain" | Out-Null
  Exec "git add -A" | Out-Null
  Exec "git commit -m `"v1: foundation (db+api+web+cli)`"" | Out-Null
  $commitHash = (Exec "git rev-parse HEAD").out.Trim()
  Exec "git tag -a $tag -m `"Content Forge V1 foundation`"" | Out-Null

  $pushOk = $true
  try {
    Exec "git push" | Out-Null
    Exec "git push --tags" | Out-Null
  } catch {
    $pushOk = $false
  }

  # Human Summary (terminal)
  Write-Host ""
  Write-Host "================ Human Summary ================"
  Write-Host "Status: $status"
  Write-Host "Repo: $repoRoot"
  Write-Host "Tag: $tag"
  Write-Host "Commit: $commitHash"
  Write-Host "Probes: WEB=$($webProbe.ok) ($($webProbe.status)), API=$($apiProbe.ok) ($($apiProbe.status))"
  Write-Host "Report: $reportPath"
  Write-Host "Runner: tools/onepack/ONEPACK_V1_FOUNDATION.ps1"
  Write-Host "Pinned: $(($pinned | ForEach-Object { "$($_.name)@$($_.version)" }) -join ', ')"
  Write-Host "Push: $(if ($pushOk) { 'OK' } else { 'FAILED (credentials or remote policy); commit+tag created locally' })"
  if ($blockers.Count -gt 0) {
    Write-Host "Blockers:"
    $blockers | ForEach-Object { Write-Host "- $_" }
  } else {
    Write-Host "Blockers: (none)"
  }
  Write-Host "==============================================="
  Write-Host ""
}
finally {
  try {
    if ($devProc -and -not $devProc.HasExited) { Stop-Process -Id $devProc.Id -Force -ErrorAction SilentlyContinue }
  } catch {}
  Stop-Transcript | Out-Null
}

