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