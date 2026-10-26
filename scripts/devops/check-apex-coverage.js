#!/usr/bin/env node
'use strict';
/**
 * Fails when an Apex test run (sf apex run test --json output) has failures, or when coverage of
 * Nexus Core classes (active modules only - package classes such as Nebula Logger are excluded)
 * is below the threshold in config/devops/nexus-devops.json (minApexCoverage).
 *
 * Usage: node scripts/devops/check-apex-coverage.js <test-result.json> [--min 85]
 */
const fs = require('node:fs');
const path = require('node:path');
const repo = require('./lib/repo');

const [resultFile, ...rest] = process.argv.slice(2);
if (!resultFile) {
    console.error('Usage: check-apex-coverage.js <test-result.json> [--min 85]');
    process.exit(2);
}
const config = repo.loadConfig();
const minIndex = rest.indexOf('--min');
const minimum = minIndex === -1 ? config.minApexCoverage : Number(rest[minIndex + 1]);

const run = JSON.parse(fs.readFileSync(resultFile, 'utf8'));
if (!run.result?.summary) {
    console.error(`No test summary in ${resultFile}: ${run.message || 'unknown error'}`);
    process.exit(1);
}
const { summary, tests = [], coverage } = run.result;

const nexusUnits = new Set(
    repo
        .allModules(config)
        .flatMap((dir) => repo.listFiles(dir))
        .filter((f) => /\.(cls|trigger)$/.test(f))
        .map((f) => path.basename(f).replace(/\.(cls|trigger)$/, ''))
);
const rows = (coverage?.coverage || []).filter((c) => nexusUnits.has(c.name));
const covered = rows.reduce((sum, c) => sum + c.totalCovered, 0);
const total = rows.reduce((sum, c) => sum + c.totalLines, 0);
const percent = total === 0 ? 0 : (covered * 100) / total;

console.log(`Apex tests: ${summary.passing} passed, ${summary.failing} failed in ${summary.testExecutionTime}`);
for (const row of rows.filter((c) => c.coveredPercent < 100).sort((a, b) => a.coveredPercent - b.coveredPercent)) {
    console.log(`  ${String(row.coveredPercent).padStart(3)}%  ${row.name}`);
}
console.log(`Nexus Core coverage: ${percent.toFixed(1)}% (${covered}/${total} lines, minimum ${minimum}%)`);

const failures = tests.filter((t) => t.Outcome !== 'Pass');
failures.forEach((t) => console.error(`FAIL ${t.FullName}: ${t.Message}\n     ${t.StackTrace || ''}`));
if (failures.length || Number(summary.failing) > 0) process.exit(1);
if (percent < minimum) {
    console.error(`Coverage ${percent.toFixed(1)}% is below the ${minimum}% minimum.`);
    process.exit(1);
}
