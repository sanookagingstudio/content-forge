const React=require('react');
module.exports=function Home(){
  const [h,setH]=React.useState(null);
  React.useEffect(()=>{ fetch('http://localhost:4000/health').then(r=>r.json()).then(setH).catch(e=>setH({error:String(e)})); },[]);
  return React.createElement('pre',null,JSON.stringify(h,null,2));
};
