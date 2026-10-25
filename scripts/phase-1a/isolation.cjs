const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { Client } = require('pg');

function samePath(a, b) {
  const canonical = (value) => {
    const resolved = path.resolve(value);
    return process.platform === 'win32' ? resolved.toLowerCase() : resolved;
  };
  return canonical(a) === canonical(b);
}

function validateManifest(value) {
  if (!value || value.version !== 1 || !/^[a-f0-9-]{36}$/.test(value.runId || '')) {
    throw new Error('An explicit Phase 1A manifest is required');
  }
  const expectedRoot = path.join(os.tmpdir(), `ledgermind-phase1a-${value.runId}`);
  if (!samePath(value.root, expectedRoot) || !samePath(value.dataDir, path.join(expectedRoot, 'data')) ||
      value.host !== '127.0.0.1' || !Number.isInteger(value.port) || value.port < 49152 || value.port > 65535 ||
      value.user !== 'phase1a_admin' || value.database !== `phase1a_${value.runId.replaceAll('-', '')}` ||
      !/^[a-f0-9]{64}$/.test(value.token || '')) {
    throw new Error('Refusing a non-owned database target');
  }
  return value;
}

function loadManifest(filename) {
  if (!filename) throw new Error('Pass the manifest path explicitly; environment database URLs are never read');
  const value = validateManifest(JSON.parse(fs.readFileSync(filename, 'utf8')));
  if (!samePath(fs.realpathSync(value.root), value.root) ||
      !samePath(fs.realpathSync(value.dataDir), value.dataDir) ||
      !samePath(fs.realpathSync(filename), path.join(value.root, 'manifest.json'))) {
    throw new Error('Refusing redirected cluster or manifest paths');
  }
  return value;
}

async function verifyServerIdentity(client, manifest) {
  try {
    const { rows: [server] } = await client.query(
      "SELECT current_setting('data_directory') AS data_directory, current_setting('cluster_name') AS cluster_name, host(inet_server_addr()) AS address, inet_server_port() AS port");
    if (!samePath(server.data_directory, manifest.dataDir) || server.cluster_name !== `phase1a_${manifest.runId}` ||
        server.address !== manifest.host || Number(server.port) !== manifest.port) {
      throw new Error('Server identity does not match the newly initialized cluster');
    }
  } catch (error) {
    await client.end();
    throw error;
  }
  return client;
}

function createOwnedClient(manifest, database) {
  validateManifest(manifest);
  const previous = Object.fromEntries(Object.entries(process.env).filter(([key]) => /^PG/i.test(key)));
  try {
    for (const key of Object.keys(previous)) delete process.env[key];
    return new Client({ host: manifest.host, port: manifest.port, user: manifest.user,
      database, password: async () => '', ssl: false, options: '-c search_path=public',
      connectionTimeoutMillis: 3000, query_timeout: 20000, application_name: 'ledgermind-phase1a' });
  } finally {
    Object.assign(process.env, previous);
  }
}

async function connectOwnedServer(manifest, database) {
  const client = createOwnedClient(manifest, database);
  await client.connect();
  return verifyServerIdentity(client, manifest);
}

async function connectIsolated(filename) {
  const manifest = loadManifest(filename);
  const client = await connectOwnedServer(manifest, manifest.database);
  try {
    const { rows } = await client.query('SELECT run_id::text, token FROM phase1a_control.isolation_marker');
    if (rows.length !== 1 || rows[0].run_id !== manifest.runId || rows[0].token !== manifest.token) {
      throw new Error('Isolation marker mismatch');
    }
    return client;
  } catch (error) {
    await client.end();
    throw error;
  }
}

module.exports = { validateManifest, loadManifest, verifyServerIdentity, createOwnedClient, connectOwnedServer, connectIsolated };
