export type ApiOk<T> = { ok: true; data: T };
export type ApiErr = { ok: false; error: { code: string; message: string; details?: unknown } };

export type Brand = {
  id: string;
  name: string;
  voiceTone: string;
  prohibitedTopics: string;
  targetAudience: string;
  channels: string[];
  createdAt: string;
  updatedAt: string;
};

export type Persona = {
  id: string;
  brandId: string;
  name: string;
  styleGuide: string;
  doDont: { do: string[]; dont: string[] };
  examples: string[];
  createdAt: string;
  updatedAt: string;
};

export type Plan = {
  id: string;
  brandId: string;
  scheduledAt: string;
  channel: string;
  seriesId?: string | null;
  objective: string;
  cta: string;
  assetRequirements: string;
  createdAt: string;
  updatedAt: string;
};

export type Job = {
  id: string;
  planId: string;
  status: string;
  createdAt: string;
  updatedAt: string;
};

const baseUrl = process.env.NEXT_PUBLIC_API_BASE_URL || 'http://localhost:4000';

async function http<T>(path: string, init?: RequestInit): Promise<ApiOk<T> | ApiErr> {
  const res = await fetch(`${baseUrl}${path}`, {
    ...init,
    headers: {
      'content-type': 'application/json',
      ...(init?.headers || {}),
    },
    cache: 'no-store',
  });
  const json = await res.json();
  return json;
}

export const api = {
  health: () => http<{ ok: true; service: string; ts: string }>(`/health`),

  listBrands: () => http<Brand[]>(`/v1/brands`),
  createBrand: (b: { name: string; voiceTone?: string; prohibitedTopics?: string; targetAudience?: string; channels?: string[] }) =>
    http<Brand>(`/v1/brands`, { method: 'POST', body: JSON.stringify(b) }),

  listPersonas: () => http<Persona[]>(`/v1/personas`),
  createPersona: (p: { brandId: string; name: string; styleGuide?: string; doDont?: any; examples?: string[] }) =>
    http<Persona>(`/v1/personas`, { method: 'POST', body: JSON.stringify(p) }),

  listPlans: (q?: { from?: string; to?: string; channel?: string }) => {
    const qs = new URLSearchParams();
    if (q?.from) qs.set('from', q.from);
    if (q?.to) qs.set('to', q.to);
    if (q?.channel) qs.set('channel', q.channel);
    const suffix = qs.toString() ? `?${qs.toString()}` : '';
    return http<any[]>(`/v1/plans${suffix}`);
  },
  createPlan: (p: any) => http<Plan>(`/v1/plans`, { method: 'POST', body: JSON.stringify(p) }),

  generateJob: (req: {
    brandId?: string;
    planId?: string;
    personaId?: string;
    topic: string;
    objective: string;
    platforms?: ('facebook' | 'instagram' | 'tiktok' | 'youtube')[];
    options?: { language?: 'th' | 'en'; tone?: string; length?: 'short' | 'medium' | 'long' };
  }) => http<any>(`/v1/jobs/generate`, { method: 'POST', body: JSON.stringify(req) }),
  getJob: (id: string) => http<any>(`/v1/jobs/${id}`),
};