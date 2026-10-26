'use strict';
/**
 * Shared helpers for Nexus Core DevOps gates: configuration, module layout, .forceignore-aware
 * file walking and a symbol index of the metadata each module defines.
 */
const fs = require('node:fs');
const path = require('node:path');

const ROOT = path.resolve(__dirname, '..', '..', '..');

/** Metadata folders whose first path segment identifies the metadata type (source format). */
const TYPE_DIRS = new Set([
    'applications',
    'approvalProcesses',
    'aura',
    'classes',
    'customMetadata',
    'customPermissions',
    'dashboards',
    'flexipages',
    'flows',
    'layouts',
    'lwc',
    'namedCredentials',
    'objects',
    'permissionsetgroups',
    'permissionsets',
    'quickActions',
    'reports',
    'roles',
    'tabs',
    'triggers',
    'workflows',
    'omniIntegrationProcedures',
    'omniScripts',
    'omniUiCard',
    'omniDataTransforms',
    'uiWidgets',
    'lightningTypes',
    'aiAuthoringBundles',
    'mcpServerDefinitions',
    'profiles',
    'sharingRules',
    'networks',
    'sites',
    'navigationMenus',
    'experiences',
    'digitalExperiences',
    'digitalExperienceConfigs',
    'uiBundles',
    'wave',
    'waveTemplates'
]);

function readJson(relativePath) {
    return JSON.parse(fs.readFileSync(path.join(ROOT, relativePath), 'utf8'));
}

function loadConfig() {
    return readJson('config/devops/nexus-devops.json');
}

/**
 * Modules for a profile: "headless" (CI scratch org) = activeModules; any other profile adds its
 * "<profile>ProfileModules" list ("full": OmniStudio, Experience Cloud, ...; "agentforce": HXL, MCP).
 */
function profileModules(config, profile = 'headless') {
    return [...config.activeModules, ...(config[`${profile}ProfileModules`] || [])];
}

/** Every module in any profile: the static gates audit them all. */
function allModules(config) {
    const extra = Object.entries(config)
        .filter(([key]) => key.endsWith('ProfileModules'))
        .flatMap(([, modules]) => modules);
    return [...new Set([...config.activeModules, ...extra])];
}

function loadProject() {
    return readJson('sfdx-project.json');
}

/** @returns {{name: string, path: string, rank: number, dependencies: string[]}[]} */
function loadModules() {
    return loadProject().packageDirectories.map((dir) => ({
        name: dir.package,
        path: dir.path,
        rank: Number.parseInt(path.basename(dir.path), 10),
        dependencies: (dir.dependencies || []).map((dep) => dep.package)
    }));
}

function loadForceIgnore() {
    const file = path.join(ROOT, '.forceignore');
    if (!fs.existsSync(file)) {
        return [];
    }
    return fs
        .readFileSync(file, 'utf8')
        .split('\n')
        .map((line) => line.trim())
        .filter((line) => line && !line.startsWith('#'));
}

function isIgnored(relativePath, patterns) {
    return patterns.some((pattern) => {
        const glob = pattern.endsWith('/') ? `${pattern}**` : pattern;
        return (
            path.matchesGlob(relativePath, glob) ||
            path.matchesGlob(relativePath, `**/${glob}`) ||
            path.matchesGlob(path.basename(relativePath), glob)
        );
    });
}

/** Recursively lists repo-relative file paths under a directory, honouring .forceignore. */
function listFiles(relativeDir, { includeIgnored = false } = {}) {
    const patterns = includeIgnored ? [] : loadForceIgnore();
    const results = [];
    const walk = (dir) => {
        const absolute = path.join(ROOT, dir);
        if (!fs.existsSync(absolute)) {
            return;
        }
        for (const entry of fs.readdirSync(absolute, { withFileTypes: true })) {
            const child = path.posix.join(dir, entry.name);
            if (entry.isDirectory()) {
                if (entry.name !== 'node_modules') {
                    walk(child);
                }
            } else if (!isIgnored(child, patterns)) {
                results.push(child);
            }
        }
    };
    walk(relativeDir);
    return results.sort();
}

/** Path from the metadata type folder onwards, e.g. classes/Foo.cls or objects/Account/fields/X.field-meta.xml */
function metadataKey(relativePath) {
    const parts = relativePath.split('/');
    // Last type-named folder wins: feature folders may share a type's name (modules/x/reports/reports/...).
    let index = -1;
    for (let i = 1; i < parts.length - 1; i++) {
        if (TYPE_DIRS.has(parts[i]) && !(parts[i - 1] === 'lwc' || parts[i - 1] === 'aura')) index = i;
    }
    return index === -1 ? null : parts.slice(index).join('/');
}

function readText(relativePath) {
    return fs.readFileSync(path.join(ROOT, relativePath), 'utf8');
}

/** Removes Apex/JS comments (keeps string literals, which may hold dynamic references). */
function stripComments(source) {
    return source.replace(/\/\*[\s\S]*?\*\//g, '').replace(/(^|[^:'"])\/\/.*$/gm, '$1');
}

/**
 * Builds the symbols each module defines. Keys are symbol names (Apex classes, custom objects,
 * custom fields as Object.Field and bare Field, LWC, flows, tabs, apps, permission sets, widgets,
 * custom lightning types); values are the defining module names.
 */
function buildSymbolIndex(modules, config) {
    const defined = new Map();
    const add = (symbol, owner, kind) => {
        if (!defined.has(symbol)) {
            defined.set(symbol, []);
        }
        defined.get(symbol).push({ owner, kind });
    };

    for (const mod of modules) {
        for (const file of listFiles(mod.path)) {
            const key = metadataKey(file);
            if (!key) {
                continue;
            }
            const parts = key.split('/');
            const base = parts[parts.length - 1];
            const stem = base.replace(/(\.[A-Za-z]+)?-meta\.xml$/, '').replace(/\.(cls|trigger|json|js|html|css)$/, '');
            switch (parts[0]) {
                case 'classes':
                    if (base.endsWith('.cls')) add(stem, mod.name, 'ApexClass');
                    break;
                case 'triggers':
                    if (base.endsWith('.trigger')) add(stem, mod.name, 'ApexTrigger');
                    break;
                case 'objects':
                    if (parts.length === 3 && /__(c|mdt|e)$/.test(parts[1])) add(parts[1], mod.name, 'CustomObject');
                    if (parts[2] === 'fields') {
                        add(`${parts[1]}.${stem}`, mod.name, 'CustomField');
                        add(stem, mod.name, 'CustomFieldName');
                    }
                    break;
                case 'lwc':
                case 'uiWidgets':
                case 'lightningTypes':
                    add(parts[1], mod.name, parts[0]);
                    break;
                case 'flows':
                case 'tabs':
                case 'applications':
                case 'permissionsets':
                case 'permissionsetgroups':
                case 'customPermissions':
                case 'flexipages':
                case 'quickActions':
                case 'omniIntegrationProcedures':
                    add(stem, mod.name, parts[0]);
                    break;
                default:
                    break;
            }
        }
    }

    for (const [pkg, symbols] of Object.entries(config.externalPackages || {})) {
        for (const list of Object.values(symbols)) {
            list.forEach((symbol) => add(symbol, pkg, 'External'));
        }
    }
    return defined;
}

/** Extracts candidate symbol references from a source or metadata file. */
function extractReferences(relativePath) {
    const text = readText(relativePath);
    const refs = new Set();
    const addToken = (token) => token && refs.add(token.trim());

    if (/\.(cls|trigger)$/.test(relativePath)) {
        for (const match of stripComments(text).matchAll(/[A-Za-z_][A-Za-z0-9_]*(?:\.[A-Za-z_][A-Za-z0-9_]*)?/g)) {
            const token = match[0];
            addToken(token);
            token.split('.').forEach(addToken);
        }
    } else if (relativePath.endsWith('.js')) {
        const source = stripComments(text);
        for (const m of source.matchAll(/@salesforce\/apex\/([A-Za-z0-9_]+)\./g)) addToken(m[1]);
        for (const m of source.matchAll(/@salesforce\/schema\/([A-Za-z0-9_]+(?:\.[A-Za-z0-9_]+)?)/g)) {
            addToken(m[1]);
            m[1].split('.').forEach(addToken);
        }
        for (const m of source.matchAll(/from\s+['"]c\/([A-Za-z0-9_]+)['"]/g)) addToken(m[1]);
    } else if (relativePath.endsWith('.html')) {
        for (const m of text.matchAll(/<c-([a-z0-9-]+)/g)) {
            addToken(m[1].replace(/-([a-z0-9])/g, (_, c) => c.toUpperCase()));
        }
    } else if (relativePath.endsWith('.xml')) {
        // OmniStudio property sets are JSON inside XML: Data Mapper bundles, Apex remote classes, IP methods.
        for (const m of text.matchAll(
            /&quot;(?:bundle|remoteClass|ipMethod)&quot;\s*:\s*&quot;([A-Za-z0-9_]+)&quot;/g
        )) {
            addToken(m[1]);
        }
        for (const m of text.matchAll(/>([^<>]+)</g)) {
            const value = m[1].trim();
            if (!value || value.length > 200) continue;
            addToken(value);
            value.split(/[.#/]/).forEach(addToken);
        }
    } else if (relativePath.endsWith('.agent')) {
        // Agent Script: action targets (apex://Class, flow://Flow) and output types (c__Type, @apexClassType/c__Class).
        for (const m of text.matchAll(/(?:apex|flow):\/\/([A-Za-z0-9_]+)/g)) addToken(m[1]);
        for (const m of text.matchAll(/c__([A-Za-z0-9_]+)/g)) addToken(m[1]);
    } else if (relativePath.endsWith('.json')) {
        // Custom Lightning Types reference types and Apex classes as c__Name, widgets as @widget/c/name.
        for (const m of text.matchAll(/c__([A-Za-z0-9_]+)/g)) addToken(m[1]);
        for (const m of text.matchAll(/@widget\/c\/([A-Za-z0-9_]+)/g)) addToken(m[1]);
        for (const m of text.matchAll(/"\$ref"\s*:\s*"\.\.\/([A-Za-z0-9_]+)\//g)) addToken(m[1]);
        // Experience Cloud pages: custom components ("definition" : "c:name") and flows ("flowName" : "Name").
        for (const m of text.matchAll(/"(?:definition|componentName)"\s*:\s*"c:([A-Za-z0-9_]+)"/g)) addToken(m[1]);
        for (const m of text.matchAll(/"flowName"\s*:\s*"([A-Za-z0-9_]+)"/g)) addToken(m[1]);
    }
    return refs;
}

module.exports = {
    ROOT,
    TYPE_DIRS,
    loadConfig,
    profileModules,
    allModules,
    loadProject,
    loadModules,
    loadForceIgnore,
    isIgnored,
    listFiles,
    metadataKey,
    readText,
    stripComments,
    buildSymbolIndex,
    extractReferences
};
