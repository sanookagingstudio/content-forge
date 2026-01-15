import './globals.css';
import Link from 'next/link';

export const metadata = {
  title: 'Content Forge',
  description: 'Content Forge V1 Foundation',
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en">
      <body style={{ fontFamily: 'system-ui, -apple-system, Segoe UI, Roboto, Arial, sans-serif', margin: 0 }}>
        <div style={{ display: 'flex', minHeight: '100vh' }}>
          <aside style={{ width: 240, borderRight: '1px solid #eee', padding: 16 }}>
            <div style={{ fontWeight: 700, marginBottom: 12 }}>Content Forge</div>
            <nav style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
              <Link href="/">Dashboard</Link>
              <Link href="/brands">Brands</Link>
              <Link href="/personas">Personas</Link>
              <Link href="/planner">Planner</Link>
              <Link href="/jobs">Jobs</Link>
            </nav>
            <div style={{ marginTop: 16, fontSize: 12, color: '#666' }}>
              API: {process.env.NEXT_PUBLIC_API_BASE_URL || 'http://localhost:4000'}
            </div>
          </aside>
          <main style={{ flex: 1, padding: 24 }}>{children}</main>
        </div>
      </body>
    </html>
  );
}