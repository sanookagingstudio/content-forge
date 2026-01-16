// Policy Evaluation - Deterministic scoring

import { PolicyEvaluationInput, PolicyEvaluationResult, RiskTier } from './types';

const HIGH_RISK_TOPICS = [
  /18\+/i,
  /โป๊/i,
  /เปลือย/i,
  /เซ็ก/i,
  /พนัน/i,
  /ยา/i,
  /ความรุนแรง/i,
  /ฆ่า/i,
  /ตาย/i,
];

const COPYRIGHT_RISK_PATTERNS = [
  /ใช้เพลงต้นฉบับ/i,
  /copy/i,
  /เหมือนเพลง/i,
  /ลอกเพลง/i,
  /ดนตรีต้นฉบับ/i,
];

export function evaluatePolicy(input: PolicyEvaluationInput): PolicyEvaluationResult {
  let baseScore = 10;
  const warnings: string[] = [];
  const notes: string[] = [];
  const platformResults: Record<string, any> = {};

  // Check topic for high-risk keywords
  for (const pattern of HIGH_RISK_TOPICS) {
    if (pattern.test(input.topic)) {
      baseScore += 70;
      warnings.push('หัวข้ออาจมีเนื้อหาที่ไม่เหมาะสม');
      notes.push('ตรวจสอบเนื้อหาก่อนเผยแพร่');
      break;
    }
  }

  // Check for copyright risks (especially for music)
  if (input.kind === 'music') {
    const topicText = `${input.topic} ${JSON.stringify(input.contentOutputs || {})}`;
    for (const pattern of COPYRIGHT_RISK_PATTERNS) {
      if (pattern.test(topicText)) {
        baseScore += 50;
        warnings.push('อาจมีความเสี่ยงด้านลิขสิทธิ์ - ควรใช้เพลงที่ได้รับอนุญาตหรือเพลงต้นฉบับ');
        notes.push('ตรวจสอบลิขสิทธิ์เพลงก่อนใช้งาน');
        break;
      }
    }
  }

  // Jarvis warnings boost risk
  if (input.jarvisAdvisory?.warnings && input.jarvisAdvisory.warnings.length > 0) {
    const ambiguousWarnings = input.jarvisAdvisory.warnings.filter(w => 
      w.includes('คลุมเครือ') || w.includes('ambiguous')
    );
    if (ambiguousWarnings.length > 0) {
      baseScore += 10;
      warnings.push('คำเตือนจาก Jarvis: ' + ambiguousWarnings.join(', '));
    }
  }

  // Provider policy tags affect score
  if (input.providerPolicyTags?.includes('strict')) {
    baseScore -= 10;
    notes.push('Provider มีนโยบายเข้มงวด - ลดความเสี่ยง');
  }

  // Clamp score to 0-100
  baseScore = Math.max(0, Math.min(100, baseScore));

  // Determine tier
  let tier: RiskTier = 'unknown';
  if (baseScore >= 70) {
    tier = 'high';
  } else if (baseScore >= 30) {
    tier = 'medium';
  } else {
    tier = 'low';
  }

  // Evaluate per platform
  for (const platform of input.platforms) {
    let platformScore = baseScore;
    const platformWarnings: string[] = [...warnings];
    const platformRequiredEdits: string[] = [];

    // Platform-specific adjustments
    if (platform === 'youtube') {
      // YouTube is stricter
      if (baseScore >= 50) {
        platformScore += 10;
        platformWarnings.push('YouTube มีนโยบายเข้มงวด - ควรตรวจสอบเพิ่มเติม');
      }
    } else if (platform === 'tiktok') {
      // TikTok is moderate
      if (baseScore >= 60) {
        platformWarnings.push('TikTok อาจจำกัดเนื้อหาบางประเภท');
      }
    } else if (platform === 'facebook') {
      // Facebook is moderate
      if (baseScore >= 60) {
        platformWarnings.push('Facebook มีนโยบายเนื้อหาที่เข้มงวด');
      }
    }

    platformScore = Math.max(0, Math.min(100, platformScore));

    platformResults[platform] = {
      riskScore: platformScore,
      warnings: platformWarnings,
      requiredEdits: platformRequiredEdits,
    };
  }

  // Overall gate requirement
  const onAirGateRequired = tier === 'high' || 
    Object.values(platformResults).some((p: any) => p.riskScore >= 80);

  if (onAirGateRequired) {
    notes.push('⚠️ ต้องผ่านการตรวจสอบก่อนเผยแพร่ (onAirGateRequired=true)');
  }

  return {
    platform: platformResults,
    overall: {
      riskScore: baseScore,
      tier,
      onAirGateRequired,
    },
    notes,
  };
}

