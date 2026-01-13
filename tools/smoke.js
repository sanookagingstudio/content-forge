const { spawn } = require('child_process');
const http = require('http');
const isWin = process.platform === 'win32';
const nodeCmd = isWin ? 'node.exe' : 'node';

function wait(ms){ return new Promise(r=>setTimeout(r,ms)); }
function get(url){
  return new Promise((resolve,reject)=>{
    const req=http.get(url,(res)=>{
      let data=''; res.on('data',c=>data+=c);
      res.on('end',()=>resolve({status:res.statusCode, body:data}));
    });
    req.on('error',reject);
  });
}
function runNode(args){
  return new Promise((resolve,reject)=>{
    const p=spawn(nodeCmd,args,{stdio:'inherit'});
    p.on('exit',(c)=>c===0?resolve():reject(new Error('exit code '+c)));
  });
}

(async ()=>{
  console.log('[smoke] doctor');
  await runNode(['apps/cli/index.js','doctor']);

  console.log('[smoke] sample job');
  await runNode(['apps/cli/index.js','run','--sample']);

  console.log('[smoke] start api');
  const api=spawn(nodeCmd,['apps/api/server.js'],{stdio:'inherit'});
  await wait(900);

  const r = await get('http://localhost:4000/health');
  if(r.status!==200) throw new Error('health status='+r.status+' body='+r.body);
  const j = JSON.parse(r.body);
  if(!j.ok) throw new Error('health ok!=true body='+r.body);

  console.log('[smoke] PASS /health ok');
  api.kill();
})().catch(e=>{ console.error('[smoke] FAIL', e.message); process.exit(1); });
