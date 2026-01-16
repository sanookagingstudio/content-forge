// Content Generation Engine V3 - Real structured output
// Thai-first, platform-aware, deterministic

import crypto from 'node:crypto';

type GenerateInputV3 = {
  brandName: string;
  voiceTone: string;
  prohibitedTopics: string;
  targetAudience: string;
  topic: string;
  objective: string;
  cta?: string;
  platforms: ('facebook' | 'instagram' | 'tiktok' | 'youtube')[];
  language: 'th' | 'en';
  seed?: string;
  personaName?: string;
};

type PlatformContent = {
  title: string;
  hook: string;
  body: string;
  cta: string;
  hashtags: string[];
};

type VideoScript = {
  hook: string;
  storyline: Array<{ scene: string; duration: string; visual: string }>;
  ending_cta: string;
};

type ImagePrompt = {
  description_th: string;
  style: string;
  negative_prompt: string;
  notes: string;
};

type GeneratedContent = {
  caption_th: string;
  platforms: {
    facebook?: PlatformContent;
    instagram?: PlatformContent;
    tiktok?: PlatformContent;
    youtube?: PlatformContent;
  };
  video_script: VideoScript;
  image_prompt: ImagePrompt;
};

function stableHash(s: string) {
  return crypto.createHash('sha256').update(s).digest('hex').slice(0, 16);
}

function pick<T>(arr: T[], idx: number) {
  return arr[idx % arr.length];
}

export function generateContentV3(input: GenerateInputV3): GeneratedContent {
  const base = JSON.stringify(input);
  const h = stableHash(base);
  const n = parseInt(h.slice(0, 8), 16);

  const isThai = input.language === 'th';

  // Thai hooks
  const thHooks = [
    'เริ่มจากเรื่องเล็ก ๆ ที่ทำได้วันนี้',
    'ถ้าคุณอยากเห็นผลลัพธ์ที่ชัดใน 7 วัน',
    '3 ขั้นตอนสั้น ๆ ที่คนส่วนใหญ่ข้ามไป',
    'ทำไมวิธีเดิมถึงไม่เวิร์ก แล้วควรทำอย่างไร',
    'เรื่องนี้เปลี่ยนมุมมองของฉันไปเลย',
  ];

  const enHooks = [
    'Start with the smallest action you can do today.',
    'If you want a clear result in 7 days, do this.',
    'Three short steps most people skip.',
    'Why the old way fails—and what to do instead.',
    'This changed my perspective completely.',
  ];

  // Thai CTAs
  const thCtas = [
    'ทักมาเพื่อรับเช็กลิสต์',
    'คอมเมนต์ "สนใจ" แล้วส่งรายละเอียดให้',
    'บันทึกโพสต์นี้ไว้ แล้วลองทำตาม',
    'แชร์ให้คนที่กำลังต้องการ',
    'ลองทำแล้วคอมเมนต์บอกผลลัพธ์',
  ];

  const enCtas = [
    'DM us for the checklist.',
    'Comment "info" and we will send details.',
    'Save this post and try it.',
    'Share with someone who needs it.',
    'Try it and comment with your results.',
  ];

  const hook = isThai ? pick(thHooks, n) : pick(enHooks, n);
  const ctaBase = input.cta?.trim() || (isThai ? pick(thCtas, n + 1) : pick(enCtas, n + 1));

  // Base caption (Thai-first)
  const caption_th = isThai
    ? `${hook}\n\n${input.objective}\n\nหัวข้อ: ${input.topic}\nกลุ่มเป้าหมาย: ${input.targetAudience}\n\n${ctaBase}`
    : `${hook}\n\n${input.objective}\n\nTopic: ${input.topic}\nTarget: ${input.targetAudience}\n\n${ctaBase}`;

  // Platform-specific content
  const platforms: GeneratedContent['platforms'] = {};

  if (input.platforms.includes('facebook')) {
    platforms.facebook = {
      title: isThai ? `${input.topic} — ${input.objective}` : `${input.topic} — ${input.objective}`,
      hook: hook,
      body: isThai
        ? `โทนแบรนด์: ${input.voiceTone}\n\n${input.objective}\n\n1) ${input.topic} — ทำไมถึงสำคัญ\n2) วิธีเริ่มต้นที่ทำได้ทันที\n3) ตัวอย่างที่เห็นผลจริง\n\n${input.prohibitedTopics ? `⚠️ หลีกเลี่ยง: ${input.prohibitedTopics}` : ''}`
        : `Brand tone: ${input.voiceTone}\n\n${input.objective}\n\n1) ${input.topic} — Why it matters\n2) How to start right away\n3) Real examples that work\n\n${input.prohibitedTopics ? `⚠️ Avoid: ${input.prohibitedTopics}` : ''}`,
      cta: ctaBase,
      hashtags: isThai
        ? ['#การตลาด', '#คอนเทนต์', `#${input.topic.replace(/\s+/g, '')}`, '#ไอเดีย', '#แบรนด์']
        : ['#marketing', '#content', `#${input.topic.replace(/\s+/g, '')}`, '#ideas', '#brand'],
    };
  }

  if (input.platforms.includes('instagram')) {
    platforms.instagram = {
      title: isThai ? `${input.topic}` : input.topic,
      hook: hook,
      body: isThai
        ? `${hook}\n\n${input.objective}\n\n✨ ${input.topic}\n\n💡 ทำได้ทันที:\n1. ${input.objective.split(' ')[0]}...\n2. เริ่มจากจุดเล็ก\n3. ติดตามผล\n\n${ctaBase}`
        : `${hook}\n\n${input.objective}\n\n✨ ${input.topic}\n\n💡 Start now:\n1. ${input.objective.split(' ')[0]}...\n2. Start small\n3. Track results\n\n${ctaBase}`,
      cta: ctaBase,
      hashtags: isThai
        ? ['#คอนเทนต์', '#ไอเดีย', `#${input.topic.replace(/\s+/g, '')}`, '#แบรนด์', '#thailand']
        : ['#content', '#ideas', `#${input.topic.replace(/\s+/g, '')}`, '#brand', '#marketing'],
    };
  }

  if (input.platforms.includes('tiktok')) {
    platforms.tiktok = {
      title: isThai ? `${hook}` : hook,
      hook: hook,
      body: isThai
        ? `${hook}\n\n${input.topic} — ทำไมถึงสำคัญ?\n\n3 ขั้นตอน:\n1️⃣ ${input.objective.split(' ').slice(0, 3).join(' ')}\n2️⃣ เริ่มทำเลย\n3️⃣ ติดตามผล\n\n${ctaBase}`
        : `${hook}\n\n${input.topic} — Why it matters?\n\n3 steps:\n1️⃣ ${input.objective.split(' ').slice(0, 3).join(' ')}\n2️⃣ Start now\n3️⃣ Track results\n\n${ctaBase}`,
      cta: ctaBase,
      hashtags: isThai
        ? ['#tiktok', '#คอนเทนต์', `#${input.topic.replace(/\s+/g, '')}`, '#viral', '#thailand']
        : ['#tiktok', '#content', `#${input.topic.replace(/\s+/g, '')}`, '#viral', '#tips'],
    };
  }

  if (input.platforms.includes('youtube')) {
    platforms.youtube = {
      title: isThai ? `${input.topic}: ${input.objective}` : `${input.topic}: ${input.objective}`,
      hook: hook,
      body: isThai
        ? `${hook}\n\nในวิดีโอนี้เราจะพูดถึง:\n\n1. ${input.topic} — ทำไมถึงสำคัญ\n2. ${input.objective} — วิธีทำ\n3. ตัวอย่างจริงที่เห็นผล\n4. สรุปและข้อควรระวัง\n\n${ctaBase}`
        : `${hook}\n\nIn this video we'll cover:\n\n1. ${input.topic} — Why it matters\n2. ${input.objective} — How to do it\n3. Real examples that work\n4. Summary and warnings\n\n${ctaBase}`,
      cta: ctaBase,
      hashtags: isThai
        ? ['#youtube', '#คอนเทนต์', `#${input.topic.replace(/\s+/g, '')}`, '#แบรนด์', '#thailand']
        : ['#youtube', '#content', `#${input.topic.replace(/\s+/g, '')}`, '#brand', '#tutorial'],
    };
  }

  // Video script
  const video_script: VideoScript = {
    hook: hook,
    storyline: [
      {
        scene: isThai ? 'เปิดเรื่อง' : 'Opening',
        duration: '0-3s',
        visual: isThai ? `แสดง ${input.topic} อย่างรวดเร็ว` : `Show ${input.topic} quickly`,
      },
      {
        scene: isThai ? 'อธิบายปัญหา' : 'Problem',
        duration: '3-10s',
        visual: isThai ? `แสดงความสำคัญของ ${input.objective}` : `Show importance of ${input.objective}`,
      },
      {
        scene: isThai ? 'วิธีแก้' : 'Solution',
        duration: '10-25s',
        visual: isThai ? `แสดงขั้นตอน 3 ขั้น` : `Show 3 steps`,
      },
      {
        scene: isThai ? 'สรุป' : 'Summary',
        duration: '25-30s',
        visual: isThai ? `แสดงผลลัพธ์และ CTA` : `Show results and CTA`,
      },
    ],
    ending_cta: ctaBase,
  };

  // Image prompt
  const image_prompt: ImagePrompt = {
    description_th: isThai
      ? `${input.topic} — ${input.objective}, สไตล์ ${input.voiceTone}, กลุ่มเป้าหมาย ${input.targetAudience}, สีสันสดใส, องค์ประกอบชัดเจน`
      : `${input.topic} — ${input.objective}, ${input.voiceTone} style, target ${input.targetAudience}, vibrant colors, clear composition`,
    style: isThai ? 'สไตล์ไทยร่วมสมัย, สีสันสดใส, องค์ประกอบชัดเจน' : 'Modern Thai style, vibrant colors, clear composition',
    negative_prompt: isThai
      ? 'ภาพเบลอ, สีซีด, องค์ประกอบรก, ข้อความเยอะเกินไป'
      : 'blurry, faded colors, cluttered composition, too much text',
    notes: isThai
      ? `⚠️ ระวัง: หลีกเลี่ยงสัญลักษณ์หรือสีที่อาจมีความหมายทางวัฒนธรรมที่ซับซ้อน. ใช้สีที่เหมาะสมกับแบรนด์ ${input.brandName}.`
      : `⚠️ Note: Avoid symbols or colors with complex cultural meanings. Use colors appropriate for brand ${input.brandName}.`,
  };

  return {
    caption_th,
    platforms,
    video_script,
    image_prompt,
  };
}

