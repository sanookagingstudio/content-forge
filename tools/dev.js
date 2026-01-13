const { spawn } = require('child_process');
const isWin = process.platform === 'win32';
const npmCmd = isWin ? 'npm.cmd' : 'npm';

function run(args){
  const p = spawn(npmCmd, args, { stdio:'inherit' });
  p.on('exit', (code)=>{ if(code && !process.exitCode) process.exitCode = code; });
}

console.log('[dev] starting api (4000) + web (3000)');
run(['-w','apps/api','run','dev']);
run(['-w','apps/web','run','dev']);
