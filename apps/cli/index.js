const fs=require('fs');
const path=require('path');
const { doctor } = require('@content-forge/config');
const core=require('@content-forge/core');

function has(flag){ return process.argv.includes(flag); }
function arg(name){ const i=process.argv.indexOf('--'+name); return i>=0 ? process.argv[i+1] : null; }

async function runSample(){
  const repoRoot=process.cwd();
  const artifactsRoot=path.join(repoRoot,'artifacts');
  fs.mkdirSync(artifactsRoot,{recursive:true});
  const jobId='job_'+new Date().toISOString().replace(/[:.]/g,'-');
  const jobDir=path.join(artifactsRoot,jobId);
  fs.mkdirSync(jobDir,{recursive:true});

  const input={
    duration:'1m',
    platforms:['youtube_long','shorts','tiktok','instagram_reel','facebook'],
    publish_mode:'manual',
    identity_pack_id:'AVATAR_BRAND_AMBASSADOR_v1',
    style_pack_id:'STYLE_HIMPAN_CANON_v1',
    language:'th',
    derivatives:{ want_all_ratios:true },
    budget_cap:0
  };
  fs.writeFileSync(path.join(jobDir,'input.json'), JSON.stringify(input,null,2), 'utf8');

  const statePath=path.join(jobDir,'state.json');
  const nodes=[
    core.nodeValidateInput(),
    core.nodeResolveIdentityStyle(repoRoot),
    core.nodePlan(),
    core.nodePackage(),
    core.nodeFidelityGateMock(),
    core.nodeExport()
  ];
  await core.runDAG(nodes,statePath,true);
  console.log('PASS sample jobDir=', jobDir);
}

async function resumeJob(jobDir){
  const repoRoot=process.cwd();
  const statePath=path.join(jobDir,'state.json');
  const nodes=[
    core.nodeValidateInput(),
    core.nodeResolveIdentityStyle(repoRoot),
    core.nodePlan(),
    core.nodePackage(),
    core.nodeFidelityGateMock(),
    core.nodeExport()
  ];
  await core.runDAG(nodes,statePath,true);
  console.log('PASS resume jobDir=', jobDir);
}

(async ()=>{
  const cmd=process.argv[2]||'help';

  if(cmd==='doctor'){
    const r=doctor();
    console.log(JSON.stringify(r,null,2));
    process.exit(r.status==='FAIL'?1:0);
  }

  if(cmd==='run' && has('--sample')){
    await runSample(); return;
  }

  if(cmd==='resume'){
    const jd=arg('jobDir');
    if(!jd) throw new Error('Usage: node apps/cli/index.js resume --jobDir <path>');
    await resumeJob(jd); return;
  }

  console.log('Usage:');
  console.log('  node apps/cli/index.js doctor');
  console.log('  node apps/cli/index.js run --sample');
  console.log('  node apps/cli/index.js resume --jobDir <jobDir>');
})().catch(e=>{ console.error(e); process.exit(1); });
