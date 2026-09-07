import test from 'node:test';
import assert from 'node:assert/strict';
import {terminalDocument} from '../terminal-output.mjs';
import {previewTarget,Previews} from '../previews.mjs';
import {mkdtempSync,rmSync} from 'node:fs';
import {join} from 'node:path';
import {tmpdir} from 'node:os';

test('terminal transport retains colour, emphasis and OSC links without executing controls',()=>{
 const doc=terminalDocument('\x1b[1;38;2;137;180;250mTitle\x1b[0m plain\n\x1b]8;;https://example.com/path?q=1\x07Open preview\x1b]8;;\x07\x1b[2J');
 assert.equal(doc.text,'Title plain\nOpen preview');
 assert.equal(doc.runs[0].color,'#89b4fa'); assert.equal(doc.runs[0].bold,true);
 assert.equal(doc.runs[1].bold,undefined); assert.equal(doc.runs[2].link,'https://example.com/path?q=1');
 const unsafe=terminalDocument('\x1b]8;;javascript:alert(1)\x07Text\x1b]8;;\x07');
 assert.equal(unsafe.runs[0].link,undefined); assert.equal(unsafe.text,'Text');
});
test('palette colours and extended background parameters do not corrupt foreground style',()=>{
 const doc=terminalDocument('\x1b[38;5;2mgreen\x1b[48;2;1;2;3mbackground\x1b[39mdefault');
 assert.equal(doc.runs[0].color,'#A8D5A2'); assert.equal(doc.runs[1].bold,undefined); assert.equal(doc.runs[1].color,'#A8D5A2'); assert.equal(doc.runs[2].color,undefined);
});
test('private preview targets accept only explicit local HTTP development ports',()=>{
 assert.deepEqual(previewTarget('http://localhost:5173/page?a=b#section'),{port:5173,suffix:'/page?a=b#section'});
 for(const url of ['file:///etc/passwd','http://evil.example:3000','http://user:pass@localhost:3000','http://localhost:8790','http://127.0.0.1:22','http://localhost','https://localhost:3000']) assert.throws(()=>previewTarget(url));
});
test('preview allocation preserves existing Tailscale routes, reuses a slot and survives restart',async()=>{
 const root=mkdtempSync(join(tmpdir(),'herdr-previews-')); const config={databasePath:join(root,'state.sqlite'),publicURL:'https://mac.tail.test.ts.net:8443'};
 const runtime={locked:async(_,work)=>work(),resolve:async()=>({machine:{id:'mac',name:'Mac',remote:false}})};
 const status={TCP:{443:{HTTPS:true},8443:{HTTPS:true},8444:{HTTPS:true}},Web:{'mac.tail.test.ts.net:8444':{Handlers:{'/':{Proxy:'http://127.0.0.1:9999'}}}}}; let writes=0;
 const runner=async(_,args)=>{
  if(args[1]==='status')return {stdout:JSON.stringify(status)};
  writes++; assert.deepEqual(args,['serve','--bg','--https=8445','http://127.0.0.1:19045']);
  status.TCP[8445]={HTTPS:true};status.Web['mac.tail.test.ts.net:8445']={Handlers:{'/':{Proxy:args.at(-1)}}};return {stdout:''};
 };
 try {
  let previews=new Previews(config,runtime,runner);previews.reachable=async()=>{};previews.relay=async()=>{};
  assert.equal((await previews.open('mac/term','http://localhost:5173/page?q=1')).url,'https://mac.tail.test.ts.net:8445/page?q=1');
  previews=new Previews(config,runtime,runner);previews.reachable=async()=>{};previews.relay=async()=>{};
  await previews.open('mac/term','http://localhost:5173/other');assert.equal(writes,1);
  status.Web['mac.tail.test.ts.net:8445'].Handlers['/'].Proxy='http://127.0.0.1:9998';
  await assert.rejects(previews.open('mac/term','http://localhost:5173/'),/another service/);assert.equal(writes,1);
 } finally {rmSync(root,{recursive:true});}
});

test('a stale stop-sharing request cannot remove a later preview on the same port',async()=>{
 const root=mkdtempSync(join(tmpdir(),'herdr-preview-identity-'));
 const config={databasePath:join(root,'state.sqlite'),publicURL:'https://mac.tail.test.ts.net:8443'};
 const runtime={locked:async(_,work)=>work(),resolve:async()=>({machine:{id:'mac',name:'Mac',remote:false}})};
 const status={TCP:{},Web:{}};
 const runner=async(_,args)=>{
  if(args[1]==='status')return{stdout:JSON.stringify(status)};
  if(args.at(-1)==='off'){delete status.TCP[8444];delete status.Web['mac.tail.test.ts.net:8444'];}
  else{status.TCP[8444]={HTTPS:true};status.Web['mac.tail.test.ts.net:8444']={Handlers:{'/':{Proxy:args.at(-1)}}};}
  return {stdout:''};
 };
 try{
  const previews=new Previews(config,runtime,runner);previews.reachable=async()=>{};previews.relay=async()=>{};
  const first=await previews.open('mac/term','http://localhost:5173/');await previews.remove(first.id);
  const next=await previews.open('mac/term','http://localhost:5174/');assert.notEqual(next.id,first.id);
  await previews.remove(first.id);assert.equal(previews.list().previews[0].id,next.id);assert.ok(status.TCP[8444]);
 }finally{rmSync(root,{recursive:true});}
});
