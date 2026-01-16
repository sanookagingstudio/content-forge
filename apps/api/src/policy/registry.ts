// Policy Profile Registry

import { prisma } from '../db';

let cachedProfiles: any[] | null = null;

export async function loadPolicyProfiles(): Promise<any[]> {
  if (cachedProfiles) {
    return cachedProfiles;
  }

  const dbProfiles = await prisma.policyProfile.findMany({
    where: { isActive: true },
    orderBy: { createdAt: 'desc' },
  });

  cachedProfiles = dbProfiles.map(p => ({
    ...p,
    rules: JSON.parse(p.rulesJson || '{}'),
  }));

  return cachedProfiles;
}

export async function getPolicyProfileByPlatform(platform: string): Promise<any | null> {
  const profiles = await loadPolicyProfiles();
  return profiles.find(p => p.platform === platform) || profiles.find(p => p.platform === 'general') || null;
}

export function clearCache(): void {
  cachedProfiles = null;
}

