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