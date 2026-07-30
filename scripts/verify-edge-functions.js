#!/usr/bin/env node
/**
 * Guards against drift between the maintained Edge Function sources in
 * `infra/supabase/functions/` and the copies under `supabase/functions/` that
 * the Supabase CLI actually deploys (the CLI only reads functions relative to
 * the project root that holds `config.toml`).
 *
 * The two trees silently diverged once already: the deployed copy was missing
 * mobile-money support and the webhook `business_id` backfill. Run this before
 * `supabase functions deploy`.
 */

const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..');
const SOURCE = path.join(ROOT, 'infra', 'supabase', 'functions');
const DEPLOY = path.join(ROOT, 'supabase', 'functions');

// Files that legitimately exist in only one tree.
const IGNORED = new Set(['.env', 'TASK_REPORT.md', '.gitkeep', 'deno.lock']);

function collect(dir, base = dir, acc = new Map()) {
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      collect(full, base, acc);
    } else if (!IGNORED.has(entry.name)) {
      acc.set(path.relative(base, full).split(path.sep).join('/'), fs.readFileSync(full));
    }
  }
  return acc;
}

function main() {
  for (const dir of [SOURCE, DEPLOY]) {
    if (!fs.existsSync(dir)) {
      console.error(`Missing Edge Function directory: ${dir}`);
      process.exit(1);
    }
  }

  const source = collect(SOURCE);
  const deploy = collect(DEPLOY);
  const problems = [];

  for (const [rel, content] of source) {
    if (!deploy.has(rel)) {
      problems.push(`missing from deploy copy: ${rel}`);
    } else if (!content.equals(deploy.get(rel))) {
      problems.push(`content differs: ${rel}`);
    }
  }
  for (const rel of deploy.keys()) {
    if (!source.has(rel)) problems.push(`orphaned in deploy copy: ${rel}`);
  }

  if (problems.length > 0) {
    console.error('Edge Function trees have drifted:\n');
    for (const p of problems) console.error(`  - ${p}`);
    console.error(
      `\nThe maintained source is infra/supabase/functions/.` +
        `\nResync with:\n  cp -r infra/supabase/functions/. supabase/functions/\n`
    );
    process.exit(1);
  }

  console.log(`Edge Functions in sync (${source.size} files checked).`);
}

main();
