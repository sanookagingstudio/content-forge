import Link from 'next/link';
import { api } from '../../src/lib/api';

export default async function JobsPage() {
  const health = await api.health();

  return (
    <div>
      <h1 style={{ marginTop: 0 }}>Jobs</h1>
      <div style={{ marginBottom: 12 }}>
        <b>API health:</b> {health.ok ? 'OK' : 'ERROR'}
      </div>
      <div style={{ marginBottom: 24, padding: 16, background: '#f0f8ff', border: '1px solid #0070f3', borderRadius: 8 }}>
        <h2 style={{ marginTop: 0 }}>Generate Content</h2>
        <p>Create real Thai-first content for multiple platforms with Jarvis advisory.</p>
        <Link href="/jobs/generate" style={{ display: 'inline-block', padding: '12px 24px', background: '#0070f3', color: 'white', textDecoration: 'none', borderRadius: 4 }}>
          Generate Content →
        </Link>
      </div>
      <div style={{ marginTop: 24 }}>
        <h2>Other Options</h2>
        <p>
          Job generation is also available via POST <code>/v1/jobs/generate</code> or CLI <code>content-forge job run &lt;planId&gt;</code>.
        </p>
        <p>
          Job artifacts are written under <code>apps/api/artifacts/jobs/&lt;jobId&gt;.json</code>.
        </p>
        <p>
          View a job detail by navigating to <code>/jobs/&lt;jobId&gt;</code>.
        </p>
      </div>
    </div>
  );
}