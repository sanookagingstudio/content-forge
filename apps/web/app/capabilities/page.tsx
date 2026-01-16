import { api } from '../../src/lib/api';

export default async function CapabilitiesPage() {
  const capabilities = await api.getCapabilities();

  return (
    <div>
      <h1 style={{ marginTop: 0 }}>Capability Providers</h1>
      <p>Available AI providers for content generation.</p>
      {capabilities.ok ? (
        <table style={{ width: '100%', borderCollapse: 'collapse', marginTop: 16 }}>
          <thead>
            <tr style={{ borderBottom: '2px solid #ddd', textAlign: 'left' }}>
              <th style={{ padding: 8 }}>Name</th>
              <th style={{ padding: 8 }}>Kind</th>
              <th style={{ padding: 8 }}>Cost</th>
              <th style={{ padding: 8 }}>Quality</th>
              <th style={{ padding: 8 }}>Speed</th>
              <th style={{ padding: 8 }}>Languages</th>
              <th style={{ padding: 8 }}>Policy Tags</th>
              <th style={{ padding: 8 }}>Default</th>
            </tr>
          </thead>
          <tbody>
            {capabilities.data.map((p: any) => (
              <tr key={p.id} style={{ borderBottom: '1px solid #eee' }}>
                <td style={{ padding: 8 }}>{p.name}</td>
                <td style={{ padding: 8 }}>{p.kind}</td>
                <td style={{ padding: 8 }}>{p.costTier}</td>
                <td style={{ padding: 8 }}>{p.qualityTier}</td>
                <td style={{ padding: 8 }}>{p.speedTier}</td>
                <td style={{ padding: 8 }}>{Array.isArray(p.languages) ? p.languages.join(', ') : ''}</td>
                <td style={{ padding: 8 }}>{Array.isArray(p.policyTags) ? p.policyTags.join(', ') : ''}</td>
                <td style={{ padding: 8 }}>{p.isDefault ? '✓' : ''}</td>
              </tr>
            ))}
          </tbody>
        </table>
      ) : (
        <p style={{ color: '#d00' }}>Failed to load capabilities: {capabilities.error?.message}</p>
      )}
    </div>
  );
}

