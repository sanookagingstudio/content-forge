// IP Canon Packet Builder - Maintains character/universe/timeline memory

import { prisma } from '../db';

export interface CanonPacket {
  universe: {
    id: string;
    name: string;
    description: string;
    canonRules: any;
  };
  characters: Array<{
    id: string;
    name: string;
    bio: string;
    traits: any;
  }>;
  events: Array<{
    id: string;
    title: string;
    summary: string;
    timeIndex: number;
  }>;
  crossovers: Array<{
    id: string;
    fromSeriesId: string;
    toSeriesId: string;
    rule: any;
  }>;
}

export async function buildCanonPacket(
  universeId: string,
  seriesId?: string
): Promise<CanonPacket> {
  const universe = await prisma.universe.findUnique({
    where: { id: universeId },
  });

  if (!universe) {
    throw new Error(`Universe not found: ${universeId}`);
  }

  // Get top 5 characters sorted by name
  const characters = await prisma.character.findMany({
    where: { universeId },
    orderBy: { name: 'asc' },
    take: 5,
  });

  // Get events sorted by timeIndex then title
  const events = await prisma.canonEvent.findMany({
    where: { universeId },
    orderBy: [{ timeIndex: 'asc' }, { title: 'asc' }],
  });

  // Get crossovers (filter by seriesId if provided)
  const crossovers = await prisma.crossoverRule.findMany({
    where: {
      universeId,
      ...(seriesId ? { fromSeriesId: seriesId } : {}),
    },
  });

  return {
    universe: {
      id: universe.id,
      name: universe.name,
      description: universe.description,
      canonRules: JSON.parse(universe.canonJson || '{}'),
    },
    characters: characters.map(c => ({
      id: c.id,
      name: c.name,
      bio: c.bio,
      traits: JSON.parse(c.traitsJson || '{}'),
    })),
    events: events.map(e => ({
      id: e.id,
      title: e.title,
      summary: e.summary,
      timeIndex: e.timeIndex,
    })),
    crossovers: crossovers.map(c => ({
      id: c.id,
      fromSeriesId: c.fromSeriesId,
      toSeriesId: c.toSeriesId,
      rule: JSON.parse(c.ruleJson || '{}'),
    })),
  };
}

export async function attachCanonToJob(jobId: string, canonPacket: CanonPacket): Promise<void> {
  const job = await prisma.contentJob.findUnique({ where: { id: jobId } });
  if (!job) {
    throw new Error(`Job not found: ${jobId}`);
  }

  const outputs = JSON.parse(job.outputsJson || '{}');
  if (!outputs.meta) {
    outputs.meta = {};
  }
  outputs.meta.canon = {
    universeId: canonPacket.universe.id,
    snapshot: true,
    characterCount: canonPacket.characters.length,
    eventCount: canonPacket.events.length,
  };

  await prisma.contentJob.update({
    where: { id: jobId },
    data: {
      canonPacketJson: JSON.stringify(canonPacket),
      outputsJson: JSON.stringify(outputs),
      universeId: canonPacket.universe.id,
    },
  });
}

