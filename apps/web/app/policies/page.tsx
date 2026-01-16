import { api } from '../../src/lib/api';

export default async function PoliciesPage() {
  const policies = await api.getPolicies();

  return (
    <div>
      <h1 style={{ marginTop: 0 }}>Policy Profiles</h1>
      <p>Platform-specific content policies and risk thresholds.</p>
      {policies.ok ? (
        <table style={{ width: '100%', borderCollapse: 'collapse', marginTop: 16 }}>
          <thead>
            <tr style={{ borderBottom: '2px solid #ddd', textAlign: 'left' }}>
              <th style={{ padding: 8 }}>Name</th>
              <th style={{ padding: 8 }}>Platform</th>
              <th style={{ padding: 8 }}>Active</th>
              <th style={{ padding: 8 }}>Rules</th>
            </tr>
          </thead>
          <tbody>
            {policies.data.map((p: any) => (
              <tr key={p.id} style={{ borderBottom: '1px solid #eee' }}>
                <td style={{ padding: 8 }}>{p.name}</td>
                <td style={{ padding: 8 }}>{p.platform}</td>
                <td style={{ padding: 8 }}>{p.isActive ? '✓' : ''}</td>
                <td style={{ padding: 8 }}>
                  {p.rules && typeof p.rules === 'object' ? (
                    <pre style={{ margin: 0, fontSize: '12px' }}>{JSON.stringify(p.rules, null, 2)}</pre>
                  ) : (
                    'N/A'
                  )}
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      ) : (
        <p style={{ color: '#d00' }}>Failed to load policies: {policies.error?.message}</p>
      )}
    </div>
  );
}

