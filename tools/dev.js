const { spawn } = require('child_process');

function run(cmd, args){
  // shell:true => let OS resolve npm properly (fixes spawn EINVAL on some Windows setups)
  const p = spawn(cmd, args, { stdio: 'inherit', shell: true, windowsHide: false });
  p.on('exit', (code) => { if(code && !process.exitCode) process.exitCode = code; });
  p.on('error', (err) => {
    console.error('[dev] spawn error:', err && err.message ? err.message : err);
    console.error('[dev] fallback (run in 2 terminals):');
    console.error('  npm -w apps/api run dev');
    console.error('  npm -w apps/web run dev');
    process.exitCode = 1;
  });
}

console.log('[dev] starting api (4000) + web (3000)');
run('npm', ['-w','apps/api','run','dev']);
run('npm', ['-w','apps/web','run','dev']);
