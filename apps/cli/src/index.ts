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
    try {
      const api = await http('/health');
      console.log(JSON.stringify({ ok: true, apiBase, api }, null, 2));
    } catch (e: any) {
      console.error(JSON.stringify({ ok: false, error: e.message, apiBase }, null, 2));
      process.exit(1);
    }
  });

program
  .command('capabilities')
  .description('List capability providers')
  .command('list')
  .action(async () => {
    try {
      const res = await http('/v1/capabilities');
      if (res.status === 200 && res.json.ok) {
        console.log(JSON.stringify(res.json.data, null, 2));
      } else {
        console.error(JSON.stringify({ ok: false, error: 'API unavailable', apiBase }, null, 2));
        process.exit(1);
      }
    } catch (e: any) {
      console.error(JSON.stringify({ ok: false, error: e.message, apiBase, note: 'API unavailable - ensure dev server is running' }, null, 2));
      process.exit(1);
    }
  });

program
  .command('policies')
  .description('List policy profiles')
  .command('list')
  .action(async () => {
    try {
      const res = await http('/v1/policies');
      if (res.status === 200 && res.json.ok) {
        console.log(JSON.stringify(res.json.data, null, 2));
      } else {
        console.error(JSON.stringify({ ok: false, error: 'API unavailable', apiBase }, null, 2));
        process.exit(1);
      }
    } catch (e: any) {
      console.error(JSON.stringify({ ok: false, error: e.message, apiBase, note: 'API unavailable - ensure dev server is running' }, null, 2));
      process.exit(1);
    }
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
    const results: unknown[] = [];
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
  .argument('[planId]', 'Plan ID (optional if brandId provided)')
  .option('--brandId <id>', 'Brand ID')
  .option('--personaId <id>', 'Persona ID')
  .option('--topic <topic>', 'Topic (required)')
  .option('--objective <quality|cost|speed>', 'Objective', 'quality')
  .option('--platforms <platforms>', 'Comma-separated platforms', 'facebook')
  .option('--lang <th|en>', 'Language', 'th')
  .option('--seed <seed>', 'Deterministic seed')
  .action(async (planId, opts) => {
    if (!planId && !opts.brandId) {
      console.error(JSON.stringify({ ok: false, error: 'Either planId or --brandId must be provided' }, null, 2));
      process.exit(1);
    }
    if (!opts.topic) {
      console.error(JSON.stringify({ ok: false, error: '--topic is required' }, null, 2));
      process.exit(1);
    }

    const platforms = opts.platforms.split(',').map((p: string) => p.trim());
    const body: any = {
      topic: opts.topic,
      objective: opts.objective,
      platforms,
      options: {
        language: opts.lang,
        deterministicSeed: opts.seed,
        policy: 'strict',
      },
    };

    if (planId) {
      body.planId = planId;
    }
    if (opts.brandId) {
      body.brandId = opts.brandId;
    }
    if (opts.personaId) {
      body.personaId = opts.personaId;
    }

    try {
      const r = await http('/v1/jobs/generate', { method: 'POST', body: JSON.stringify(body) });
      if (r.status === 201 && r.json.ok) {
        console.log(JSON.stringify({ ok: true, apiBase, result: r.json.data }, null, 2));
      } else {
        console.error(JSON.stringify({ ok: false, error: r.json.error || 'API error', apiBase, result: r }, null, 2));
        process.exit(1);
      }
    } catch (e: any) {
      console.error(JSON.stringify({ ok: false, error: e.message, apiBase, note: 'API unavailable - ensure dev server is running' }, null, 2));
      process.exit(1);
    }
  });

program
  .command('music')
  .description('Music generation')
  .command('generate')
  .option('--brandId <id>', 'Brand ID')
  .option('--topic <topic>', 'Topic (required)')
  .option('--style <style>', 'Style', 'ไทยร่วมสมัย')
  .option('--objective <quality|cost|speed>', 'Objective', 'quality')
  .option('--platforms <platforms>', 'Comma-separated platforms', 'youtube,tiktok')
  .option('--mood <happy|serene|epic|sad>', 'Mood', 'happy')
  .option('--duration <seconds>', 'Duration in seconds', '30')
  .action(async (opts) => {
    if (!opts.brandId) {
      console.error(JSON.stringify({ ok: false, error: '--brandId is required' }, null, 2));
      process.exit(1);
    }
    if (!opts.topic) {
      console.error(JSON.stringify({ ok: false, error: '--topic is required' }, null, 2));
      process.exit(1);
    }

    const platforms = opts.platforms.split(',').map((p: string) => p.trim());
    const body: any = {
      brandId: opts.brandId,
      topic: opts.topic,
      objective: opts.objective,
      platforms,
      assetKinds: ['text', 'music'],
      musicOptions: {
        mood: opts.mood,
        style: opts.style,
        durationSec: parseInt(opts.duration, 10),
      },
      options: {
        language: 'th',
        policy: 'strict',
      },
    };

    try {
      const r = await http('/v1/jobs/generate', { method: 'POST', body: JSON.stringify(body) });
      if (r.status === 201 && r.json.ok) {
        const data = r.json.data;
        const musicOutput = data.outputs?.music;
        const policyTrace = data.policyTrace;
        console.log(JSON.stringify({
          ok: true,
          jobId: data.id,
          musicProvider: data.providerTraces?.music?.providerName,
          chordProgression: musicOutput?.structure?.chordProgression,
          policyTier: policyTrace?.overall?.tier,
          gateRequired: policyTrace?.overall?.onAirGateRequired,
          result: data,
        }, null, 2));
      } else {
        console.error(JSON.stringify({ ok: false, error: r.json.error || 'API error', apiBase, result: r }, null, 2));
        process.exit(1);
      }
    } catch (e: any) {
      console.error(JSON.stringify({ ok: false, error: e.message, apiBase, note: 'API unavailable - ensure dev server is running' }, null, 2));
      process.exit(1);
    }
  });

program.parseAsync(process.argv).catch((e) => {
  console.error(e);
  process.exit(1);
});