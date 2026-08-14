const { Client } = require("pg");
const fs = require("fs"); const path = require("path");
const env = fs.readFileSync(path.join(__dirname,"..","ledgermindv1-main",".env"),"utf8");
const get = k => (env.split(/\r?\n/).find(l=>l.startsWith(k+"="))||"").slice(k.length+1).trim();
(async()=>{
 const c=new Client({connectionString:get("DATABASE_URL"),ssl:{rejectUnauthorized:false}});await c.connect();
 const mv=await c.query("SELECT c.relname,r.rolname g,count(*) n FROM pg_class c JOIN pg_namespace ns ON ns.oid=c.relnamespace AND ns.nspname='public' CROSS JOIN LATERAL aclexplode(c.relacl) a JOIN pg_roles r ON r.oid=a.grantee WHERE c.relname IN ('mv_daily_sales','mv_stock_velocity','v_inventory_snapshot') AND r.rolname IN ('anon','authenticated') GROUP BY 1,2 ORDER BY 1,2");
 console.log("view grants anon/authenticated (expect none):"); mv.rows.forEach(x=>console.log("  "+x.relname+" "+x.g+" n="+x.n)); if(!mv.rows.length)console.log("  (none)");
 const fn=await c.query("SELECT p.proname,r.rolname g FROM pg_proc p JOIN pg_namespace ns ON ns.oid=p.pronamespace AND ns.nspname='public' CROSS JOIN LATERAL aclexplode(COALESCE(p.proacl,acldefault('f',p.proowner))) a JOIN pg_roles r ON r.oid=a.grantee WHERE p.proname IN ('safe_finalize_sale','process_payment_capture','process_stock_in') AND r.rolname IN ('anon','authenticated') AND a.privilege_type='EXECUTE' ORDER BY 1,2");
 console.log("fn EXECUTE anon/authenticated:"); fn.rows.forEach(x=>console.log("  "+x.proname+" "+x.g)); if(!fn.rows.length)console.log("  (none)");
 const v=await c.query("SELECT reloptions FROM pg_class WHERE relname='v_inventory_snapshot'"); console.log("v_inventory_snapshot reloptions:",JSON.stringify(v.rows[0].reloptions));
 const tg=await c.query("SELECT tgname, c.relname FROM pg_trigger t JOIN pg_class c ON c.oid=t.tgrelid WHERE tgname LIKE 'trg_%branch_write' ORDER BY 1"); console.log("branch-write triggers:"); tg.rows.forEach(x=>console.log("  "+x.tgname+" on "+x.relname));
 const pol=await c.query("SELECT tablename,policyname FROM pg_policies WHERE schemaname='public' AND (policyname LIKE 'shifts_%' OR policyname LIKE 'refunds_%') ORDER BY 1,2"); console.log("shifts/refunds policies:"); pol.rows.forEach(x=>console.log("  "+x.tablename+"."+x.policyname));
 await c.end();
})().catch(e=>{console.error("ERR",e.message);process.exit(1)});