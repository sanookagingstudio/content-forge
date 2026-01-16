// Mock Video Provider - Returns structured shotlist

import { ProviderExecuteInput, ProviderExecuteOutput } from '../types';

export async function executeMockVideo(
  providerId: string,
  providerName: string,
  input: ProviderExecuteInput
): Promise<ProviderExecuteOutput> {
  const startTime = Date.now();

  // Return structured placeholder for video generation
  const outputs = {
    video_script: {
      hook: input.language === 'th'
        ? `เริ่มจากเรื่องเล็ก ๆ ที่ทำได้วันนี้`
        : `Start with the smallest action you can do today`,
      scenes: [
        {
          scene: 1,
          visual: input.language === 'th' ? `แสดง ${input.topic} อย่างรวดเร็ว` : `Show ${input.topic} quickly`,
          narration: input.language === 'th' ? `ทำไม ${input.topic} ถึงสำคัญ?` : `Why is ${input.topic} important?`,
          duration: '0-5s',
        },
        {
          scene: 2,
          visual: input.language === 'th' ? `แสดงขั้นตอน 3 ขั้น` : `Show 3 steps`,
          narration: input.language === 'th' ? `3 ขั้นตอนง่าย ๆ:` : `3 simple steps:`,
          duration: '5-20s',
        },
        {
          scene: 3,
          visual: input.language === 'th' ? `แสดงผลลัพธ์และ CTA` : `Show results and CTA`,
          narration: input.cta || (input.language === 'th' ? 'ลองทำตาม' : 'Try it'),
          duration: '20-30s',
        },
      ],
      ending_cta: input.cta || (input.language === 'th' ? 'ลองทำตาม' : 'Try it'),
    },
    shotlist: [
      {
        shot: 1,
        description: input.language === 'th' ? 'เปิดเรื่อง' : 'Opening',
        duration: '0-5s',
        style: 'dynamic',
      },
      {
        shot: 2,
        description: input.language === 'th' ? 'เนื้อหาหลัก' : 'Main content',
        duration: '5-20s',
        style: 'clear',
      },
      {
        shot: 3,
        description: input.language === 'th' ? 'ปิดท้าย' : 'Closing',
        duration: '20-30s',
        style: 'call-to-action',
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

