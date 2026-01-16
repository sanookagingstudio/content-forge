// Jarvis Advisory Module - Lightweight input analysis
// Detects ambiguity and provides warnings/suggestions

export type AdvisoryInput = {
  brandName?: string;
  voiceTone?: string;
  topic?: string;
  objective?: string;
  personaName?: string;
  platforms?: string[];
  styleHints?: string[];
};

export type AdvisoryOutput = {
  warnings: string[];
  suggestions: string[];
  normalized: {
    language: 'th' | 'en';
    styleHints: string[];
    culturalGuards: string[];
  };
};

const CULTURAL_CONFUSION_PATTERNS = [
  /หนุมาน/i,
  /รามเกียรติ์/i,
  /พระราม/i,
  /นางสีดา/i,
  /ทศกัณฑ์/i,
];

const VAGUE_STYLE_PATTERNS = [
  /ดี/i,
  /สวย/i,
  /เยี่ยม/i,
  /ดีมาก/i,
  /ทั่วไป/i,
];

const AMBIGUOUS_TOPICS = [
  /สุขภาพ/i,
  /อาหาร/i,
  /ท่องเที่ยว/i,
];

export function analyzeInputs(input: AdvisoryInput): AdvisoryOutput {
  const warnings: string[] = [];
  const suggestions: string[] = [];
  const culturalGuards: string[] = [];

  // Check for cultural confusion
  const topicText = `${input.topic || ''} ${input.objective || ''}`;
  for (const pattern of CULTURAL_CONFUSION_PATTERNS) {
    if (pattern.test(topicText)) {
      warnings.push('อาจมีความหมายทางวัฒนธรรมที่ซับซ้อน - ควรระบุบริบทให้ชัดเจน');
      suggestions.push('ระบุว่าเป็นเรื่องราวจากวรรณคดี/ตำนาน หรือเป็นเพียงการเปรียบเทียบ');
      culturalGuards.push('ระวังการอ้างอิงถึงตัวละครในวรรณคดีไทย - ควรระบุบริบทให้ชัดเจน');
    }
  }

  // Check for vague style descriptions
  if (input.voiceTone) {
    for (const pattern of VAGUE_STYLE_PATTERNS) {
      if (pattern.test(input.voiceTone)) {
        warnings.push('โทนเสียงที่ระบุค่อนข้างกว้าง - อาจทำให้ผลลัพธ์ไม่ตรงกับที่ต้องการ');
        suggestions.push('ระบุโทนเสียงให้ชัดเจน เช่น: เป็นกันเอง, วิชาการ, สนุกสนาน, แรงบันดาลใจ');
        break;
      }
    }
  }

  // Check for ambiguous topics
  for (const pattern of AMBIGUOUS_TOPICS) {
    if (pattern.test(topicText)) {
      warnings.push('หัวข้อกว้างเกินไป - ควรระบุมุมมองหรือจุดเด่นให้ชัดเจน');
      suggestions.push('ระบุมุมมองเฉพาะ เช่น: "สุขภาพ: การออกกำลังกายสำหรับผู้สูงอายุ" แทน "สุขภาพ"');
      break;
    }
  }

  // Check for missing persona
  if (!input.personaName && input.brandName) {
    warnings.push('ไม่มีการระบุ Persona - อาจทำให้เนื้อหาไม่ตรงกับกลุ่มเป้าหมาย');
    suggestions.push('สร้างหรือเลือก Persona ที่สอดคล้องกับกลุ่มเป้าหมาย');
  }

  // Check for platform selection
  if (!input.platforms || input.platforms.length === 0) {
    warnings.push('ไม่มีการเลือกแพลตฟอร์ม - จะสร้างเนื้อหาทั่วไป');
    suggestions.push('เลือกแพลตฟอร์มที่ต้องการ: Facebook, Instagram, TikTok, YouTube');
  }

  // Check for objective clarity
  if (!input.objective || input.objective.trim().length < 10) {
    warnings.push('วัตถุประสงค์ไม่ชัดเจน - อาจทำให้เนื้อหาไม่ตรงเป้า');
    suggestions.push('ระบุวัตถุประสงค์ให้ชัดเจน เช่น: "เพิ่มการมีส่วนร่วม", "สร้างการรับรู้", "แปลงเป็นลูกค้า"');
  }

  // Determine language (default to Thai)
  const language: 'th' | 'en' = input.topic && /^[a-zA-Z\s]+$/.test(input.topic) ? 'en' : 'th';

  return {
    warnings,
    suggestions,
    normalized: {
      language,
      styleHints: input.styleHints || [],
      culturalGuards,
    },
  };
}

