// Product Template Registry

import { prisma } from '../db';

let cachedTemplates: any[] | null = null;

export async function loadProductTemplates(): Promise<any[]> {
  if (cachedTemplates) {
    return cachedTemplates;
  }

  const dbTemplates = await prisma.productTemplate.findMany({
    where: { isActive: true },
    orderBy: { createdAt: 'desc' },
  });

  cachedTemplates = dbTemplates.map(t => ({
    ...t,
    schema: JSON.parse(t.schemaJson || '{}'),
  }));

  return cachedTemplates;
}

export async function getProductTemplate(key: string): Promise<any | null> {
  const templates = await loadProductTemplates();
  return templates.find(t => t.key === key) || null;
}

export function clearCache(): void {
  cachedTemplates = null;
}

