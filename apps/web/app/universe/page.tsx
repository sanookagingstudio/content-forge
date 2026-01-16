import { api } from '../../src/lib/api';
import Link from 'next/link';

export default async function UniversePage() {
  const universes = await api.getUniverses();

  return (
    <div>
      <h1 style={{ marginTop: 0 }}>Universes</h1>
      <p>IP Factory - Canon Memory across series.</p>
      {universes.ok ? (
        <table style={{ width: '100%', borderCollapse: 'collapse', marginTop: 16 }}>
          <thead>
            <tr style={{ borderBottom: '2px solid #ddd', textAlign: 'left' }}>
              <th style={{ padding: 8 }}>Name</th>
              <th style={{ padding: 8 }}>Description</th>
              <th style={{ padding: 8 }}>Language</th>
              <th style={{ padding: 8 }}>Actions</th>
            </tr>
          </thead>
          <tbody>
            {universes.data.map((u: any) => (
              <tr key={u.id} style={{ borderBottom: '1px solid #eee' }}>
                <td style={{ padding: 8 }}>{u.name}</td>
                <td style={{ padding: 8 }}>{u.description}</td>
                <td style={{ padding: 8 }}>{u.language}</td>
                <td style={{ padding: 8 }}>
                  <Link href={`/universe/${u.id}`} style={{ color: '#0070f3', textDecoration: 'none' }}>
                    View Canon
                  </Link>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      ) : (
        <p style={{ color: '#d00' }}>Failed to load universes: {universes.error?.message}</p>
      )}
    </div>
  );
}

