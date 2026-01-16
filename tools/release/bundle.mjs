import { execSync } from 'child_process';
import { writeFileSync, mkdirSync, copyFileSync, readFileSync } from 'fs';
import { join, dirname } from 'path';
import { fileURLToPath } from 'url';
import archiver from 'archiver';
import { createWriteStream } from 'fs';

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);
const repoRoot = join(__dirname, '../..');

// Get version and stamp
const pkg = JSON.parse(readFileSync(join(repoRoot, 'package.json'), 'utf8'));
const version = pkg.version || '0.3.6';
const stamp = new Date().toISOString().replace(/[:.]/g, '-').slice(0, -5);
const bundleName = `content-forge_${version}_${stamp}`;
const distDir = join(repoRoot, 'dist', 'release');
const bundlePath = join(distDir, `${bundleName}.zip`);

console.log(`[bundle] Creating release bundle: ${bundleName}`);

// Ensure dist/release exists
mkdirSync(distDir, { recursive: true });

// Ensure builds exist
console.log('[bundle] Ensuring builds are complete...');
try {
  execSync('npm run build', { cwd: repoRoot, stdio: 'inherit' });
} catch (e) {
  console.error('[bundle] Build failed, aborting');
  process.exit(1);
}

// Create bundle
const output = createWriteStream(bundlePath);
const archive = archiver('zip', { zlib: { level: 9 } });

output.on('close', () => {
  console.log(`[bundle] Created: ${bundlePath} (${archive.pointer()} bytes)`);
});

archive.on('error', (err) => {
  throw err;
});

archive.pipe(output);

// Add API build
const apiDist = join(repoRoot, 'apps', 'api', 'dist');
archive.directory(apiDist, 'api/dist');

// Add Web build (.next)
const webNext = join(repoRoot, 'apps', 'web', '.next');
archive.directory(webNext, 'web/.next');

// Add Prisma schema and migrations
archive.directory(join(repoRoot, 'apps', 'api', 'prisma'), 'api/prisma');

// Add package manifests
archive.file(join(repoRoot, 'package.json'), { name: 'package.json' });
archive.file(join(repoRoot, 'apps', 'api', 'package.json'), { name: 'apps/api/package.json' });
archive.file(join(repoRoot, 'apps', 'web', 'package.json'), { name: 'apps/web/package.json' });

// Add README_RELEASE.md
const readmeRelease = `# Content Forge Release Bundle

Version: ${version}
Built: ${new Date().toISOString()}

## Prerequisites

- Node.js >= 20.0.0
- npm >= 9.0.0

## Setup

1. Extract this bundle
2. Run: \`npm install --production\`
3. Run: \`npm --prefix apps/api run db:generate\`
4. Run: \`npm --prefix apps/api run db:migrate\` (if needed)

## Start Services

### API Server
\`\`\`
npm --prefix apps/api start
\`\`\`
Default port: 4000

### Web Server
\`\`\`
npm --prefix apps/web start
\`\`\`
Default port: 3000

## Environment Variables

Set \`DATABASE_URL\` for Prisma (defaults to \`file:./prisma/dev.db\`).

## Notes

- This bundle includes built artifacts only
- Source code is not included
- Prisma migrations are included for database setup
`;

writeFileSync(join(repoRoot, 'dist', 'release', 'README_RELEASE.md'), readmeRelease);
archive.file(join(repoRoot, 'dist', 'release', 'README_RELEASE.md'), { name: 'README_RELEASE.md' });

archive.finalize();

