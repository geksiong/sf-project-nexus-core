#!/usr/bin/env node
'use strict';
/**
 * Regression test for the Nexus PMD ruleset: runs config/pmd/nexus-apex-rules.xml against
 * config/pmd/fixtures and asserts the exact set of violations in fixtures/expected.json.
 */
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { execFileSync } = require('node:child_process');
const repo = require('./lib/repo');

const fixtures = path.join(repo.ROOT, 'config/pmd/fixtures');
const expected = JSON.parse(fs.readFileSync(path.join(fixtures, 'expected.json'), 'utf8')).violations;
const outFile = path.join(fs.mkdtempSync(path.join(os.tmpdir(), 'nexus-pmd-')), 'results.json');

let stderr = '';
try {
    execFileSync(
        'sf',
        ['code-analyzer', 'run', '--workspace', fixtures, '--rule-selector', 'pmd:Custom', '--output-file', outFile],
        {
            cwd: repo.ROOT,
            stdio: ['ignore', 'ignore', 'pipe']
        }
    );
} catch (error) {
    // Violations do not fail the run without --severity-threshold; any other failure leaves no output file.
    stderr = String(error.stderr || '');
}
if (!fs.existsSync(outFile)) {
    console.error(`Code Analyzer produced no results file.\n${stderr}`);
    process.exit(1);
}

const results = JSON.parse(fs.readFileSync(outFile, 'utf8'));
const actual = (results.violations || [])
    .filter((v) => v.rule.startsWith('Nexus'))
    .map((v) => {
        const location = v.locations[v.primaryLocationIndex || 0];
        return `${path.basename(location.file)}:${location.startLine}:${v.rule}`;
    });
const wanted = expected.map((v) => `${v.file}:${v.line}:${v.rule}`);

const missing = wanted.filter((v) => !actual.includes(v));
const unexpected = actual.filter((v) => !wanted.includes(v));
missing.forEach((v) => console.error(`MISSING    ${v} (rule no longer fires)`));
unexpected.forEach((v) => console.error(`UNEXPECTED ${v} (false positive)`));
if (missing.length || unexpected.length) process.exit(1);
console.log(`Nexus PMD rules OK: ${wanted.length} expected violations, no false positives.`);
