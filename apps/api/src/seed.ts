import { prisma } from './db';
import fs from 'node:fs';
import path from 'node:path';
import { analyzeInputs } from './generator/jarvis';
import { generateContent } from './generator/generate';

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

  // Capability Providers
  const textProviders = [
    {
      name: 'mock-text-fast',
      version: '1.0.0',
      speedTier: 'fast',
      qualityTier: 'fast',
      costTier: 'cheap',
      policyTags: ['safe'],
      isDefault: false,
    },
    {
      name: 'mock-text-hq',
      version: '1.0.0',
      speedTier: 'standard',
      qualityTier: 'hq',
      costTier: 'premium',
      policyTags: ['strict', 'safe'],
      isDefault: true,
    },
    {
      name: 'mock-text-cheap',
      version: '1.0.0',
      speedTier: 'standard',
      qualityTier: 'standard',
      costTier: 'cheap',
      policyTags: ['safe'],
      isDefault: false,
    },
  ];

  for (const p of textProviders) {
    await prisma.capabilityProvider.upsert({
      where: { id: `seed-provider-${p.name}` },
      update: {},
      create: {
        id: `seed-provider-${p.name}`,
        kind: 'text',
        name: p.name,
        version: p.version,
        supports: JSON.stringify(['thai', 'english', 'deterministic']),
        costTier: p.costTier,
        qualityTier: p.qualityTier,
        speedTier: p.speedTier,
        regions: JSON.stringify(['global']),
        languages: JSON.stringify(['th', 'en']),
        policyTags: JSON.stringify(p.policyTags),
        isDefault: p.isDefault,
      },
    });
  }

  // Music Providers
  const musicProviders = [
    {
      name: 'mock-music-fast',
      version: '1.0.0',
      speedTier: 'fast',
      qualityTier: 'fast',
      costTier: 'cheap',
      policyTags: ['safe'],
      isDefault: false,
    },
    {
      name: 'mock-music-hq',
      version: '1.0.0',
      speedTier: 'standard',
      qualityTier: 'hq',
      costTier: 'premium',
      policyTags: ['strict', 'safe'],
      isDefault: true,
    },
    {
      name: 'mock-music-cheap',
      version: '1.0.0',
      speedTier: 'standard',
      qualityTier: 'standard',
      costTier: 'cheap',
      policyTags: ['safe'],
      isDefault: false,
    },
  ];

  for (const p of musicProviders) {
    await prisma.capabilityProvider.upsert({
      where: { id: `seed-provider-${p.name}` },
      update: {},
      create: {
        id: `seed-provider-${p.name}`,
        kind: 'music',
        name: p.name,
        version: p.version,
        supports: JSON.stringify(['bgm', 'jingle', 'chord_extract', 'style_transform']),
        costTier: p.costTier,
        qualityTier: p.qualityTier,
        speedTier: p.speedTier,
        regions: JSON.stringify(['global']),
        languages: JSON.stringify(['th', 'en']),
        policyTags: JSON.stringify(p.policyTags),
        isDefault: p.isDefault,
      },
    });
  }

  // Image provider placeholder
  await prisma.capabilityProvider.upsert({
    where: { id: 'seed-provider-mock-image' },
    update: {},
    create: {
      id: 'seed-provider-mock-image',
      kind: 'image',
      name: 'mock-image',
      version: '1.0.0',
      supports: JSON.stringify(['prompt', 'shotlist']),
      costTier: 'standard',
      qualityTier: 'standard',
      speedTier: 'standard',
      regions: JSON.stringify(['global']),
      languages: JSON.stringify(['th', 'en']),
      policyTags: JSON.stringify(['safe']),
      isDefault: true,
    },
  });

  // Video provider placeholder
  await prisma.capabilityProvider.upsert({
    where: { id: 'seed-provider-mock-video' },
    update: {},
    create: {
      id: 'seed-provider-mock-video',
      kind: 'video',
      name: 'mock-video',
      version: '1.0.0',
      supports: JSON.stringify(['script', 'shotlist']),
      costTier: 'premium',
      qualityTier: 'standard',
      speedTier: 'slow',
      regions: JSON.stringify(['global']),
      languages: JSON.stringify(['th', 'en']),
      policyTags: JSON.stringify(['safe']),
      isDefault: true,
    },
  });

  // Policy Profiles
  const policyProfiles = [
    {
      name: 'general',
      platform: 'general',
      rulesJson: JSON.stringify({
        thresholds: { low: 0, medium: 30, high: 70 },
        notes: ['Baseline policy for all platforms'],
      }),
    },
    {
      name: 'youtube',
      platform: 'youtube',
      rulesJson: JSON.stringify({
        thresholds: { low: 0, medium: 30, high: 50 },
        notes: ['YouTube has stricter content policies'],
      }),
    },
    {
      name: 'tiktok',
      platform: 'tiktok',
      rulesJson: JSON.stringify({
        thresholds: { low: 0, medium: 40, high: 60 },
        notes: ['TikTok moderate content policies'],
      }),
    },
    {
      name: 'facebook',
      platform: 'facebook',
      rulesJson: JSON.stringify({
        thresholds: { low: 0, medium: 40, high: 60 },
        notes: ['Facebook moderate content policies'],
      }),
    },
    {
      name: 'instagram',
      platform: 'instagram',
      rulesJson: JSON.stringify({
        thresholds: { low: 0, medium: 35, high: 65 },
        notes: ['Instagram moderate content policies'],
      }),
    },
  ];

  for (const p of policyProfiles) {
    await prisma.policyProfile.upsert({
      where: { id: `seed-policy-${p.platform}` },
      update: {},
      create: {
        id: `seed-policy-${p.platform}`,
        name: p.name,
        platform: p.platform,
        rulesJson: p.rulesJson,
        isActive: true,
      },
    });
  }

  // Write seed evidence
  const outDir = path.join(process.cwd(), 'artifacts', 'seed');
  fs.mkdirSync(outDir, { recursive: true });
  fs.writeFileSync(path.join(outDir, 'seed-meta.json'), JSON.stringify(seedMeta, null, 2), 'utf8');

  // Create sample ContentJob with generated content
  const firstPlan = await prisma.contentPlan.findFirst({
    where: { brandId: brand.id },
    orderBy: { scheduledAt: 'asc' },
  });

  if (firstPlan) {
    const persona = await prisma.persona.findFirst({
      where: { brandId: brand.id },
    });

    const topic = 'การดูแลสุขภาพผู้สูงอายุ';
    const objective = 'ให้ความรู้และสร้างแรงบันดาลใจในการดูแลสุขภาพ';
    const platforms: ('facebook' | 'instagram' | 'tiktok' | 'youtube')[] = ['facebook', 'instagram', 'tiktok', 'youtube'];

    // Run Jarvis advisory
    const advisory = analyzeInputs({
      brandName: brand.name,
      voiceTone: brand.voiceTone,
      topic,
      objective,
      personaName: persona?.name,
      platforms,
    });

    // Generate content
    const generatedOutput = generateContent({
      brandName: brand.name,
      voiceTone: brand.voiceTone,
      prohibitedTopics: brand.prohibitedTopics,
      targetAudience: brand.targetAudience,
      topic,
      objective,
      cta: firstPlan.cta,
      platforms,
      language: 'th',
      seed: `seed-${firstPlan.id}`,
      personaName: persona?.name,
    });

    // Create ContentJob
    const job = await prisma.contentJob.create({
      data: {
        planId: firstPlan.id,
        status: 'succeeded',
        inputsJson: JSON.stringify({
          planId: firstPlan.id,
          brandId: brand.id,
          personaId: persona?.id,
          topic,
          objective,
          platforms,
          options: {
            language: 'th',
            deterministicSeed: `seed-${firstPlan.id}`,
          },
        }),
        outputsJson: JSON.stringify(generatedOutput),
        advisoryJson: JSON.stringify(advisory),
        costJson: JSON.stringify({ tokens: 0, currency: 'N/A' }),
        logsJson: JSON.stringify([
          { at: nowISO(), msg: 'Queued' },
          { at: nowISO(), msg: 'Generated deterministically' },
          { at: nowISO(), msg: 'Completed' },
        ]),
      },
    });

    // Write artifact file
    const artifactsDir = path.join(process.cwd(), 'artifacts', 'jobs');
    fs.mkdirSync(artifactsDir, { recursive: true });
    const artifactPath = path.join(artifactsDir, `${job.id}.json`);
    fs.writeFileSync(
      artifactPath,
      JSON.stringify(
        {
          jobId: job.id,
          inputs: {
            planId: firstPlan.id,
            brandId: brand.id,
            personaId: persona?.id,
            topic,
            objective,
            platforms,
            options: {
              language: 'th',
              deterministicSeed: `seed-${firstPlan.id}`,
            },
          },
          advisory,
          outputs: generatedOutput,
        },
        null,
        2
      ),
      'utf8'
    );

    console.log(JSON.stringify({ ok: true, seedMeta, brandId: brand.id, jobId: job.id, artifactPath }, null, 2));
  } else {
    console.log(JSON.stringify({ ok: true, seedMeta, brandId: brand.id }, null, 2));
  }
}

main()
  .catch((e) => { console.error(e); process.exit(1); })
  .finally(async () => { await prisma.$disconnect(); });