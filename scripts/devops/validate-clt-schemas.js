#!/usr/bin/env node
'use strict';
/**
 * Validates the Agentforce / MCP / HXL UI contract (AGENTS.md section 5) across all modules:
 *   clt-invalid-json         every widget / Custom Lightning Type JSON file parses
 *   hxl-widget               uiWidgets/<name>/ has <name>.json and <name>.uiwidget-meta.xml (widgetType JSON); the
 *                            composition is a lightning__agentforceWidget rooted at tile/widget, uses only catalogued
 *                            tile/* components and action/openLink | action/sendMessage actions
 *   hxl-widget-schema        widget schema.json declares properties.attributes.properties, each with lightning:type
 *   hxl-composition-binding  {!$attrs.x} bindings exist in the widget schema; loop variables ($item) are in scope
 *   clt-schema               schema.json has a title and lightning:type; object properties are typed; c__Type and
 *                            @apexClassType/c__Class references resolve to a type or Apex class in the repo
 *   clt-renderer-widget      renderer componentOverrides.$ names an existing @widget/c/<name> and maps only
 *                            attributes the widget declares
 *   clt-renderer-binding     renderer {!$attrs.a.b} bindings resolve against the type (object properties, referenced
 *                            types, and @AuraEnabled fields of referenced Apex classes)
 *   mcp-type                 MCP types (lightning:tags mcp) are closed objects; wrappers (with outputValues) declare
 *                            actionName / isSuccess / outputValues; payloads have no renderer
 *   mcp-resource             McpServerDefinition ui://widget/lightningType/c__X resources name a wrapper type with
 *                            a renderer; every tool uiResource names a declared resource
 *   mcp-tool                 McpServerDefinition tools backed by Apex (API_CATALOG aa:apex-<Class>, operation <Class>)
 *                            name an @InvocableMethod class in the repo
 *   agent-action             Agent Script actions target existing invocable Apex (apex://Class) and their output
 *                            types (c__Type, @apexClassType/c__Class) exist
 *
 * Findings in config/devops/nexus-devops.json "allowlist" (keyed by repo-relative file) are reported but do not fail.
 */
const path = require('node:path');
const repo = require('./lib/repo');

// HXL beta component catalog (tile/widget is the composition root).
const COMPONENTS = new Set(
    [
        'widget',
        'accordion',
        'accordionItem',
        'avatar',
        'badge',
        'button',
        'callout',
        'code',
        'column',
        'container',
        'icon',
        'image',
        'link',
        'list',
        'listItem',
        'markdown',
        'progress',
        'row',
        'separator',
        'spacer',
        'spinner',
        'table',
        'text'
    ].map((c) => `tile/${c}`)
);
const ACTIONS = new Set(['action/openLink', 'action/sendMessage']);

function main() {
    const config = repo.loadConfig();
    const files = repo.loadModules().flatMap((m) => repo.listFiles(m.path));
    const fileSet = new Set(files);
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
    const bundles = (type) =>
        new Map(
            files
                .filter((f) => f.includes(`/${type}/`))
                .map((f) => [f.split(`/${type}/`)[1].split('/')[0], f.split(`/${type}/`)[0] + `/${type}/`])
                .map(([name, base]) => [name, base + name])
        );
    const widgets = bundles('uiWidgets');
    const types = bundles('lightningTypes');
    const apex = apexFields(files);

    // 1. Widgets
    const widgetAttributes = new Map();
    for (const [name, dir] of widgets) {
        const composition = `${dir}/${name}.json`;
        const meta = `${dir}/${name}.uiwidget-meta.xml`;
        if (!fileSet.has(meta) || !/<widgetType>JSON<\/widgetType>/.test(repo.readText(meta))) {
            report('hxl-widget', dir, `needs ${name}.uiwidget-meta.xml with <widgetType>JSON</widgetType>`);
        }
        const schemaFile = `${dir}/schema.json`;
        const schema = fileSet.has(schemaFile) ? loadJson(schemaFile) : null;
        const attributes = schema?.properties?.attributes?.properties;
        if (schema && typeof attributes !== 'object') {
            report('hxl-widget-schema', schemaFile, 'must declare properties.attributes.properties');
        }
        for (const [attr, def] of Object.entries(attributes || {})) {
            if (!def['lightning:type'])
                report('hxl-widget-schema', schemaFile, `attribute "${attr}" has no lightning:type`);
        }
        widgetAttributes.set(name, attributes || {});
        if (!fileSet.has(composition)) {
            report('hxl-widget', dir, `needs the composition ${name}.json`);
            continue;
        }
        const doc = loadJson(composition);
        if (!doc) continue;
        if (doc.type !== 'lightning__agentforceWidget') {
            report('hxl-widget', composition, 'type must be "lightning__agentforceWidget"');
        }
        const root = doc.contentBody?.widgetBody;
        if (root?.definition !== 'tile/widget') {
            report('hxl-widget', composition, 'contentBody.widgetBody.definition must be "tile/widget"');
            continue;
        }
        walkComposition(root, ['$attrs'], (node, scope) => {
            if (!COMPONENTS.has(node.definition)) {
                report('hxl-widget', composition, `"${node.definition}" is not in the HXL component catalog`);
            }
            for (const [event, actions] of Object.entries(node.attributes?.actions || {})) {
                for (const action of [].concat(actions)) {
                    if (!ACTIONS.has(action.definition))
                        report('hxl-widget', composition, `${event} action "${action.definition}" is not supported`);
                }
            }
            const own = { ...node, children: undefined };
            for (const m of JSON.stringify(own).matchAll(/\{!([^}]*)\}/g)) {
                for (const ref of m[1].matchAll(/\$([A-Za-z_][A-Za-z0-9_]*)(?:\.([A-Za-z_][A-Za-z0-9_]*))?/g)) {
                    const variable = `$${ref[1]}`;
                    if (variable === '$attrs') {
                        if (!ref[2] || !(attributes && ref[2] in attributes))
                            report(
                                'hxl-composition-binding',
                                composition,
                                `{!$attrs.${ref[2]}} is not an attribute of widget "${name}"`
                            );
                    } else if (!scope.includes(variable)) {
                        report('hxl-composition-binding', composition, `${variable} is used outside its forEach`);
                    }
                }
            }
        });
    }

    // 2. Custom Lightning Types
    const schemaOf = (typeName) => (types.has(typeName) ? loadJson(`${types.get(typeName)}/schema.json`) : null);
    for (const [name, dir] of types) {
        const schemaFile = `${dir}/schema.json`;
        if (!fileSet.has(schemaFile)) {
            report('clt-schema', dir, 'Custom Lightning Type needs schema.json');
            continue;
        }
        const schema = loadJson(schemaFile);
        if (!schema) continue;
        if (!schema.title || !schema['lightning:type']) {
            report('clt-schema', schemaFile, 'schema.json needs "title" and "lightning:type"');
        }
        const checkTypeRef = (ref, where) => {
            const apexRef = /^@apexClassType\/c__([A-Za-z0-9_]+)$/.exec(ref || '');
            const typeRef = /^c__([A-Za-z0-9_]+)$/.exec(ref || '');
            if (apexRef && !apex.has(apexRef[1])) {
                report('clt-schema', schemaFile, `${where} references Apex class "${apexRef[1]}", not in the repo`);
            } else if (typeRef && !types.has(typeRef[1])) {
                report('clt-schema', schemaFile, `${where} references unknown type "${typeRef[1]}"`);
            } else if (typeRef && typeRef[1] === name) {
                report('clt-schema', schemaFile, `${where} references the type itself`);
            }
        };
        checkTypeRef(schema['lightning:type'], 'lightning:type');
        for (const [prop, def] of Object.entries(schema.properties || {})) {
            if (!def['lightning:type']) report('clt-schema', schemaFile, `property "${prop}" has no lightning:type`);
            checkTypeRef(def['lightning:type'], `property "${prop}"`);
        }

        const isMcp = (schema['lightning:tags'] || []).includes('mcp');
        const rendererFile = `${dir}/renderer.json`;
        const hasRenderer = fileSet.has(rendererFile);
        if (isMcp) {
            if (schema['lightning:type'] !== 'lightning__objectType' || schema.unevaluatedProperties !== false) {
                report(
                    'mcp-type',
                    schemaFile,
                    'MCP types are lightning__objectType with "unevaluatedProperties": false'
                );
            }
            const props = schema.properties || {};
            if ('outputValues' in props) {
                for (const key of ['actionName', 'isSuccess'])
                    if (!(key in props)) report('mcp-type', schemaFile, `MCP wrapper needs "${key}"`);
            } else if (hasRenderer) {
                report('mcp-type', rendererFile, 'only the MCP wrapper type (with outputValues) has a renderer');
            }
        }
        if (!hasRenderer) continue;

        const renderer = loadJson(rendererFile);
        const override = renderer?.renderer?.componentOverrides?.$;
        const widget = /^@widget\/c\/([A-Za-z0-9_]+)$/.exec(override?.definition || '');
        if (!widget || !widgets.has(widget[1])) {
            report(
                'clt-renderer-widget',
                rendererFile,
                `componentOverrides.$ must name a repo widget (@widget/c/<name>)`
            );
            continue;
        }
        const declared = widgetAttributes.get(widget[1]);
        for (const [attr, binding] of Object.entries(override.attributes || {})) {
            if (!(attr in declared)) {
                report(
                    'clt-renderer-widget',
                    rendererFile,
                    `attribute "${attr}" is not declared by widget "${widget[1]}"`
                );
            }
            const m = /^\{!\$attrs\.([A-Za-z0-9_.]+)\}$/.exec(binding);
            if (m && !resolvePath(schema, m[1].split('.'), schemaOf, apex)) {
                report('clt-renderer-binding', rendererFile, `"${attr}" binds ${binding}, which type "${name}" lacks`);
            }
        }
    }

    // 3. MCP server definitions
    for (const file of files.filter((f) => f.endsWith('.mcpServerDefinition-meta.xml'))) {
        const xml = repo.readText(file);
        const resources = new Set([...xml.matchAll(/<resourceName>([^<]+)<\/resourceName>/g)].map((m) => m[1]));
        for (const m of xml.matchAll(/<resourceUri>ui:\/\/widget\/lightningType\/c__([A-Za-z0-9_]+)<\/resourceUri>/g)) {
            if (
                !types.has(m[1]) ||
                !fileSet.has(`${types.get(m[1])}/renderer.json`) ||
                !schemaOf(m[1])?.properties?.outputValues
            )
                report('mcp-resource', file, `resource type "${m[1]}" is not an MCP wrapper type with a renderer`);
        }
        for (const m of xml.matchAll(/<uiResource>([^<]+)<\/uiResource>/g)) {
            if (!resources.has(m[1])) report('mcp-resource', file, `tool uiResource "${m[1]}" names no resource`);
        }
    }

    // 4. Apex-backed MCP tools and Agent Script actions
    const invocable = new Set(
        files
            .filter((f) => f.endsWith('.cls') && /@InvocableMethod\b/.test(repo.readText(f)))
            .map((f) => path.basename(f, '.cls'))
    );
    for (const file of files.filter((f) => f.endsWith('.mcpServerDefinition-meta.xml'))) {
        for (const m of repo.readText(file).matchAll(/<apiDefinition>([\s\S]*?)<\/apiDefinition>/g)) {
            const identifier = /<apiIdentifier>aa:apex-([^<]+)<\/apiIdentifier>/.exec(m[1])?.[1];
            const operation = /<operation>([^<]+)<\/operation>/.exec(m[1])?.[1];
            if (identifier && (!invocable.has(identifier) || operation !== identifier)) {
                report(
                    'mcp-tool',
                    file,
                    `tool aa:apex-${identifier} must name an invocable Apex class (operation = class)`
                );
            }
        }
    }
    for (const file of files.filter((f) => f.endsWith('.agent'))) {
        const script = repo.readText(file);
        for (const m of script.matchAll(/target:\s*"apex:\/\/([A-Za-z0-9_]+)"/g)) {
            if (!invocable.has(m[1])) report('agent-action', file, `apex://${m[1]} is not an invocable Apex class`);
        }
        for (const m of script.matchAll(/complex_data_type_name:\s*"([^"]+)"/g)) {
            const typeRef = /^c__([A-Za-z0-9_]+)$/.exec(m[1]);
            const apexRef = /^@apexClassType\/c__([A-Za-z0-9_]+)$/.exec(m[1]);
            if ((typeRef && !types.has(typeRef[1])) || (apexRef && !apex.has(apexRef[1]))) {
                report('agent-action', file, `output type ${m[1]} does not exist in the repo`);
            }
        }
    }

    const allowed = (f) => (config.allowlist || []).find((a) => a.check === f.check && a.item === f.file);
    const blocking = findings.filter((f) => !allowed(f));
    console.log(`Validated ${widgets.size} HXL widgets and ${types.size} Custom Lightning Types.`);
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

/** Visits every node with the loop variables in scope (forItem defaults to $Item, forIndex optional). */
function walkComposition(node, scope, visit) {
    let inner = scope;
    if (node.meta?.forEach) {
        inner = [...scope, node.meta.forItem || '$Item'];
        if (node.meta.forIndex) inner.push(node.meta.forIndex);
    }
    visit(node, inner);
    for (const child of node.children || []) walkComposition(child, inner, visit);
}

/**
 * Resolves a binding path against a type: object properties, referenced types (c__Name) and @AuraEnabled fields of
 * referenced Apex classes (@apexClassType/c__Class, following List<T> element types).
 */
function resolvePath(schema, segments, schemaOf, apex) {
    let current = { kind: 'schema', value: schema };
    for (const segment of segments) {
        current = step(current, segment, schemaOf, apex);
        if (!current) return false;
    }
    return true;
}

function step(current, segment, schemaOf, apex) {
    if (current.kind === 'apex') {
        const fieldType = apex.get(current.value)?.get(segment);
        return fieldType ? typeNode(fieldType, apex) : null;
    }
    if (current.kind === 'leaf') return null;
    const schema = current.value;
    const ref = schema['lightning:type'];
    if (/^@apexClassType\/c__/.test(ref || '') && !schema.properties) {
        return step({ kind: 'apex', value: ref.split('c__')[1] }, segment, schemaOf, apex);
    }
    const prop = schema.properties?.[segment];
    if (!prop) return null;
    const propType = prop['lightning:type'] || '';
    if (/^@apexClassType\/c__/.test(propType)) return { kind: 'apex', value: propType.split('c__')[1] };
    if (/^c__/.test(propType)) {
        const target = schemaOf(propType.slice(3));
        return target ? { kind: 'schema', value: target } : null;
    }
    return prop.properties ? { kind: 'schema', value: prop } : { kind: 'leaf' };
}

function typeNode(apexType, apex) {
    const element = /^List<\s*([A-Za-z0-9_]+)\s*>$/i.exec(apexType)?.[1] || apexType;
    return apex.has(element) && apexType === element ? { kind: 'apex', value: element } : { kind: 'leaf' };
}

/** Top-level Apex classes in the repo mapped to their @AuraEnabled fields (name to declared type). */
function apexFields(files) {
    const classes = new Map();
    for (const file of files.filter((f) => f.endsWith('.cls'))) {
        const source = repo.stripComments(repo.readText(file));
        const fields = new Map();
        for (const m of source.matchAll(
            /@AuraEnabled\b[^;{]*?\b(?:global|public)\s+((?:List<\s*[A-Za-z0-9_]+\s*>)|[A-Za-z0-9_]+)\s+([A-Za-z0-9_]+)\s*;/g
        )) {
            fields.set(m[2], m[1]);
        }
        classes.set(path.basename(file, '.cls'), fields);
    }
    return classes;
}

main();
