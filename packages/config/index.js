const fs=require('fs');
const path=require('path');
const dotenv=require('dotenv');
const { z }=require('zod');

const EnvSchema = z.object({
  CF_WEB_ORIGIN: z.string().default('http://localhost:3000'),
  CF_API_ORIGIN: z.string().default('http://localhost:4000'),
  CF_STORAGE_BASE: z.string().default(path.resolve(process.cwd(),'artifacts')),
  CF_AUTH_MODE: z.enum(['dev','oidc']).default('dev'),
  CF_OIDC_ISSUER_URL: z.string().optional(),
  CF_OIDC_CLIENT_ID: z.string().optional(),
  CF_OIDC_AUDIENCE: z.string().optional()
});

function loadDotenvIfExists(p){
  if(fs.existsSync(p)){ dotenv.config({ path:p, override:false }); return true; }
  return false;
}

function loadEnv(){
  const sharedPath = process.env.FUNAGING_SHARED_ENV || 'D:\\\\.secrets\\\\funaging_shared.env';
  const projectPath = path.resolve(process.cwd(),'.secrets','content_forge.env');
  const loaded = { shared: loadDotenvIfExists(sharedPath), project: loadDotenvIfExists(projectPath) };
  const parsed = EnvSchema.safeParse(process.env);
  return { ok: parsed.success, env: parsed.success?parsed.data:null, issues: parsed.success?[]:parsed.error.issues, loaded, paths:{sharedPath,projectPath} };
}

function doctor(){
  const r = loadEnv();
  const blockers=[], warnings=[];
  if(!r.loaded.shared) warnings.push('Shared env not found: '+r.paths.sharedPath);
  if(!r.loaded.project) warnings.push('Project env not found: '+r.paths.projectPath);
  if(!r.ok) return { status:'FAIL', blockers:['Env schema invalid: '+JSON.stringify(r.issues)], warnings };

  if(r.env.CF_AUTH_MODE==='oidc'){
    const miss=['CF_OIDC_ISSUER_URL','CF_OIDC_CLIENT_ID','CF_OIDC_AUDIENCE'].filter(k=>!process.env[k]);
    if(miss.length) blockers.push('OIDC enabled but missing: '+miss.join(', '));
  }
  return { status:blockers.length?'PASS_WITH_BLOCKER':'PASS', blockers, warnings, effective:r.env };
}

module.exports = { loadEnv, doctor };
