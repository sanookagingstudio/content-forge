import { api } from '../../src/lib/api';

export default async function PlannerPage() {
  const plans = await api.listPlans();
  return (
    <div>
      <h1 style={{ marginTop: 0 }}>Planner</h1>
      {!plans.ok && <ErrorBox code={plans.error.code} message={plans.error.message} />}
      {plans.ok && (
        <table style={{ width: '100%', borderCollapse: 'collapse' }}>
          <thead>
            <tr>
              <th style={th}>Scheduled</th>
              <th style={th}>Channel</th>
              <th style={th}>Objective</th>
              <th style={th}>CTA</th>
            </tr>
          </thead>
          <tbody>
            {plans.data.map((p: any) => (
              <tr key={p.id}>
                <td style={td}>{new Date(p.scheduledAt).toLocaleString()}</td>
                <td style={td}>{p.channel}</td>
                <td style={td}>{p.objective}</td>
                <td style={td}>{p.cta}</td>
              </tr>
            ))}
          </tbody>
        </table>
      )}
      <p style={{ marginTop: 16, color: '#666' }}>
        Generate jobs via CLI or API. Jobs UI is in the Jobs page.
      </p>
    </div>
  );
}

const th: React.CSSProperties = { textAlign: 'left', borderBottom: '1px solid #eee', padding: 8, color: '#666', fontSize: 12 };
const td: React.CSSProperties = { borderBottom: '1px solid #f3f3f3', padding: 8 };

function ErrorBox({ code, message }: { code: string; message: string }) {
  return (
    <div style={{ border: '1px solid #f3c', background: '#fff5fb', padding: 12, borderRadius: 10 }}>
      <b>{code}</b>: {message}
    </div>
  );
}