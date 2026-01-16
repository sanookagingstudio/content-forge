import { api } from '../../../src/lib/api';

export default async function UniverseDetailPage({ params }: { params: { id: string } }) {
  const universe = await api.getUniverse(params.id);

  if (!universe.ok) {
    return (
      <div>
        <h1>Universe Not Found</h1>
        <p>{universe.error?.message}</p>
      </div>
    );
  }

  const u = universe.data;

  return (
    <div>
      <h1 style={{ marginTop: 0 }}>{u.name}</h1>
      <p>{u.description}</p>
      <p><strong>Language:</strong> {u.language}</p>

      <h2>Characters ({u.characters.length})</h2>
      <table style={{ width: '100%', borderCollapse: 'collapse', marginTop: 8 }}>
        <thead>
          <tr style={{ borderBottom: '2px solid #ddd', textAlign: 'left' }}>
            <th style={{ padding: 8 }}>Name</th>
            <th style={{ padding: 8 }}>Bio</th>
            <th style={{ padding: 8 }}>Traits</th>
          </tr>
        </thead>
        <tbody>
          {u.characters.map((c: any) => (
            <tr key={c.id} style={{ borderBottom: '1px solid #eee' }}>
              <td style={{ padding: 8 }}>{c.name}</td>
              <td style={{ padding: 8 }}>{c.bio}</td>
              <td style={{ padding: 8 }}>
                {c.traits && typeof c.traits === 'object' ? (
                  <pre style={{ margin: 0, fontSize: '12px' }}>{JSON.stringify(c.traits, null, 2)}</pre>
                ) : (
                  'N/A'
                )}
              </td>
            </tr>
          ))}
        </tbody>
      </table>

      <h2>Canon Events ({u.events.length})</h2>
      <table style={{ width: '100%', borderCollapse: 'collapse', marginTop: 8 }}>
        <thead>
          <tr style={{ borderBottom: '2px solid #ddd', textAlign: 'left' }}>
            <th style={{ padding: 8 }}>Time Index</th>
            <th style={{ padding: 8 }}>Title</th>
            <th style={{ padding: 8 }}>Summary</th>
          </tr>
        </thead>
        <tbody>
          {u.events.map((e: any) => (
            <tr key={e.id} style={{ borderBottom: '1px solid #eee' }}>
              <td style={{ padding: 8 }}>{e.timeIndex}</td>
              <td style={{ padding: 8 }}>{e.title}</td>
              <td style={{ padding: 8 }}>{e.summary}</td>
            </tr>
          ))}
        </tbody>
      </table>

      <h2>Crossovers ({u.crossovers.length})</h2>
      {u.crossovers.length > 0 ? (
        <table style={{ width: '100%', borderCollapse: 'collapse', marginTop: 8 }}>
          <thead>
            <tr style={{ borderBottom: '2px solid #ddd', textAlign: 'left' }}>
              <th style={{ padding: 8 }}>From Series</th>
              <th style={{ padding: 8 }}>To Series</th>
              <th style={{ padding: 8 }}>Rules</th>
            </tr>
          </thead>
          <tbody>
            {u.crossovers.map((c: any) => (
              <tr key={c.id} style={{ borderBottom: '1px solid #eee' }}>
                <td style={{ padding: 8 }}>{c.fromSeriesId}</td>
                <td style={{ padding: 8 }}>{c.toSeriesId}</td>
                <td style={{ padding: 8 }}>
                  {c.rule && typeof c.rule === 'object' ? (
                    <pre style={{ margin: 0, fontSize: '12px' }}>{JSON.stringify(c.rule, null, 2)}</pre>
                  ) : (
                    'N/A'
                  )}
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      ) : (
        <p>No crossovers defined.</p>
      )}
    </div>
  );
}

