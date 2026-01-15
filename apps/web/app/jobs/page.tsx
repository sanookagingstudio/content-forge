import Link from 'next/link';
import { api } from '../../src/lib/api';

export default async function JobsPage() {
  // This endpoint is not implemented as list (by scope). We show guidance + recent artifacts directory note.
  const health = await api.health();

  return (
    <div>
      <h1 style={{ marginTop: 0 }}>Jobs</h1>
      <div style={{ marginBottom: 12 }}>
        <b>API health:</b> {health.ok ? 'OK' : 'ERROR'}
      </div>
      <p>
        Job generation is available via POST <code>/v1/jobs/generate</code> or CLI <code>content-forge job run &lt;planId&gt;</code>.
      </p>
      <p>
        Job artifacts are written under <code>apps/api/artifacts/jobs/&lt;jobId&gt;.json</code>.
      </p>
      <p>
        View a job detail by navigating to <code>/jobs/&lt;jobId&gt;</code>.
      </p>
      <p style={{ color: '#666' }}>
        Example: <Link href="/jobs/example">/jobs/example</Link> (will 404 unless that job exists).
      </p>
    </div>
  );
}