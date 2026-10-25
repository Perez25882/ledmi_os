const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const crypto = require('node:crypto');
const net = require('node:net');
const { execFileSync } = require('node:child_process');
const { loadManifest, connectOwnedServer, connectIsolated } = require('./isolation.cjs');

const repo = path.resolve(__dirname, '../..');
const evidence = path.join(repo, 'docs/phase-1a/evidence');
const migrations = path.join(repo, 'infra/supabase/migrations');
const seeds = path.join(repo, 'infra/supabase/seed');
const suffix = process.platform === 'win32' ? '.exe' : '';
const hash = (bytes) => crypto.createHash('sha256').update(bytes).digest('hex');

function save(name, value) {
  fs.mkdirSync(evidence, { recursive: true });
  fs.writeFileSync(path.join(evidence, name), JSON.stringify(value, null, 2) + '\n');
}

function pgTool(bin, name, args) {
  const env = { ...process.env };
  for (const key of Object.keys(env)) if (/^PG/i.test(key)) delete env[key];
  const output = path.join(evidence, `native-${name}.txt`);
  const fd = fs.openSync(output, 'w');
  try {
    execFileSync(path.join(bin, name + suffix), args, { timeout: 300000, env,
      stdio: ['ignore', fd, fd] });
    return fs.readFileSync(output, 'utf8');
  } catch (error) {
    fs.writeFileSync(path.join(evidence, `${name}-failure.txt`),
      fs.readFileSync(output, 'utf8') + '\n' + error.message);
    throw error;
  } finally {
    fs.closeSync(fd);
  }
}

function freePort() {
  return new Promise((resolve, reject) => {
    const server = net.createServer();
    server.on('error', reject);
    server.listen(0, '127.0.0.1', () => {
      const port = server.address().port;
      server.close(() => port >= 49152 ? resolve(port) : freePort().then(resolve, reject));
    });
  });
}

async function setup() {
  const pgBin = process.env.PHASE1A_PG_BIN || (process.platform === 'win32'
    ? 'C:/Program Files/PostgreSQL/17/bin' : '/usr/lib/postgresql/17/bin');
  const runId = crypto.randomUUID();
  const root = path.join(os.tmpdir(), `ledgermind-phase1a-${runId}`);
  fs.mkdirSync(root);
  const manifest = { version: 1, runId, root, dataDir: path.join(root, 'data'),
    host: '127.0.0.1', port: await freePort(), user: 'phase1a_admin',
    database: `phase1a_${runId.replaceAll('-', '')}`, token: crypto.randomBytes(32).toString('hex'), pgBin };
  fs.writeFileSync(path.join(root, 'manifest.json'), JSON.stringify(manifest, null, 2), { mode: 0o600 });
  fs.writeFileSync(path.join(evidence, 'database-manifest-path.txt'), path.join(root, 'manifest.json') + '\n');
  const log = pgTool(pgBin, 'initdb', ['-D', manifest.dataDir, '-U', manifest.user, '-A', 'trust', '--no-clean', '--no-locale', '-E', 'UTF8']);
  fs.writeFileSync(path.join(evidence, 'initdb.txt'), log);
  try {
    pgTool(pgBin, 'pg_ctl', ['-D', manifest.dataDir, '-l', path.join(root, 'postgres.log'), '-w',
      '-o', `-h 127.0.0.1 -p ${manifest.port} -c cluster_name=phase1a_${runId}`, 'start']);
    await initializeDatabase(manifest);
  } catch (error) {
    try { await stop(path.join(root, 'manifest.json')); }
    catch (cleanupError) { save('setup-cleanup-blocker.json', { message: cleanupError.message }); }
    throw error;
  }
}

async function initializeDatabase(manifest) {
  let client = await connectOwnedServer(manifest, 'postgres');
  try { await client.query(`CREATE DATABASE "${manifest.database}"`); } finally { await client.end(); }
  client = await connectOwnedServer(manifest, manifest.database);
  try {
    await client.query('CREATE SCHEMA phase1a_control; REVOKE ALL ON SCHEMA phase1a_control FROM PUBLIC; CREATE TABLE phase1a_control.isolation_marker(run_id UUID PRIMARY KEY, token TEXT NOT NULL)');
    await client.query('INSERT INTO phase1a_control.isolation_marker VALUES ($1,$2)', [manifest.runId, manifest.token]);
    await client.query(`
      CREATE ROLE anon NOLOGIN;
      CREATE ROLE authenticated NOLOGIN;
      CREATE ROLE service_role NOLOGIN BYPASSRLS;
      CREATE SCHEMA auth;
      CREATE TABLE auth.users(id UUID PRIMARY KEY, email TEXT);
      CREATE FUNCTION auth.jwt() RETURNS JSONB LANGUAGE SQL STABLE AS
        $$ SELECT COALESCE(NULLIF(current_setting('request.jwt.claims', true), ''), '{}')::jsonb $$;
      CREATE FUNCTION auth.uid() RETURNS UUID LANGUAGE SQL STABLE AS
        $$ SELECT NULLIF(auth.jwt()->>'sub','')::uuid $$;
      GRANT USAGE ON SCHEMA auth TO anon, authenticated, service_role;
    `);
    save('database-isolation.json', { mode: 'native-postgres', runId: manifest.runId, host: manifest.host,
      port: manifest.port, database: manifest.database, user: manifest.user, dataDirectory: manifest.dataDir,
      postgres: (await client.query('SELECT version()')).rows[0].version,
      authFixture: 'minimal auth.users/auth.uid/auth.jwt and DB roles only; no Supabase Auth/PostgREST/Realtime/Storage service',
      productionEnvironmentRead: false, defaultDmlGrants: 'vanilla PostgreSQL; no Supabase implicit grants modeled yet' });
    console.log(`Owned loopback database initialized. Manifest: ${path.join(manifest.root, 'manifest.json')}`);
  } finally { await client.end(); }
}

async function migrate(filename, label) {
  const client = await connectIsolated(filename);
  const results = [];
  try {
    await client.query('CREATE TABLE IF NOT EXISTS schema_migrations(filename TEXT PRIMARY KEY, applied_at TIMESTAMPTZ NOT NULL DEFAULT now())');
    for (const [kind, dir] of [['migration', migrations], ['seed', seeds]]) {
      for (const file of fs.readdirSync(dir).filter((f) => f.endsWith('.sql')).sort()) {
        const sql = fs.readFileSync(path.join(dir, file), 'utf8');
        if ((await client.query('SELECT 1 FROM schema_migrations WHERE filename=$1', [file])).rowCount) {
          results.push({ kind, file, sha256: hash(sql), status: 'already applied' });
          continue;
        }
        try {
          await client.query('BEGIN');
          await client.query(sql);
          await client.query('INSERT INTO schema_migrations(filename) VALUES($1)', [file]);
          await client.query('COMMIT');
          results.push({ kind, file, sha256: hash(sql), status: 'applied' });
        } catch (error) {
          await client.query('ROLLBACK');
          results.push({ kind, file, sha256: hash(sql), status: 'failed', code: error.code,
            message: error.message, detail: error.detail, position: error.position });
          save(`migrations-${label}.json`, { results, success: false });
          throw new Error(`Unchanged ${file} failed (${error.code}): ${error.message}`);
        }
      }
    }
    save(`migrations-${label}.json`, { results, success: true });
    console.log(`Migration workflow complete: ${results.filter((r) => r.status === 'applied').length} applied, ${results.filter((r) => r.status === 'already applied').length} skipped.`);
  } finally { await client.end(); }
}

async function inspect(filename) {
  const client = await connectIsolated(filename);
  try {
    const queries = {
      tables: "SELECT c.relname, c.relrowsecurity, c.relforcerowsecurity, pg_get_userbyid(c.relowner) owner FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='public' AND c.relkind IN ('r','m','v') ORDER BY 1",
      constraints: "SELECT conrelid::regclass::text AS relation, conname, contype, pg_get_constraintdef(oid) AS definition FROM pg_constraint WHERE connamespace='public'::regnamespace ORDER BY 1,2",
      functions: "SELECT p.oid::regprocedure::text AS signature, p.prosecdef, p.proconfig, pg_get_userbyid(p.proowner) owner, has_function_privilege('anon',p.oid,'EXECUTE') anon_execute, has_function_privilege('authenticated',p.oid,'EXECUTE') authenticated_execute, has_function_privilege('service_role',p.oid,'EXECUTE') service_execute FROM pg_proc p WHERE p.pronamespace='public'::regnamespace ORDER BY 1",
      policies: "SELECT tablename,policyname,roles,cmd,qual,with_check FROM pg_policies WHERE schemaname='public' ORDER BY tablename,policyname",
      triggers: "SELECT c.relname,t.tgname,pg_get_triggerdef(t.oid) AS definition FROM pg_trigger t JOIN pg_class c ON c.oid=t.tgrelid JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='public' AND NOT t.tgisinternal ORDER BY 1,2",
      tableGrants: "SELECT c.relname, r.rolname, has_table_privilege(r.rolname,c.oid,'SELECT') can_select, has_table_privilege(r.rolname,c.oid,'INSERT') can_insert, has_table_privilege(r.rolname,c.oid,'UPDATE') can_update, has_table_privilege(r.rolname,c.oid,'DELETE') can_delete FROM pg_class c CROSS JOIN pg_roles r WHERE c.relnamespace='public'::regnamespace AND c.relkind IN ('r','v','m') AND r.rolname IN ('anon','authenticated','service_role') ORDER BY 1,2",
      roles: "SELECT rolname,rolsuper,rolinherit,rolbypassrls,rolcanlogin FROM pg_roles WHERE rolname IN ('anon','authenticated','service_role','phase1a_admin') ORDER BY 1",
      columns: "SELECT table_name,column_name,data_type,is_nullable FROM information_schema.columns WHERE table_schema='public' ORDER BY table_name,ordinal_position",
      extensions: 'SELECT extname, extversion FROM pg_extension ORDER BY extname',
      indexes: "SELECT tablename,indexname,indexdef FROM pg_indexes WHERE schemaname='public' ORDER BY tablename,indexname",
      defaultPrivileges: 'SELECT defaclrole::regrole::text AS owner,defaclnamespace::regnamespace::text AS schema,defaclobjtype,defaclacl FROM pg_default_acl',
      functionDefinitions: "SELECT p.oid::regprocedure::text AS signature, pg_get_functiondef(p.oid) AS definition FROM pg_proc p WHERE p.pronamespace='public'::regnamespace ORDER BY 1",
      history: 'SELECT filename FROM schema_migrations ORDER BY filename',
    };
    const result = {};
    for (const [name, sql] of Object.entries(queries)) result[name] = (await client.query(sql)).rows;
    save('database-catalog.json', result);
    const requiredTables = ['activity_logs','ai_insights','barcode_cache','branches','business_types',
      'businesses','cart_items','carts','categories','custom_roles','inventory','inventory_logs','invoices',
      'payment_events','payment_intents','payment_processing_markers','payments','products','push_subscriptions',
      'refund_items','refunds','sale_items','sales','shifts','starter_catalog_templates','suppliers','user_business_roles','webhook_receipts'];
    const missingTables = requiredTables.filter((name) => !result.tables.some((r) => r.relname === name && r.relrowsecurity));
    const requiredFunctions = ['process_checkout_cash','create_checkout_intent','safe_finalize_sale',
      'process_refund','process_stock_in','open_shift','close_shift','user_accessible_branches'];
    const missingFunctions = requiredFunctions.filter((name) => !result.functions.some((r) => r.signature.startsWith(`${name}(`)));
    const missingConstraints = ['uq_payment_intents_idempotency','invoices_business_id_invoice_number_key']
      .filter((name) => !result.constraints.some((r) => r.conname === name));
    const missingIndexes = ['idx_payment_events_provider_event','uq_payment_marker_intent']
      .filter((name) => !result.indexes.some((r) => r.indexname === name));
    const validation = { expectedApplicationTables: requiredTables.length, missingTables, missingFunctions,
      missingConstraints, missingIndexes, migrationHistoryRows: result.history.length,
      policyCount: result.policies.length, triggerCount: result.triggers.length };
    validation.passed = ![missingTables,missingFunctions,missingConstraints,missingIndexes].some((r) => r.length) &&
      result.history.length === 23 && result.policies.length > 0 && result.triggers.length > 0;
    save('schema-validation.json', validation);
    if (!validation.passed) throw new Error('Schema validation failed; inspect schema-validation.json without repairing migrations');
    console.log(`Inspected ${result.tables.length} relations, ${result.functions.length} functions, ${result.policies.length} policies; effective grants recorded.`);
  } finally { await client.end(); }
}

async function rawRepeat(filename) {
  const client = await connectIsolated(filename);
  const results = [];
  try {
    for (const file of fs.readdirSync(migrations).filter((f) => f.endsWith('.sql')).sort()) {
      await client.query('BEGIN');
      try {
        await client.query(fs.readFileSync(path.join(migrations, file), 'utf8'));
        results.push({ file, status: 'reapplication succeeds (rolled back)' });
      } catch (error) { results.push({ file, status: 'reapplication fails (rolled back)', code: error.code, message: error.message }); }
      finally { await client.query('ROLLBACK'); }
    }
    save('migration-raw-repeat.json', results);
    console.log(`Raw repeat: ${results.filter((r) => r.code).length} failures. Filename-tracked workflow is tested separately.`);
  } finally { await client.end(); }
}

async function stop(filename) {
  const manifest = loadManifest(filename);
  const client = await connectOwnedServer(manifest, 'postgres');
  await client.end();
  pgTool(manifest.pgBin, 'pg_ctl', ['-D', manifest.dataDir, '-m', 'fast', '-w', 'stop']);
  console.log('Owned server stopped. Test data retained; no directory or existing data deleted.');
}

async function main() {
  fs.mkdirSync(evidence, { recursive: true });
  const [command, filename, label = 'first'] = process.argv.slice(2);
  if (command === 'setup') await setup();
  else if (command === 'complete-setup') await initializeDatabase(loadManifest(filename));
  else if (command === 'migrate') await migrate(filename, label);
  else if (command === 'inspect') await inspect(filename);
  else if (command === 'raw-repeat') await rawRepeat(filename);
  else if (command === 'stop') await stop(filename);
  else throw new Error('Usage: node scripts/phase-1a/database.cjs setup|complete-setup|migrate|inspect|raw-repeat|stop [manifest] [label]');
}

if (require.main === module) main().catch((error) => { console.error(error.message); process.exitCode = 1; });
