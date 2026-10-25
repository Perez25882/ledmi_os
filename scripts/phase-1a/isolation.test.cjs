const test = require('node:test');
const assert = require('node:assert/strict');
const os = require('node:os');
const path = require('node:path');
const { validateManifest, verifyServerIdentity, createOwnedClient } = require('./isolation.cjs');

const runId = '11111111-1111-4111-8111-111111111111';
const root = path.join(os.tmpdir(), `ledgermind-phase1a-${runId}`);
const manifest = { version: 1, runId, root, dataDir: path.join(root, 'data'),
  host: '127.0.0.1', port: 55432, user: 'phase1a_admin',
  database: `phase1a_${runId.replaceAll('-', '')}`, token: 'a'.repeat(64) };

test('only an explicit owned loopback manifest is accepted', () => {
  assert.equal(validateManifest(manifest).host, '127.0.0.1');
  for (const change of [
    { host: 'db.example.com' }, { host: 'localhost' }, { port: 5432 },
    { database: 'postgres' }, { user: 'postgres' }, { token: '' },
    { root: path.resolve('.') }, { dataDir: path.join(os.tmpdir(), 'unknown') },
  ]) assert.throws(() => validateManifest({ ...manifest, ...change }));
  assert.throws(() => validateManifest(undefined));
});

test('server identity mismatch closes the connection before a mutation', async () => {
  let ended = false;
  const client = { query: async () => ({ rows: [{ data_directory: 'unknown', cluster_name: 'other' }] }),
    end: async () => { ended = true; } };
  await assert.rejects(verifyServerIdentity(client, manifest));
  assert.equal(ended, true);
});

test('ambient PostgreSQL credentials and options cannot influence the client', () => {
  const previous = { PGPASSWORD: process.env.PGPASSWORD, PGOPTIONS: process.env.PGOPTIONS };
  try {
    process.env.PGPASSWORD = 'fictional-environment-password';
    process.env.PGOPTIONS = '-c search_path=fictional_schema';
    const client = createOwnedClient(manifest, manifest.database);
    assert.equal(typeof client.password, 'function');
    assert.equal(client.connectionParameters.options, '-c search_path=public');
    assert.equal(process.env.PGPASSWORD, 'fictional-environment-password');
    assert.equal(process.env.PGOPTIONS, '-c search_path=fictional_schema');
  } finally {
    for (const [key, value] of Object.entries(previous)) {
      if (value === undefined) delete process.env[key]; else process.env[key] = value;
    }
  }
});
