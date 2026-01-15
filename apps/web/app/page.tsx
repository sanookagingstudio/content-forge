import Link from 'next/link';

export default function Dashboard() {
  return (
    <div>
      <h1 style={{ marginTop: 0 }}>Dashboard</h1>
      <p style={{ marginTop: 16, color: '#444', marginBottom: 24 }}>
        Welcome to Content Forge V1 Foundation. Manage your content creation workflow.
      </p>
      <div style={{ display: 'flex', flexDirection: 'column', gap: 12 }}>
        <Link href="/brands" style={{ display: 'block', padding: 12, border: '1px solid #eee', borderRadius: 8, textDecoration: 'none', color: 'inherit' }}>
          <strong>Brands</strong> — Manage brand definitions and voice
        </Link>
        <Link href="/personas" style={{ display: 'block', padding: 12, border: '1px solid #eee', borderRadius: 8, textDecoration: 'none', color: 'inherit' }}>
          <strong>Personas</strong> — Define target audience personas
        </Link>
        <Link href="/planner" style={{ display: 'block', padding: 12, border: '1px solid #eee', borderRadius: 8, textDecoration: 'none', color: 'inherit' }}>
          <strong>Planner</strong> — Create and manage content plans
        </Link>
        <Link href="/jobs" style={{ display: 'block', padding: 12, border: '1px solid #eee', borderRadius: 8, textDecoration: 'none', color: 'inherit' }}>
          <strong>Jobs</strong> — View content generation jobs
        </Link>
      </div>
    </div>
  );
}