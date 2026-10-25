#!/usr/bin/env node
'use strict';
/**
 * Validates the Agentforce / MCP / HXL UI contract (AGENTS.md section 5) across all modules:
 *   clt-invalid-json         every widget / Custom Lightning Type JSON file parses
 *   clt-schema               schema.json is an object schema; required keys exist; $ref targets resolve
 *   clt-renderer-widget      renderer widgetName (c__X) names an existing UiWidgetBundle, and the
 *                            renderer supplies every attribute the widget schema requires
 *   clt-renderer-binding     renderer {!$payload.a.b} bindings resolve against the type's result schema
 *   hxl-composition-binding  composition {!$attrs.x} bindings exist in the widget schema
 *   mcp-resource             McpServerDefinition ui://widget/lightningType/c__X resources name an existing type
 *   mcp-tool                 McpServerDefinition tools reference an existing Apex class
 *
 * Findings in config/devops/nexus-devops.json "allowlist" (keyed by repo-relative file) are reported but do not fail.
 */
const fs = require('node:fs');
const path = require('node:path');
const repo = require('./lib/repo');

const JSON_TYPES = new Set(['object', 'array', 'string', 'number', 'integer', 'boolean', 'null']);

function main() {
    const config = repo.loadConfig();
    const files = repo.loadModules().flatMap((m) => repo.listFiles(m.path));
    const findings = [];
    const report = (check, file, detail) => findings.push({ check, file, detail });

    const parsed = new Map();
    const loadJson = (file) => {
        if (!parsed.has(file)) {
            try {
                parsed.set(file, JSON.parse(repo.readText(file)));
            } catch (error) {
                report('clt-invalid-json', file, error.message);
                parsed.set(file, null);
            }
        }
        return parsed.get(file);
    };

    const contractFiles = files.filter((f) =>
        /\/(ui-widget-bundles|custom-lightning-types)\/[^/]+\/[^/]+\.json$/.test(f)
    );
    const bundleOf = (type) =>
        new Map(
            contractFiles
                .filter((f) => f.includes(`/${type}/`))
                .map((f) => [f.split(`/${type}/`)[1].split('/')[0], path.posix.dirname(f)])
        );
    const widgets = bundleOf('ui-widget-bundles');
    const types = bundleOf('custom-lightning-types');

    // Resolves a schema (following $ref) and returns it, or null when unresolvable.
    const resolveSchema = (schema, fromFile, seen = new Set()) => {
        if (!schema || !schema.$ref) return schema;
        const target = path.posix.normalize(path.posix.join(path.posix.dirname(fromFile), schema.$ref));
        if (seen.has(target) || !fs.existsSync(path.join(repo.ROOT, target))) return null;
        seen.add(target);
        return resolveSchema(loadJson(target), target, seen);
    };

    // 1. Schemas
    for (const file of contractFiles.filter((f) => f.endsWith('/schema.json'))) {
        const schema = loadJson(file);
        if (!schema) continue;
        if (schema.type !== 'object' || typeof schema.properties !== 'object') {
            report('clt-schema', file, 'schema.json must declare "type": "object" with "properties"');
            continue;
        }
        for (const key of schema.required || []) {
            if (!(key in schema.properties))
                report('clt-schema', file, `required property "${key}" is not defined in properties`);
        }
        for (const [name, prop] of Object.entries(schema.properties)) {
            if (prop.$ref) {
                if (!resolveSchema(prop, file))
                    report('clt-schema', file, `property "${name}" $ref "${prop.$ref}" does not resolve`);
            } else if (!JSON_TYPES.has(prop.type)) {
                report('clt-schema', file, `property "${name}" has invalid type "${prop.type}"`);
            }
        }
    }

    // 2. Renderers
    for (const [typeName, dir] of types) {
        const rendererFile = `${dir}/renderer.json`;
        if (!fs.existsSync(path.join(repo.ROOT, rendererFile))) continue;
        const renderer = loadJson(rendererFile);
        if (!renderer || renderer.type !== 'widget') continue;

        const widgetName = (renderer.widgetName || '').replace(/^c__/, '');
        const widgetSchemaFile = widgets.has(widgetName) ? `${widgets.get(widgetName)}/schema.json` : null;
        const widgetSchema = widgetSchemaFile ? loadJson(widgetSchemaFile) : null;
        if (!widgetSchema) {
            report(
                'clt-renderer-widget',
                rendererFile,
                `widgetName "${renderer.widgetName}" does not match a UiWidgetBundle with a schema.json`
            );
        } else {
            for (const key of widgetSchema.required || []) {
                if (!(key in (renderer.attributes || {}))) {
                    report(
                        'clt-renderer-widget',
                        rendererFile,
                        `widget "${widgetName}" requires attribute "${key}" which the renderer does not supply`
                    );
                }
            }
            for (const key of Object.keys(renderer.attributes || {})) {
                if (!(key in widgetSchema.properties))
                    report(
                        'clt-renderer-widget',
                        rendererFile,
                        `attribute "${key}" is not defined by widget "${widgetName}"`
                    );
            }
        }

        const resultSchema = loadJson(`${dir}/schema.json`);
        for (const [attr, binding] of Object.entries(renderer.attributes || {})) {
            const match = /^\{!\$payload\.([A-Za-z0-9_.]+)\}$/.exec(binding);
            if (!match) continue;
            let node = resultSchema;
            let nodeFile = `${dir}/schema.json`;
            for (const segment of match[1].split('.')) {
                const props = node?.properties;
                node = props ? props[segment] : undefined;
                if (node?.$ref) {
                    nodeFile = path.posix.normalize(path.posix.join(path.posix.dirname(nodeFile), node.$ref));
                    node = resolveSchema(node, `${dir}/schema.json`);
                }
            }
            if (!node) {
                report(
                    'clt-renderer-binding',
                    rendererFile,
                    `attribute "${attr}" binds ${binding}, which does not exist in ${typeName}/schema.json`
                );
            }
        }
    }

    // 3. Widget compositions
    for (const [widgetName, dir] of widgets) {
        const compositionFile = `${dir}/composition.json`;
        if (!fs.existsSync(path.join(repo.ROOT, compositionFile))) continue;
        const schema = loadJson(`${dir}/schema.json`);
        const raw = repo.readText(compositionFile);
        for (const m of raw.matchAll(/\{!\$attrs\.([A-Za-z0-9_]+)\}/g)) {
            if (!schema?.properties?.[m[1]]) {
                report(
                    'hxl-composition-binding',
                    compositionFile,
                    `binding {!$attrs.${m[1]}} is not a property of widget "${widgetName}"`
                );
            }
        }
    }

    // 4. MCP server definitions
    const apexClasses = new Set(files.filter((f) => f.endsWith('.cls')).map((f) => path.basename(f, '.cls')));
    for (const file of files.filter((f) => f.endsWith('.mcpServerDefinition-meta.xml'))) {
        const xml = repo.readText(file);
        for (const m of xml.matchAll(/<uri>ui:\/\/widget\/lightningType\/c__([A-Za-z0-9_]+)<\/uri>/g)) {
            if (!types.has(m[1]))
                report('mcp-resource', file, `resource references unknown Custom Lightning Type "${m[1]}"`);
        }
        for (const m of xml.matchAll(/<apexClass>([^<]+)<\/apexClass>/g)) {
            if (!apexClasses.has(m[1])) report('mcp-tool', file, `tool references unknown Apex class "${m[1]}"`);
        }
    }

    const allowed = (f) => (config.allowlist || []).find((a) => a.check === f.check && a.item === f.file);
    const blocking = findings.filter((f) => !allowed(f));
    console.log(
        `Validated ${contractFiles.length} contract files (${widgets.size} widgets, ${types.size} Custom Lightning Types).`
    );
    findings
        .filter(allowed)
        .forEach((f) => console.log(`ALLOW ${f.check}: ${f.file} - ${f.detail}\n      (${allowed(f).reason})`));
    blocking.forEach((f) => console.error(`ERROR ${f.check}: ${f.file} - ${f.detail}`));
    if (blocking.length) {
        console.error(`\n${blocking.length} contract violation(s).`);
        process.exit(1);
    }
    console.log('Agentforce / HXL contract schemas OK.');
}

main();
