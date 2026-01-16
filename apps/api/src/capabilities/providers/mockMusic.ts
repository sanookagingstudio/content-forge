// Mock Music Provider - Deterministic music generation

import { ProviderExecuteInput, ProviderExecuteOutput } from '../types';
import crypto from 'node:crypto';

export interface MusicOptions {
  task?: 'bgm' | 'jingle' | 'chord_extract' | 'style_transform';
  mood?: 'happy' | 'serene' | 'epic' | 'sad';
  tempoBpm?: number;
  durationSec?: number;
  style?: string;
  referenceLink?: string;
}

function stableHash(s: string): string {
  return crypto.createHash('sha256').update(s).digest('hex').slice(0, 16);
}

function pick<T>(arr: T[], idx: number): T {
  return arr[idx % arr.length];
}

const KEYS = ['Am', 'C', 'G', 'F', 'Dm', 'Em', 'A', 'D'];
const CHORD_PROGRESSIONS = [
  ['Am', 'F', 'C', 'G'],
  ['C', 'Am', 'F', 'G'],
  ['G', 'Em', 'C', 'D'],
  ['Am', 'Dm', 'G', 'C'],
  ['F', 'C', 'G', 'Am'],
];

const TEMPO_BY_MOOD: Record<string, number> = {
  happy: 120,
  serene: 80,
  epic: 140,
  sad: 70,
};

export async function executeMockMusic(
  providerId: string,
  providerName: string,
  input: ProviderExecuteInput,
  options?: MusicOptions
): Promise<ProviderExecuteOutput> {
  const startTime = Date.now();

  const task = options?.task || 'bgm';
  const mood = options?.mood || 'happy';
  const tempoBpm = options?.tempoBpm || TEMPO_BY_MOOD[mood] || 100;
  const durationSec = options?.durationSec || 30;
  const style = options?.style || (input.language === 'th' ? 'ไทยร่วมสมัย' : 'modern');
  const referenceLink = options?.referenceLink || null;

  // Deterministic seed
  const seed = input.seed || JSON.stringify({ input, options });
  const h = stableHash(seed);
  const n = parseInt(h.slice(0, 8), 16);

  const key = pick(KEYS, n);
  const chordProgression = pick(CHORD_PROGRESSIONS, n % CHORD_PROGRESSIONS.length);

  const sections = ['intro', 'verse', 'chorus', 'bridge', 'outro'];
  const selectedSections = sections.slice(0, Math.min(4, Math.floor(durationSec / 8) + 1));

  let lyrics_th: string | null = null;
  if (task === 'jingle' && input.language === 'th') {
    lyrics_th = `${input.topic}\n${input.objective}\n\n${pick(['จดจำได้ง่าย', 'น่าจดจำ', 'ติดหู'], n)}`;
  }

  const productionNotes: string[] = [];
  if (mood === 'epic') {
    productionNotes.push('ใช้เครื่องดนตรีที่มีพลัง เช่น กลอง, ทรัมเป็ต');
  } else if (mood === 'serene') {
    productionNotes.push('ใช้เครื่องดนตรีเบา เช่น เปียโน, ไวโอลิน');
  } else if (mood === 'happy') {
    productionNotes.push('ใช้เครื่องดนตรีที่มีจังหวะ เช่น กีตาร์, เปียโน');
  }

  productionNotes.push(`คีย์: ${key}`);
  productionNotes.push(`จังหวะ: ${tempoBpm} BPM`);
  productionNotes.push(`สไตล์: ${style}`);

  if (referenceLink) {
    productionNotes.push(`อ้างอิง: ${referenceLink} (ไม่ดึงข้อมูลใน v5)`);
  }

  const outputs = {
    music: {
      type: 'plan',
      task,
      structure: {
        key,
        tempoBpm,
        chordProgression,
        sections: selectedSections,
      },
      lyrics_th,
      productionNotes,
      provider: {
        name: providerName,
        version: '1.0.0',
      },
    },
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
        task,
        mood,
        style,
      },
    },
  };
}

