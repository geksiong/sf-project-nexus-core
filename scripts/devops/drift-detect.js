#!/usr/bin/env node
'use strict';
/**
 * Drift detection (BP-DEVOPS-008 gate 2): retrieves every component of the active modules from a
 * target org and compares it with the source in git.
 *
 *   MODIFIED        component exists in the org but differs from source
 *   MISSING_IN_ORG  component is in source but was not retrieved from the org
 *
 * Retrieval re-serialises metadata (element order, entity encoding, number format, defaults the
 * server adds or omits), so XML is compared semantically: every element in source must exist in the
 * org with the same value. Types listed in NOISY_TYPES are reported as warnings only.
 *
 * Usage: node scripts/devops/drift-detect.js --target-org <alias> [--report drift-report.md]
 * Exit codes: 0 no drift, 1 drift found, 2 usage / retrieval error.
 */
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { execFileSync } = require('node:child_process');
const repo = require('./lib/repo');

// Server-side normalisation makes these unreliable to diff; drift is reported but does not fail.
const NOISY_TYPES = new Set(['layouts', 'flexipages', 'reports', 'dashboards', 'applications', 'approvalProcesses']);

function parseArgs() {
    const args = process.argv.slice(2);
    const get = (name) => {
        const i = args.indexOf(name);
        return i === -1 ? null : args[i + 1];
    };
    const targetOrg = get('--target-org') || get('-o');
    if (!targetOrg) {
        console.error('Usage: drift-detect.js --target-org <alias> [--report drift-report.md]');
        process.exit(2);
    }
    return { targetOrg, reportFile: get('--report'), keep: args.includes('--keep') };
}

function sf(args, cwd) {
    let out;
    try {
        out = execFileSync('sf', [...args, '--json'], {
            cwd,
            encoding: 'utf8',
            maxBuffer: 64 * 1024 * 1024,
            stdio: ['ignore', 'pipe', 'pipe']
        });
    } catch (error) {
        // sf exits non-zero on failure but still prints a JSON error document on stdout.
        out = error.stdout;
        if (!out) throw error;
    }
    const result = JSON.parse(out);
    if (result.status !== 0) throw new Error(`sf ${args.slice(0, 3).join(' ')}: ${result.message}`);
    return result;
}

const ENTITIES = { '&amp;': '&', '&lt;': '<', '&gt;': '>', '&quot;': '"', '&apos;': "'" };

/** Parses XML into {name, attrs, text, children}; keeps only xsi:nil among attributes. */
function parseXml(xml) {
    const tokens =
        xml
            .replace(/<\?xml[^>]*\?>/, '')
            .replace(/<!--[\s\S]*?-->/g, '')
            .match(/<[^>]+>|[^<]+/g) || [];
    const root = { name: '#root', nil: false, text: '', children: [] };
    const stack = [root];
    for (const token of tokens) {
        if (token.startsWith('</')) {
            stack.pop();
        } else if (token.startsWith('<')) {
            const node = {
                name: token.slice(1).split(/[\s/>]/)[0],
                nil: /xsi:nil="true"/.test(token),
                text: '',
                children: []
            };
            stack[stack.length - 1].children.push(node);
            if (!token.endsWith('/>')) stack.push(node);
        } else if (token.trim()) {
            stack[stack.length - 1].text += token.trim().replace(/&(amp|lt|gt|quot|apos);/g, (m) => ENTITIES[m]);
        }
    }
    return root;
}

function sameText(a, b) {
    if (a === b) return true;
    const na = Number(a);
    const nb = Number(b);
    return a !== '' && b !== '' && !Number.isNaN(na) && !Number.isNaN(nb) && na === nb;
}

const isDefaultLeaf = (node) => !node.children.length && (node.text === '' || node.text === 'false');

/**
 * True when every element in `source` is present in `org` with the same value (order-insensitive).
 * Elements only the org has are server defaults and are ignored, as are source leaves holding a
 * default value (false / empty) that the server omits.
 */
function containedIn(source, org) {
    if (source.nil !== org.nil && !(source.nil && org.text === '')) return false;
    if (!source.children.length) return sameText(source.text, org.text);
    const available = [...org.children];
    for (const child of source.children) {
        const index = available.findIndex(
            (candidate) => candidate.name === child.name && containedIn(child, candidate)
        );
        if (index !== -1) {
            available.splice(index, 1);
        } else if (!isDefaultLeaf(child)) {
            return false;
        }
    }
    return true;
}

function differs(file, sourceContent, orgContent) {
    if (file.endsWith('.xml')) return !containedIn(parseXml(sourceContent), parseXml(orgContent));
    const normalise = (content) =>
        content
            .replace(/\r\n/g, '\n')
            .replace(/[ \t]+$/gm, '')
            .trim();
    return normalise(sourceContent) !== normalise(orgContent);
}

function main() {
    const { targetOrg, reportFile, keep } = parseArgs();
    const config = repo.loadConfig();
    const project = repo.loadProject();
    const work = fs.mkdtempSync(path.join(os.tmpdir(), 'nexus-drift-'));
    let exitCode = 2;

    try {
        // 1. Manifest of everything in the active modules (respects .forceignore).
        const manifestArgs = ['project', 'generate', 'manifest', '--output-dir', work, '--name', 'package.xml'];
        config.activeModules.forEach((dir) => manifestArgs.push('--source-dir', dir));
        sf(manifestArgs, repo.ROOT);

        // 2. Retrieve into a throwaway single-directory project.
        fs.mkdirSync(path.join(work, 'force-app'));
        fs.writeFileSync(
            path.join(work, 'sfdx-project.json'),
            JSON.stringify({
                packageDirectories: [{ path: 'force-app', default: true }],
                sourceApiVersion: project.sourceApiVersion
            })
        );
        sf(
            ['project', 'retrieve', 'start', '--manifest', 'package.xml', '--target-org', targetOrg, '--wait', '20'],
            work
        );

        // 3. Index retrieved files by metadata key.
        const retrieved = new Map();
        const walk = (dir) => {
            for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
                const full = path.join(dir, entry.name);
                if (entry.isDirectory()) walk(full);
                else {
                    const relative = path.relative(work, full).split(path.sep).join('/');
                    const key = repo.metadataKey(relative);
                    if (key) retrieved.set(key, full);
                }
            }
        };
        walk(path.join(work, 'force-app'));

        // 4. Compare.
        const drift = [];
        let compared = 0;
        for (const file of config.activeModules.flatMap((dir) => repo.listFiles(dir))) {
            const key = repo.metadataKey(file);
            if (!key || file.includes('/__tests__/') || file.endsWith('.md')) continue;
            compared++;
            const type = key.split('/')[0];
            const orgFile = retrieved.get(key);
            if (!orgFile) {
                drift.push({ status: 'MISSING_IN_ORG', file, type });
            } else if (differs(file, repo.readText(file), fs.readFileSync(orgFile, 'utf8'))) {
                drift.push({ status: 'MODIFIED', file, type });
            }
        }

        const blocking = drift.filter((d) => !NOISY_TYPES.has(d.type));
        const advisory = drift.filter((d) => NOISY_TYPES.has(d.type));
        const lines = [
            `# Drift report: ${targetOrg}`,
            '',
            `Compared ${compared} source files from ${config.activeModules.join(', ')} with the org (${new Date().toISOString()}).`,
            ''
        ];
        if (!drift.length) lines.push('No drift detected.');
        if (blocking.length) {
            lines.push(
                '## Drift',
                '',
                '| Status | File |',
                '| --- | --- |',
                ...blocking.map((d) => `| ${d.status} | \`${d.file}\` |`),
                ''
            );
        }
        if (advisory.length) {
            lines.push(
                '## Advisory (server-normalised types, review manually)',
                '',
                '| Status | File |',
                '| --- | --- |',
                ...advisory.map((d) => `| ${d.status} | \`${d.file}\` |`),
                ''
            );
        }
        const report = lines.join('\n');
        console.log(report);
        if (reportFile) fs.writeFileSync(reportFile, `${report}\n`);
        exitCode = blocking.length ? 1 : 0;
    } catch (error) {
        console.error(`Drift detection failed: ${error.message}`);
        exitCode = 2;
    } finally {
        if (keep) console.error(`Retrieved project kept at ${work}`);
        else fs.rmSync(work, { recursive: true, force: true });
    }
    process.exit(exitCode);
}

main();
