import { api } from '../../../src/lib/api';

export default async function JobDetailPage({ params }: { params: { id: string } }) {
  const job = await api.getJob(params.id);

  if (!job.ok) {
    return (
      <div>
        <h1 style={{ marginTop: 0 }}>Job {params.id}</h1>
        <div style={{ border: '1px solid #f3c', background: '#fff5fb', padding: 12, borderRadius: 10 }}>
          <b>{job.error.code}</b>: {job.error.message}
        </div>
      </div>
    );
  }

  const outputs = job.data.outputs || {};
  return (
    <div>
      <h1 style={{ marginTop: 0 }}>Job {job.data.id}</h1>
      <div style={{ color: '#666', fontSize: 12 }}>
        Status: {job.data.status} • Created: {new Date(job.data.createdAt).toLocaleString()}
      </div>

      <Section title="Title" text={outputs.title} />
      <Section title="Hook" text={outputs.hook} />
      <Section title="Body" text={outputs.body} />
      <Section title="CTA" text={outputs.cta} />
      <Section title="Hashtags" text={(outputs.hashtags || []).join(' ')} />
      <Section title="Deterministic Hash" text={outputs.deterministicHash} />

      <h2>Raw Outputs</h2>
      <pre style={{ background: '#fafafa', border: '1px solid #eee', padding: 12, borderRadius: 10, overflowX: 'auto' }}>
        {JSON.stringify(outputs, null, 2)}
      </pre>
    </div>
  );
}

function Section({ title, text }: { title: string; text: string }) {
  return (
    <div style={{ marginTop: 16 }}>
      <div style={{ fontWeight: 700, marginBottom: 6 }}>{title}</div>
      <div style={{ border: '1px solid #eee', borderRadius: 10, padding: 12, whiteSpace: 'pre-wrap' }}>{text || '—'}</div>
    </div>
  );
}