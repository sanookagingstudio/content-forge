// Policy Evaluation Types

export type RiskTier = 'low' | 'medium' | 'high' | 'unknown';

export interface PlatformPolicyResult {
  riskScore: number;
  warnings: string[];
  requiredEdits: string[];
}

export interface PolicyEvaluationResult {
  platform: Record<string, PlatformPolicyResult>;
  overall: {
    riskScore: number;
    tier: RiskTier;
    onAirGateRequired: boolean;
  };
  notes: string[];
}

export interface PolicyEvaluationInput {
  kind: 'text' | 'image' | 'video' | 'music';
  platforms: string[];
  topic: string;
  contentOutputs?: any;
  providerPolicyTags?: string[];
  jarvisAdvisory?: {
    warnings: string[];
    suggestions: string[];
  };
}

