// Mock Text Provider - Uses existing deterministic generator

import { generateContent } from '../../generator/generate';
import { ProviderExecuteInput, ProviderExecuteOutput } from '../types';

export async function executeMockText(
  providerId: string,
  providerName: string,
  input: ProviderExecuteInput
): Promise<ProviderExecuteOutput> {
  const startTime = Date.now();

  // Use existing deterministic generator
  const outputs = generateContent(input);

  const executionTimeMs = Date.now() - startTime;

  return {
    outputs,
    providerTrace: {
      providerId,
      providerName,
      executionTimeMs,
      metadata: {
        deterministic: true,
        generatorVersion: outputs.meta.deterministicSeed,
      },
    },
  };
}

