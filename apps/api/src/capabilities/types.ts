// Capability Provider Types

export type ProviderKind = 'text' | 'image' | 'video' | 'music';

export type CostTier = 'cheap' | 'standard' | 'premium';
export type QualityTier = 'fast' | 'standard' | 'hq';
export type SpeedTier = 'fast' | 'standard' | 'slow';

export type Objective = 'quality' | 'cost' | 'speed';

export interface CapabilityProvider {
  id: string;
  kind: ProviderKind;
  name: string;
  version: string;
  supports: string[]; // supported features
  costTier: CostTier;
  qualityTier: QualityTier;
  speedTier: SpeedTier;
  regions: string[];
  languages: string[];
  policyTags: string[];
  isDefault: boolean;
}

export interface SelectorInput {
  kind: ProviderKind;
  objective: Objective;
  language: string;
  policy: string;
  jarvisAdvisory?: {
    warnings: string[];
    suggestions: string[];
  };
}

export interface SelectorOutput {
  providerId: string;
  reason: string;
  score: number;
  breakdown: {
    objectiveScore: number;
    languageScore: number;
    policyScore: number;
  };
}

export interface ProviderExecuteInput {
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
}

export interface ProviderExecuteOutput {
  outputs: any;
  providerTrace: {
    providerId: string;
    providerName: string;
    executionTimeMs: number;
    metadata: Record<string, any>;
  };
}

