const Fastify=require('fastify');
const cors=require('@fastify/cors');
const fs=require('fs');
const path=require('path');
const { doctor, loadEnv } = require('@content-forge/config');
const core=require('@content-forge/core');

function safeJoin(base, target){
  const targetPath = path.normalize(target).replace(/^(\.\.(\/|\\\|$))+/, '');
  const p = path.join(base, targetPath);
  if(!p.startsWith(base)) throw new Error('Path traversal blocked');
  return p;
}

(async ()=>{
  const f=Fastify({ logger:true });
  const d=doctor();
  const envRes=loadEnv();
  const webOrigin = (envRes.ok && envRes.env && envRes.env.CF_WEB_ORIGIN) ? envRes.env.CF_WEB_ORIGIN : 'http://localhost:3000';
  await f.register(cors,{ origin:[webOrigin], credentials:true });

  f.get('/health', async()=>({ ok:true, doctor_status:d.status, blockers:d.blockers||[], warnings:d.warnings||[] }));

  f.post('/v1/jobs', async(req, reply)=>{
    const repoRoot=process.cwd();
    const artifactsRoot=path.join(repoRoot,'artifacts');
    fs.mkdirSync(artifactsRoot,{recursive:true});

    const jobId='job_'+new Date().toISOString().replace(/[:.]/g,'-');
    const jobDir=path.join(artifactsRoot,jobId);
    fs.mkdirSync(jobDir,{recursive:true});

    const input = (req.body && req.body.input) ? req.body.input : null;
    const defaultInput={
      duration:'1m',
      platforms:['youtube_long','shorts'],
      publish_mode:'manual',
      identity_pack_id:'AVATAR_BRAND_AMBASSADOR_v1',
      style_pack_id:'STYLE_HIMPAN_CANON_v1',
      language:'th',
      derivatives:{ want_all_ratios:true },
      budget_cap:0
    };
    fs.writeFileSync(path.join(jobDir,'input.json'), JSON.stringify(input||defaultInput,null,2),'utf8');

    const statePath=path.join(jobDir,'state.json');
    const nodes=[
      core.nodeValidateInput(),
      core.nodeResolveIdentityStyle(repoRoot),
      core.nodePlan(),
      core.nodePackage(),
      core.nodeFidelityGateMock(),
      core.nodeExport()
    ];

    try{
      await core.runDAG(nodes,statePath,true);
      return { status:'PASS', jobId, jobDir };
    }catch(e){
      reply.code(500);
      return { status:'FAIL', jobId, jobDir, error:String(e && e.message ? e.message : e) };
    }
  });

  f.post('/v1/jobs/:jobId/resume', async(req, reply)=>{
    const repoRoot=process.cwd();
    const jobId=req.params.jobId;
    const jobDir=path.join(repoRoot,'artifacts',jobId);
    const statePath=path.join(jobDir,'state.json');
    if(!fs.existsSync(jobDir)) return reply.code(404).send({status:'NOT_FOUND', jobId});
    const nodes=[
      core.nodeValidateInput(),
      core.nodeResolveIdentityStyle(repoRoot),
      core.nodePlan(),
      core.nodePackage(),
      core.nodeFidelityGateMock(),
      core.nodeExport()
    ];
    try{
      await core.runDAG(nodes,statePath,true);
      return { status:'PASS', jobId, jobDir };
    }catch(e){
      reply.code(500);
      return { status:'FAIL', jobId, jobDir, error:String(e && e.message ? e.message : e) };
    }
  });

  f.get('/v1/jobs/:jobId', async(req, reply)=>{
    const repoRoot=process.cwd();
    const jobId=req.params.jobId;
    const statePath=path.join(repoRoot,'artifacts',jobId,'state.json');
    if(!fs.existsSync(statePath)) return reply.code(404).send({status:'NOT_FOUND', jobId});
    return JSON.parse(fs.readFileSync(statePath,'utf8'));
  });

  f.get('/v1/artifacts/:jobId/*', async(req, reply)=>{
    const repoRoot=process.cwd();
    const jobId=req.params.jobId;
    const rel=req.params['*']||'';
    const jobDir=path.join(repoRoot,'artifacts',jobId);
    if(!fs.existsSync(jobDir)) return reply.code(404).send('NOT_FOUND');
    const p=safeJoin(jobDir, rel);
    if(!fs.existsSync(p)) return reply.code(404).send('NOT_FOUND');
    const st=fs.statSync(p);
    if(st.isDirectory()) return reply.code(400).send('DIRECTORY');
    reply.type('application/octet-stream');
    return fs.createReadStream(p);
  });

  await f.listen({ port:4000, host:'0.0.0.0' });
})().catch(e=>{ console.error(e); process.exit(1); });
