// Digital Product Exporter - Creates ZIP-ready folder bundles

import { prisma } from '../db';
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';

export interface ExportInput {
  jobId: string;
  templateKey: string;
  mode: 'draft' | 'publish';
}

export interface ExportResult {
  productId: string;
  exportPath: string;
  manifest: any;
}

function stableHash(content: string): string {
  return crypto.createHash('sha256').update(content).digest('hex');
}

function sortKeys(obj: any): any {
  if (typeof obj !== 'object' || obj === null) {
    return obj;
  }
  if (Array.isArray(obj)) {
    return obj.map(sortKeys);
  }
  const sorted: any = {};
  for (const key of Object.keys(obj).sort()) {
    sorted[key] = sortKeys(obj[key]);
  }
  return sorted;
}

export async function exportProduct(input: ExportInput): Promise<ExportResult> {
  const job = await prisma.contentJob.findUnique({
    where: { id: input.jobId },
    include: { plan: { include: { brand: true } } },
  });

  if (!job) {
    throw new Error(`Job not found: ${input.jobId}`);
  }

  // Policy gate check
  if (input.mode === 'publish' && job.onAirGateRequired) {
    throw new Error('Publish blocked: onAirGateRequired');
  }

  const template = await prisma.productTemplate.findUnique({
    where: { key: input.templateKey },
  });

  if (!template) {
    throw new Error(`Template not found: ${input.templateKey}`);
  }

  const outputs = JSON.parse(job.outputsJson || '{}');
  const policyTrace = JSON.parse(job.policyJson || '{}');
  const canonPacket = JSON.parse(job.canonPacketJson || '{}');
  const selectorJson = JSON.parse(job.selectorJson || '{}');

  // Create product export record
  const product = await prisma.productExport.create({
    data: {
      jobId: job.id,
      templateKey: input.templateKey,
      mode: input.mode,
      status: 'created',
      exportPath: '', // Will update after folder creation
      manifestJson: '{}',
    },
  });

  // Create export folder
  const exportDir = path.join(process.cwd(), 'exports', 'products', product.id);
  fs.mkdirSync(exportDir, { recursive: true });

  const assetsDir = path.join(exportDir, 'assets');
  const marketingDir = path.join(exportDir, 'marketing');
  const licensingDir = path.join(exportDir, 'licensing');
  fs.mkdirSync(assetsDir, { recursive: true });
  fs.mkdirSync(marketingDir, { recursive: true });
  fs.mkdirSync(licensingDir, { recursive: true });

  // Write assets
  const textContent = JSON.stringify(outputs.text || {}, null, 2);
  const promptsContent = JSON.stringify(outputs.image_prompt || {}, null, 2);
  const musicContent = JSON.stringify(outputs.music || {}, null, 2);

  fs.writeFileSync(path.join(assetsDir, 'text.json'), textContent, 'utf8');
  fs.writeFileSync(path.join(assetsDir, 'prompts.json'), promptsContent, 'utf8');
  fs.writeFileSync(path.join(assetsDir, 'music.json'), musicContent, 'utf8');

  // Write marketing
  const captionsContent = JSON.stringify({
    platforms: outputs.platforms || {},
    video_script: outputs.video_script || {},
  }, null, 2);
  fs.writeFileSync(path.join(marketingDir, 'captions.json'), captionsContent, 'utf8');

  // Write licensing
  const rightsContent = JSON.stringify({
    jobId: job.id,
    createdAt: job.createdAt.toISOString(),
    template: input.templateKey,
    mode: input.mode,
    policyGate: {
      tier: policyTrace.overall?.tier || 'unknown',
      gateRequired: job.onAirGateRequired,
    },
  }, null, 2);

  const policyContent = JSON.stringify({
    summary: policyTrace.overall || {},
    platform: policyTrace.platform || {},
    warnings: policyTrace.notes || [],
  }, null, 2);

  fs.writeFileSync(path.join(licensingDir, 'rights.json'), rightsContent, 'utf8');
  fs.writeFileSync(path.join(licensingDir, 'policy.json'), policyContent, 'utf8');

  // Build manifest
  const files = [
    { path: 'assets/text.json', hash: stableHash(textContent) },
    { path: 'assets/prompts.json', hash: stableHash(promptsContent) },
    { path: 'assets/music.json', hash: stableHash(musicContent) },
    { path: 'marketing/captions.json', hash: stableHash(captionsContent) },
    { path: 'licensing/rights.json', hash: stableHash(rightsContent) },
    { path: 'licensing/policy.json', hash: stableHash(policyContent) },
  ];

  const manifest = {
    productId: product.id,
    jobId: job.id,
    templateKey: input.templateKey,
    mode: input.mode,
    createdAt: new Date().toISOString(),
    providerTrace: selectorJson.providerTraces || {},
    policySummary: {
      tier: policyTrace.overall?.tier || 'unknown',
      gateRequired: job.onAirGateRequired,
      warnings: input.mode === 'draft' && job.onAirGateRequired ? ['Draft mode: Gate required for publish'] : [],
    },
    canonSummary: canonPacket.universe ? {
      universe: canonPacket.universe.name,
      characters: canonPacket.characters?.map((c: any) => c.name) || [],
    } : null,
    files,
  };

  const manifestContent = JSON.stringify(sortKeys(manifest), null, 2);
  fs.writeFileSync(path.join(exportDir, 'manifest.json'), manifestContent, 'utf8');

  // Update product export record
  await prisma.productExport.update({
    where: { id: product.id },
    data: {
      exportPath: exportDir,
      manifestJson: manifestContent,
      status: 'completed',
    },
  });

  return {
    productId: product.id,
    exportPath: exportDir,
    manifest,
  };
}

