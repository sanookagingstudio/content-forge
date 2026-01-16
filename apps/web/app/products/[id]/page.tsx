import { api } from '../../../src/lib/api';

export default async function ProductPage({ params }: { params: { id: string } }) {
  const product = await api.getProduct(params.id);

  if (!product.ok) {
    return (
      <div>
        <h1>Product Export Not Found</h1>
        <p>{product.error?.message}</p>
      </div>
    );
  }

  const p = product.data;
  const manifest = p.manifest || {};

  return (
    <div>
      <h1 style={{ marginTop: 0 }}>Product Export: {p.id}</h1>
      <p><strong>Job ID:</strong> {p.jobId}</p>
      <p><strong>Template:</strong> {p.templateKey}</p>
      <p><strong>Mode:</strong> {p.mode}</p>
      <p><strong>Status:</strong> {p.status}</p>
      <p><strong>Export Path:</strong> {p.exportPath}</p>

      <h2>Manifest Summary</h2>
      {manifest.policySummary && (
        <div style={{ marginTop: 16 }}>
          <h3>Policy</h3>
          <p><strong>Tier:</strong> {manifest.policySummary.tier}</p>
          <p><strong>Gate Required:</strong> {manifest.policySummary.gateRequired ? 'Yes' : 'No'}</p>
          {manifest.policySummary.warnings && manifest.policySummary.warnings.length > 0 && (
            <div>
              <strong>Warnings:</strong>
              <ul>
                {manifest.policySummary.warnings.map((w: string, i: number) => (
                  <li key={i}>{w}</li>
                ))}
              </ul>
            </div>
          )}
        </div>
      )}

      {manifest.canonSummary && (
        <div style={{ marginTop: 16 }}>
          <h3>Canon</h3>
          <p><strong>Universe:</strong> {manifest.canonSummary.universe}</p>
          <p><strong>Characters:</strong> {manifest.canonSummary.characters?.join(', ') || 'None'}</p>
        </div>
      )}

      {manifest.files && (
        <div style={{ marginTop: 16 }}>
          <h3>Files ({manifest.files.length})</h3>
          <ul>
            {manifest.files.map((f: any, i: number) => (
              <li key={i}>{f.path} (hash: {f.hash.slice(0, 8)}...)</li>
            ))}
          </ul>
        </div>
      )}
    </div>
  );
}

