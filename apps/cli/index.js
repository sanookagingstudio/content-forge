const { doctor } = require('@content-forge/config');
const cmd = process.argv[2] || 'help';
if(cmd==='doctor'){
  const r = doctor();
  console.log(JSON.stringify(r,null,2));
  process.exit(r.status==='FAIL'?1:0);
}
console.log('Usage: node apps/cli/index.js doctor');
