const { spawn } = require('child_process');
function run(cmd, args){
  const p = spawn(cmd, args, { stdio:'inherit', shell:true });
  p.on('exit', (code)=>{ if(code && !process.exitCode) process.exitCode = code; });
}
console.log('[dev] starting api (4000) + web (3000)');
run('npm',['-w','apps/api','run','dev']);
run('npm',['-w','apps/web','run','dev']);
