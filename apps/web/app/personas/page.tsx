import { api } from '../../src/lib/api';

export default async function PersonasPage() {
  const personas = await api.listPersonas();
  return (
    <div>
      <h1 style={{ marginTop: 0 }}>Personas</h1>
      {!personas.ok && <ErrorBox code={personas.error.code} message={personas.error.message} />}
      {personas.ok && (
        <div style={{ display: 'grid', gap: 12 }}>
          {personas.data.map((p) => (
            <div key={p.id} style={{ border: '1px solid #eee', borderRadius: 10, padding: 16 }}>
              <div style={{ fontWeight: 700 }}>{p.name}</div>
              <div style={{ color: '#666', fontSize: 12 }}>Brand: {p.brandId}</div>
              <div style={{ marginTop: 8 }}><b>Style:</b> {p.styleGuide || '—'}</div>
              <div style={{ marginTop: 8 }}>
                <b>Do:</b> {p.doDont?.do?.join(' • ') || '—'}
              </div>
              <div>
                <b>Don't:</b> {p.doDont?.dont?.join(' • ') || '—'}
              </div>
              <div style={{ marginTop: 8 }}>
                <b>Examples:</b> {p.examples?.join(' • ') || '—'}
              </div>
            </div>
          ))}
        </div>
      )}
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