import { api } from '../src/lib/api';

export default async function Dashboard() {
  const [brands, personas, plans] = await Promise.all([
    api.listBrands(),
    api.listPersonas(),
    api.listPlans(),
  ]);

  const brandCount = brands.ok ? brands.data.length : 0;
  const personaCount = personas.ok ? personas.data.length : 0;
  const planCount = plans.ok ? plans.data.length : 0;

  return (
    <div>
      <h1 style={{ marginTop: 0 }}>Dashboard</h1>
      <div style={{ display: 'flex', gap: 12, flexWrap: 'wrap' }}>
        <Card title="Brands" value={brandCount} />
        <Card title="Personas" value={personaCount} />
        <Card title="Plans" value={planCount} />
      </div>
      <p style={{ marginTop: 16, color: '#444' }}>
        This is the V1 foundation UI: basic CRUD surfaces for brands/personas/plans and deterministic job generation.
      </p>
    </div>
  );
}

function Card({ title, value }: { title: string; value: number }) {
  return (
    <div style={{ border: '1px solid #eee', borderRadius: 10, padding: 16, width: 220 }}>
      <div style={{ color: '#666', fontSize: 12 }}>{title}</div>
      <div style={{ fontSize: 32, fontWeight: 700 }}>{value}</div>
    </div>
  );
}