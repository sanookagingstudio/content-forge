// AI Selector - Chooses provider based on objective + policy

import { SelectorInput, SelectorOutput, CapabilityProvider, Objective } from './types';
import { getProvidersByKind, getDefaultProvider } from './registry';

const TIER_SCORES: Record<string, Record<string, number>> = {
  quality: {
    hq: 3,
    standard: 2,
    fast: 1,
  },
  cost: {
    cheap: 3,
    standard: 2,
    premium: 1,
  },
  speed: {
    fast: 3,
    standard: 2,
    slow: 1,
  },
};

export async function selectProvider(input: SelectorInput): Promise<SelectorOutput> {
  const providers = await getProvidersByKind(input.kind);

  if (providers.length === 0) {
    const defaultProvider = await getDefaultProvider(input.kind);
    if (!defaultProvider) {
      throw new Error(`No providers available for kind: ${input.kind}`);
    }
    return {
      providerId: defaultProvider.id,
      reason: 'No providers available, using default',
      score: 0,
      breakdown: {
        objectiveScore: 0,
        languageScore: 0,
        policyScore: 0,
      },
    };
  }

  // Score each provider
  const scored = providers.map(provider => {
    let objectiveScore = 0;
    let languageScore = 0;
    let policyScore = 0;

    // Objective scoring
    if (input.objective === 'quality') {
      objectiveScore = TIER_SCORES.quality[provider.qualityTier] || 0;
    } else if (input.objective === 'cost') {
      objectiveScore = TIER_SCORES.cost[provider.costTier] || 0;
    } else if (input.objective === 'speed') {
      objectiveScore = TIER_SCORES.speed[provider.speedTier] || 0;
    }

    // Language match boost
    if (provider.languages.includes(input.language)) {
      languageScore = 2;
    } else if (provider.languages.length === 0) {
      // No language restriction = universal
      languageScore = 1;
    }

    // Policy match (if jarvis warns about sensitive topics, prefer strict)
    if (input.jarvisAdvisory?.warnings && input.jarvisAdvisory.warnings.length > 0) {
      if (provider.policyTags.includes('strict')) {
        policyScore = 3;
      } else if (provider.policyTags.includes('safe')) {
        policyScore = 1;
      }
    } else {
      // No warnings, prefer safe providers
      if (provider.policyTags.includes('safe')) {
        policyScore = 2;
      }
    }

    const totalScore = objectiveScore * 3 + languageScore * 2 + policyScore;

    return {
      provider,
      score: totalScore,
      breakdown: {
        objectiveScore,
        languageScore,
        policyScore,
      },
    };
  });

  // Sort by score descending
  scored.sort((a, b) => b.score - a.score);

  const selected = scored[0];

  const reason = `Selected ${selected.provider.name} (${selected.provider.kind}): ` +
    `objective=${selected.breakdown.objectiveScore} ` +
    `language=${selected.breakdown.languageScore} ` +
    `policy=${selected.breakdown.policyScore} ` +
    `total=${selected.score}`;

  return {
    providerId: selected.provider.id,
    reason,
    score: selected.score,
    breakdown: selected.breakdown,
  };
}

