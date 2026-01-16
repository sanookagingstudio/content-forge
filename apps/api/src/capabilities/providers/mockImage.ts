// Mock Image Provider - Returns structured placeholder prompts

import { ProviderExecuteInput, ProviderExecuteOutput } from '../types';

export async function executeMockImage(
  providerId: string,
  providerName: string,
  input: ProviderExecuteInput
): Promise<ProviderExecuteOutput> {
  const startTime = Date.now();

  // Return structured placeholder for image generation
  const outputs = {
    image_prompt: {
      description_th: input.language === 'th'
        ? `${input.topic} — ${input.objective}, สไตล์ ${input.voiceTone}, กลุ่มเป้าหมาย ${input.targetAudience}`
        : `${input.topic} — ${input.objective}, ${input.voiceTone} style, target ${input.targetAudience}`,
      style: input.language === 'th' ? 'สไตล์ไทยร่วมสมัย, สีสันสดใส' : 'Modern style, vibrant colors',
      negative_prompt: input.language === 'th'
        ? 'ภาพเบลอ, สีซีด, องค์ประกอบรก'
        : 'blurry, faded colors, cluttered',
      notes: [
        input.language === 'th'
          ? `⚠️ ระวัง: หลีกเลี่ยงสัญลักษณ์หรือสีที่อาจมีความหมายทางวัฒนธรรมที่ซับซ้อน`
          : `⚠️ Note: Avoid symbols or colors with complex cultural meanings`,
      ],
    },
    shotlist: [
      {
        shot: 1,
        description: input.language === 'th' ? 'ภาพหลักแสดงหัวข้อ' : 'Main image showing topic',
        aspectRatio: '16:9',
        style: 'vibrant',
      },
      {
        shot: 2,
        description: input.language === 'th' ? 'ภาพประกอบแสดงผลลัพธ์' : 'Supporting image showing results',
        aspectRatio: '1:1',
        style: 'clean',
      },
    ],
  };

  const executionTimeMs = Date.now() - startTime;

  return {
    outputs,
    providerTrace: {
      providerId,
      providerName,
      executionTimeMs,
      metadata: {
        deterministic: true,
        placeholder: true,
      },
    },
  };
}

