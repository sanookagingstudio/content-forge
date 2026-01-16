// Capability Registry - Loads and manages providers

import { prisma } from '../db';
import { CapabilityProvider, ProviderKind } from './types';

let cachedProviders: CapabilityProvider[] | null = null;

export async function loadProviders(): Promise<CapabilityProvider[]> {
  if (cachedProviders) {
    return cachedProviders;
  }

  const dbProviders = await prisma.capabilityProvider.findMany();
  cachedProviders = dbProviders.map(p => ({
    id: p.id,
    kind: p.kind as ProviderKind,
    name: p.name,
    version: p.version,
    supports: JSON.parse(p.supports || '[]'),
    costTier: p.costTier as any,
    qualityTier: p.qualityTier as any,
    speedTier: p.speedTier as any,
    regions: JSON.parse(p.regions || '[]'),
    languages: JSON.parse(p.languages || '[]'),
    policyTags: JSON.parse(p.policyTags || '[]'),
    isDefault: p.isDefault,
  }));

  return cachedProviders;
}

export async function getProviderById(id: string): Promise<CapabilityProvider | null> {
  const providers = await loadProviders();
  return providers.find(p => p.id === id) || null;
}

export async function getProvidersByKind(kind: ProviderKind): Promise<CapabilityProvider[]> {
  const providers = await loadProviders();
  return providers.filter(p => p.kind === kind);
}

export async function getDefaultProvider(kind: ProviderKind): Promise<CapabilityProvider | null> {
  const providers = await loadProviders();
  const defaultProvider = providers.find(p => p.kind === kind && p.isDefault);
  if (defaultProvider) {
    return defaultProvider;
  }
  // Fallback to first provider of kind
  return providers.find(p => p.kind === kind) || null;
}

export function clearCache(): void {
  cachedProviders = null;
}

