import { api } from '../../src/lib/api';

export default async function BrandsPage() {
  const brands = await api.listBrands();
  return (
    <div>
      <h1 style={{ marginTop: 0 }}>Brands</h1>
      {!brands.ok && <ErrorBox code={brands.error.code} message={brands.error.message} />}
      {brands.ok && (
        <div style={{ display: 'grid', gap: 12 }}>
          {brands.data.map((b) => (
            <div key={b.id} style={{ border: '1px solid #eee', borderRadius: 10, padding: 16 }}>
              <div style={{ fontWeight: 700 }}>{b.name}</div>
              <div style={{ color: '#666', fontSize: 12 }}>Tone: {b.voiceTone}</div>
              <div style={{ marginTop: 8 }}><b>Audience:</b> {b.targetAudience}</div>
              <div><b>Channels:</b> {b.channels.join(', ')}</div>
              <div><b>Prohibited:</b> {b.prohibitedTopics || '—'}</div>
            </div>
          ))}
        </div>
      )}
      <p style={{ marginTop: 16, color: '#666' }}>
        Create is available via API; UI creation forms are deferred to the hardening ONEPACK.
      </p>
    </div>
  );
}

function ErrorBox({ code, message }: { code: string; message: string }) {
  return (
    <div style={{ border: '1px solid #f3c', background: '#fff5fb', padding: 12, borderRadius: 10 }}>
      <b>{code}</b>: {message}
    </div>
  );
}