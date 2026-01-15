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