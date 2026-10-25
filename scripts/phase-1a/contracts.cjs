const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const assert = require('node:assert/strict');
const { connectIsolated, loadManifest } = require('./isolation.cjs');

const [manifest, output = path.resolve(__dirname, '../../docs/phase-1a/evidence')] = process.argv.slice(2);
const id = () => crypto.randomUUID();
const results = [];
let admin;

async function run(name, description, body) {
  let observation;
  try {
    observation = await body();
    assert.deepEqual(observation.actual, observation.expected, description);
    results.push({ id: name, description, status: 'verified passing behavior', ...observation });
  } catch (error) {
    results.push({ id: name, description,
      status: error.code === 'ERR_ASSERTION' ? 'reproduced failure' : 'test implemented but blocked',
      ...observation, error: { code: error.code, message: error.message } });
  }
}

async function fixture() {
  const f = Object.fromEntries(['business', 'otherBusiness', 'branch', 'otherBranch', 'foreignBranch',
    'owner', 'manager', 'cashier', 'accountant', 'outsider', 'product', 'foreignProduct'].map((key) => [key, id()]));
  await admin.query('BEGIN');
  try {
    for (const who of ['owner', 'manager', 'cashier', 'accountant', 'outsider']) {
      await admin.query('INSERT INTO auth.users(id,email) VALUES($1,$2)', [f[who], `${who}-${f[who]}@fictional.invalid`]);
    }
    await admin.query('INSERT INTO businesses(id,name) VALUES($1,$2),($3,$4)',
      [f.business, `Fictional A ${f.business}`, f.otherBusiness, `Fictional B ${f.otherBusiness}`]);
    await admin.query('INSERT INTO branches(id,business_id,name) VALUES($1,$2,\'A1\'),($3,$2,\'A2\'),($4,$5,\'B1\')',
      [f.branch, f.business, f.otherBranch, f.foreignBranch, f.otherBusiness]);
    for (const who of ['owner', 'manager', 'cashier', 'accountant', 'outsider']) {
      const business = who === 'outsider' ? f.otherBusiness : f.business;
      const role = who === 'outsider' ? 'owner' : who;
      const branch = ['cashier', 'manager'].includes(who) ? f.branch : null;
      await admin.query('INSERT INTO user_business_roles(user_id,business_id,role_id,branch_id) SELECT $1,$2,id,$3 FROM custom_roles WHERE business_id=$2 AND name=$4',
        [f[who], business, branch, role]);
    }
    await admin.query('INSERT INTO products(id,business_id,name,selling_price,cost_price) VALUES($1,$2,\'Fictional product A\',10,5),($3,$4,\'Fictional product B\',10,5)',
      [f.product, f.business, f.foreignProduct, f.otherBusiness]);
    await admin.query('INSERT INTO inventory(product_id,business_id,branch_id,quantity) VALUES($1,$2,$3,10),($4,$5,$6,10)',
      [f.product, f.business, f.branch, f.foreignProduct, f.otherBusiness, f.foreignBranch]);
    await admin.query('COMMIT');
  } catch (error) { await admin.query('ROLLBACK'); throw error; }
  return f;
}

async function transaction(client, role, user, business, body) {
  if (!['anon', 'authenticated', 'service_role'].includes(role)) throw new Error('Invalid fixture role');
  await client.query('BEGIN');
  try {
    await client.query(`SET LOCAL ROLE ${role}`);
    await client.query("SELECT set_config('request.jwt.claims',$1,true)",
      [JSON.stringify({ sub: user, business_id: business, role })]);
    const result = await body(client);
    await client.query('COMMIT');
    return result;
  } catch (error) { await client.query('ROLLBACK'); throw error; }
}

const items = (f, quantity = 1) => [{ product_id: f.product, quantity }];
async function cash(client, f, user = f.cashier, quantity = 1, key = id()) {
  return transaction(client, 'authenticated', user, f.business, async (c) =>
    (await c.query('SELECT process_checkout_cash($1,$2,$3,$4,$5::jsonb,$6::bigint) AS sale',
      [f.business, f.branch, user, key, JSON.stringify(items(f, quantity)), quantity * 1000])).rows[0].sale);
}

async function intent(client, f, quick = false) {
  const lines = quick ? [{ is_quick_sale: true, quick_sale_name: 'Fictional ad hoc item', quantity: 1, unit_price: 10 }] : items(f);
  const row = await transaction(client, 'authenticated', f.cashier, f.business, async (c) =>
    (await c.query('SELECT * FROM create_checkout_intent($1,$2,$3,$4,$5::jsonb,1000,\'card\')',
      [f.business, f.branch, f.cashier, id(), JSON.stringify(lines)])).rows[0]);
  assert.ok(row.intent_id, 'Intent fixture must reach the real RPC');
  await admin.query("INSERT INTO payment_events(payment_intent_id,event_type,provider,provider_event_id,payload,occurred_at) VALUES($1,'payment_captured','paystack',$2,$3::jsonb,now())",
    [row.intent_id, id(), JSON.stringify({ data: { channel: 'card', amount: 1000, currency: 'GHS' } })]);
  return row.intent_id;
}

async function finalize(client, intentId) {
  return transaction(client, 'service_role', null, null, async (c) =>
    (await c.query('SELECT safe_finalize_sale($1) AS sale', [intentId])).rows[0].sale);
}

async function denied(body) {
  try { await body(); return false; }
  catch (error) {
    if (error.code === '42501' || (error.code === 'P0001' && /belong|authorized|permission|cashier/i.test(error.message))) return true;
    throw error;
  }
}

async function waitForBlocked(pids) {
  const deadline = Date.now() + 15000;
  while (Date.now() < deadline) {
    const rows = (await admin.query('SELECT pid,pg_blocking_pids(pid) AS blockers FROM pg_stat_activity WHERE pid=ANY($1::int[])', [pids])).rows;
    if (rows.length === pids.length && rows.every((r) => r.blockers.length > 0)) return rows;
    await new Promise((resolve) => setTimeout(resolve, 25));
  }
  throw new Error('Concurrency barrier not reached; no race reproduction is claimed');
}

async function concurrent(f, operation, allowDomainRejection = false) {
  const clients = [];
  let control;
  let pending = [];
  try {
    control = await connectIsolated(manifest); clients.push(control);
    const a = await connectIsolated(manifest); clients.push(a);
    const b = await connectIsolated(manifest); clients.push(b);
    await control.query('BEGIN');
    await control.query('SELECT 1 FROM inventory WHERE product_id=$1 AND branch_id=$2 FOR UPDATE', [f.product, f.branch]);
    const pids = await Promise.all([a, b].map(async (c) => (await c.query('SELECT pg_backend_pid() AS pid')).rows[0].pid));
    pending = [a, b].map((c, index) => operation(c, index));
    // Attach rejection handlers while the lock barrier is inspected.
    const settled = Promise.allSettled(pending);
    const blockers = await waitForBlocked(pids);
    await control.query('COMMIT');
    const completed = await settled;
    const failed = completed.find((r) => r.status === 'rejected');
    if (failed && !allowDomainRejection) throw failed.reason;
    return { blockers, completed };
  } finally {
    if (control) await control.query('ROLLBACK').catch(() => {});
    await Promise.allSettled(pending);
    await Promise.allSettled(clients.map((c) => c.end()));
  }
}

async function main() {
  fs.mkdirSync(output, { recursive: true });
  admin = await connectIsolated(manifest);
  try {
    const before = (await admin.query("SELECT c.relname,has_table_privilege('authenticated',c.oid,'SELECT') can_select,has_table_privilege('authenticated',c.oid,'INSERT') can_insert FROM pg_class c WHERE c.relnamespace='public'::regnamespace AND c.relkind='r' ORDER BY 1")).rows;
    fs.writeFileSync(path.join(output, 'db-contract-grants-before.json'), JSON.stringify(before, null, 2));
    // Explicit modeled profile: only base tables, preserving the later view and function revocations.
    const tables = (await admin.query("SELECT relname FROM pg_class WHERE relnamespace='public'::regnamespace AND relkind='r'")).rows;
    for (const { relname } of tables) {
      await admin.query(`GRANT SELECT,INSERT,UPDATE,DELETE ON TABLE public."${relname.replaceAll('"', '""')}" TO anon,authenticated,service_role`);
    }

    await run('CONTROL-cash-idempotency', 'Cash RPC replays one stable key without a second deduction', async () => {
      const f = await fixture(); const key = id(); const first = await cash(admin, f, f.cashier, 1, key);
      const second = await cash(admin, f, f.cashier, 1, key);
      const stock = (await admin.query('SELECT quantity FROM inventory WHERE product_id=$1 AND branch_id=$2', [f.product, f.branch])).rows[0].quantity;
      return { expected: { sameSale: true, stock: 9 }, actual: { sameSale: first === second, stock } };
    });
    await run('B-01', 'Second captured sale in one branch/day finalizes', async () => {
      const f = await fixture(); await finalize(admin, await intent(admin, f));
      const second = await intent(admin, f);
      try { await finalize(admin, second); return { expected: 'finalized', actual: 'finalized' }; }
      catch (error) {
        if (error.code !== '22P02' || !/integer/.test(error.message)) throw error;
        return { expected: 'finalized', actual: error.code, databaseMessage: error.message, firstCaptureFinalized: true };
      }
    });
    await run('B-02', 'Captured quick-sale intent finalizes without catalog stock', async () => {
      const f = await fixture(); const pi = await intent(admin, f, true);
      try { await finalize(admin, pi); return { expected: 'finalized', actual: 'finalized' }; }
      catch (error) {
        if (error.code !== 'P0001' || !/Insufficient stock or missing inventory/.test(error.message)) throw error;
        return { expected: 'finalized', actual: error.code, databaseMessage: error.message, quickIntentCreated: true };
      }
    });
    for (const sameKey of [false, true]) await run(sameKey ? 'B-05' : 'B-04',
      sameKey ? 'Concurrent stock receiving deduplicates the same operation' : 'Concurrent receiving preserves both deliveries', async () => {
        const f = await fixture(); const key = id(); const quantities = sameKey ? [5, 5] : [5, 7];
        const race = await concurrent(f, (c, index) => transaction(c, 'authenticated', f.manager, f.business,
          (cx) => cx.query('SELECT process_stock_in($1,$2,$3,\'fictional delivery\',$4)',
            [f.branch, f.product, quantities[index], sameKey ? key : id()])));
        const stock = (await admin.query('SELECT quantity FROM inventory WHERE product_id=$1 AND branch_id=$2', [f.product, f.branch])).rows[0].quantity;
        const logs = Number((await admin.query('SELECT count(*) AS n FROM inventory_logs WHERE product_id=$1 AND branch_id=$2', [f.product, f.branch])).rows[0].n);
        return { expected: sameKey ? { logs: 1, stock: 15 } : { stock: 22 }, actual: sameKey ? { logs, stock } : { stock },
          observedStock: stock, observedLogs: logs, lockBarrier: race.blockers };
      });
    await run('B-06', 'Concurrent refunds cannot exceed original sold quantity', async () => {
      const f = await fixture(); const sale = await cash(admin, f);
      const saleItem = (await admin.query('SELECT id FROM sale_items WHERE sale_id=$1', [sale])).rows[0].id;
      const race = await concurrent(f, (c) => transaction(c, 'authenticated', f.cashier, f.business,
        (cx) => cx.query('SELECT process_refund($1,$2,$3,$4,$5::jsonb,\'fictional return\',$6)',
          [f.business, f.branch, f.cashier, sale, JSON.stringify([{ sale_item_id: saleItem, quantity: 1 }]), id()])), true);
      for (const outcome of race.completed) {
        if (outcome.status === 'rejected' && !(outcome.reason.code === 'P0001' &&
            /^Refund quantity exceeds sold quantity/.test(outcome.reason.message))) throw outcome.reason;
      }
      const refunded = Number((await admin.query('SELECT COALESCE(sum(quantity),0) AS n FROM refund_items WHERE sale_item_id=$1', [saleItem])).rows[0].n);
      return { expected: 1, actual: refunded, originalSoldQuantity: 1, lockBarrier: race.blockers };
    });
    await run('B-07', 'Cashier cannot directly forge a successful payment', async () => {
      const f = await fixture(); const rejected = await denied(() => transaction(admin, 'authenticated', f.cashier, f.business,
        (c) => c.query("INSERT INTO payments(business_id,cashier_id,method,amount,status) VALUES($1,$2,'CASH',999,'SUCCESS')", [f.business, f.cashier])));
      const count = Number((await admin.query('SELECT count(*) AS n FROM payments WHERE business_id=$1', [f.business])).rows[0].n);
      return { expected: true, actual: rejected, independentlyInsertedPayments: count };
    });
    await run('B-08-cart', 'Branch-scoped cashier cannot relocate an active cart', async () => {
      const f = await fixture(); const cart = id();
      await admin.query('INSERT INTO carts(id,business_id,branch_id,cashier_id) VALUES($1,$2,$3,$4)', [cart, f.business, f.branch, f.cashier]);
      const rejected = await denied(() => transaction(admin, 'authenticated', f.cashier, f.business,
        (c) => c.query('UPDATE carts SET branch_id=$1 WHERE id=$2', [f.otherBranch, cart])));
      const branch = (await admin.query('SELECT branch_id FROM carts WHERE id=$1', [cart])).rows[0].branch_id;
      return { expected: true, actual: rejected || branch === f.branch, actualBranch: branch, assignedBranch: f.branch };
    });
    await run('B-08-inventory', 'Branch-scoped manager cannot relocate inventory', async () => {
      const f = await fixture();
      const rejected = await denied(() => transaction(admin, 'authenticated', f.manager, f.business,
        (c) => c.query('UPDATE inventory SET branch_id=$1 WHERE product_id=$2 AND branch_id=$3', [f.otherBranch, f.product, f.branch])));
      const branch = (await admin.query('SELECT branch_id FROM inventory WHERE product_id=$1', [f.product])).rows[0].branch_id;
      return { expected: true, actual: rejected || branch === f.branch, actualBranch: branch, assignedBranch: f.branch };
    });
    await run('B-09', 'Accountant without process_sales cannot run cash checkout', async () => {
      const f = await fixture(); return { expected: true, actual: await denied(() => cash(admin, f, f.accountant)) };
    });
    await run('B-09-refund', 'Accountant without process_sales cannot refund a sale', async () => {
      const f = await fixture(); const sale = await cash(admin, f);
      const saleItem = (await admin.query('SELECT id FROM sale_items WHERE sale_id=$1', [sale])).rows[0].id;
      return { expected: true, actual: await denied(() => transaction(admin, 'authenticated', f.accountant, f.business,
        (c) => c.query('SELECT process_refund($1,$2,$3,$4,$5::jsonb,\'fictional return\',$6)',
          [f.business, f.branch, f.accountant, sale, JSON.stringify([{ sale_item_id: saleItem, quantity: 1 }]), id()]))) };
    });
    await run('B-16', 'Stock receiving rejects another tenant product UUID', async () => {
      const f = await fixture(); const rejected = await denied(() => transaction(admin, 'authenticated', f.owner, f.business,
        (c) => c.query('SELECT process_stock_in($1,$2,1,\'fictional delivery\',$3)', [f.branch, f.foreignProduct, id()])));
      const count = Number((await admin.query('SELECT count(*) AS n FROM inventory WHERE branch_id=$1 AND product_id=$2', [f.branch, f.foreignProduct])).rows[0].n);
      return { expected: true, actual: rejected, ownBusiness: f.business, productBusiness: f.otherBusiness,
        foreignProductInventoryRows: count };
    });
    await run('CONTROL-tenant-read', 'Cashier cannot read another tenant inventory', async () => {
      const f = await fixture(); const count = await transaction(admin, 'authenticated', f.cashier, f.business,
        async (c) => (await c.query('SELECT * FROM inventory WHERE business_id=$1', [f.otherBusiness])).rowCount);
      return { expected: 0, actual: count };
    });
    await run('CONTROL-branch-read', 'Cashier cannot read another assigned business branch inventory', async () => {
      const f = await fixture();
      await admin.query('INSERT INTO inventory(product_id,business_id,branch_id,quantity) VALUES($1,$2,$3,10)', [f.product, f.business, f.otherBranch]);
      const count = await transaction(admin, 'authenticated', f.cashier, f.business,
        async (c) => (await c.query('SELECT * FROM inventory WHERE branch_id=$1', [f.otherBranch])).rowCount);
      return { expected: 0, actual: count };
    });
    await run('CONTROL-outsider-stock', 'Nonmember cannot receive another business stock', async () => {
      const f = await fixture(); return { expected: true, actual: await denied(() =>
        transaction(admin, 'authenticated', f.outsider, f.otherBusiness,
          (c) => c.query('SELECT process_stock_in($1,$2,1,\'fictional\',$3)', [f.branch, f.product, id()]))) };
    });
    await run('CONTROL-service-boundary', 'Authenticated user cannot execute service-only finalizer', async () => {
      const f = await fixture(); return { expected: true, actual: await denied(() =>
        transaction(admin, 'authenticated', f.cashier, f.business, (c) => c.query('SELECT safe_finalize_sale($1)', [id()]))) };
    });
    await run('CONTROL-anonymous-stock', 'Anonymous role cannot receive inventory', async () => {
      const f = await fixture(); return { expected: true, actual: await denied(() =>
        transaction(admin, 'anon', null, null,
          (c) => c.query('SELECT process_stock_in($1,$2,1,\'fictional\',$3)', [f.branch, f.product, id()]))) };
    });
    await run('CONTROL-owner-stock', 'Owner can receive valid same-tenant inventory', async () => {
      const f = await fixture();
      await transaction(admin, 'authenticated', f.owner, f.business,
        (c) => c.query('SELECT process_stock_in($1,$2,2,\'fictional\',$3)', [f.branch, f.product, id()]));
      const quantity = (await admin.query('SELECT quantity FROM inventory WHERE branch_id=$1 AND product_id=$2', [f.branch, f.product])).rows[0].quantity;
      return { expected: 12, actual: quantity };
    });
  } finally { await admin.end(); }
  const summary = { runId: loadManifest(manifest).runId,
    profile: 'Explicit base-table DML grant fixture; views/function revocations preserved. Not a production ACL claim.',
    testTenants: 'fictional only; committed fixture data retained inside the owned cluster',
    results, counts: Object.fromEntries(['reproduced failure', 'verified passing behavior', 'test implemented but blocked'].map((s) => [s, results.filter((r) => r.status === s).length])) };
  fs.writeFileSync(path.join(output, 'db-contract-results.json'), JSON.stringify(summary, null, 2) + '\n');
  console.log(JSON.stringify(summary.counts));
  if (results.some((r) => r.status !== 'verified passing behavior')) process.exitCode = 1;
}

main().catch((error) => { console.error(`Infrastructure failure: ${error.message}`); process.exitCode = 2; });
