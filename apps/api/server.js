const Fastify=require('fastify'); const cors=require('@fastify/cors');
const { doctor } = require('@content-forge/config');
(async ()=>{
  const f=Fastify({ logger:true });
  const d=doctor();
  await f.register(cors,{ origin:['http://localhost:3000'], credentials:true });
  f.get('/health', async()=>({ ok:true, doctor_status:d.status, blockers:d.blockers||[], warnings:d.warnings||[] }));
  await f.listen({ port:4000, host:'0.0.0.0' });
})().catch(e=>{ console.error(e); process.exit(1); });
