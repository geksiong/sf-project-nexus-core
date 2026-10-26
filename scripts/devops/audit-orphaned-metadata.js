#!/usr/bin/env node
'use strict';
/**
 * Orphaned metadata & missing permission audit (BP-DEVOPS-008 gate 2) for the active modules.
 *
 * Checks:
 *   missing-class-access        @AuraEnabled / @InvocableMethod / @RestResource classes granted by no permission set
 *   missing-field-permission    custom fields (that support FLS) granted by no permission set
 *   unassigned-custom-permission custom permissions granted by no permission set
 *   unreferenced-tab            tabs in no app and no permission set
 *   unreferenced-lwc            LWC bundles used by no page, component or action
 *   unreferenced-flow           screen flows launched by no action, page, flow or permission set
 *   unreferenced-apex           non-test Apex classes referenced by nothing and not a platform entry point
 *   unreferenced-widget         HXL UiWidgetBundles bound by no Custom Lightning Type renderer
 *   unreferenced-clt            Custom Lightning Types with no renderer referenced by no other type or MCP resource
 *   unreferenced-vip            OmniStudio Integration Procedures (VIPs, by Type_SubType) referenced by nothing
 *   unreferenced-datamapper     OmniStudio Data Mappers used by no Integration Procedure or FlexCard
 *   unreferenced-flexcard       OmniStudio FlexCards placed on no Lightning page or parent card
 *   facts-selector-exposure     @AuraEnabled / @InvocableMethod / @RestResource classes calling a *FactsSelector
 *                               directly (system-mode facts must stay inside services, AGENTS.md 2.1)
 *
 * Findings listed in config/devops/nexus-devops.json "allowlist" are reported but do not fail.
 * Usage: node scripts/devops/audit-orphaned-metadata.js
 */
const path = require('node:path');
const repo = require('./lib/repo');

const ENTRY_POINT_PATTERN =
    /@(AuraEnabled|InvocableMethod|RestResource|HttpGet|HttpPost)\b|\bglobal\s+|implements\s+[^{]*\b(Schedulable|Database\.Batchable|Queueable|StubProvider|Comparable|Callable)\b/i;
const FLS_EXEMPT_TYPES = new Set(['MasterDetail', 'Summary', 'AutoNumber']);

function main() {
    const config = repo.loadConfig();
    const modules = repo.allModules(config);
    const files = modules.flatMap((dir) => repo.listFiles(dir));
    const text = new Map(files.map((f) => [f, repo.readText(f)]));
    const byType = (dir, suffix) =>
        files.filter((f) => repo.metadataKey(f)?.startsWith(`${dir}/`) && f.endsWith(suffix));
    const stem = (file, suffix) => path.basename(file, suffix);

    // Grants come from permission sets and (for site guest users and external users) profiles.
    const permissionSets = [
        ...byType('permissionsets', '.permissionset-meta.xml'),
        ...byType('profiles', '.profile-meta.xml')
    ].map((f) => text.get(f));
    const permissionXml = permissionSets.join('\n');
    const granted = (element, value) => new RegExp(`<${element}>${escape(value)}</${element}>`).test(permissionXml);

    // Corpus of references per file, so a definition never counts as a reference to itself.
    const references = new Map(files.map((f) => [f, repo.extractReferences(f)]));
    const referencedOutside = (symbol, ownFiles) =>
        files.some(
            (f) => !ownFiles.some((own) => f === own || f.startsWith(`${own}/`)) && references.get(f).has(symbol)
        );

    const findings = [];
    const report = (check, item, detail) => findings.push({ check, item, detail });

    // --- Apex
    const apexClasses = byType('classes', '.cls');
    for (const file of apexClasses) {
        const name = stem(file, '.cls');
        const source = repo.stripComments(text.get(file));
        const isTest = /@IsTest/i.test(source);
        if (isTest) continue;
        // Entry points are annotated methods or REST classes; @AuraEnabled on DTO properties does not count.
        // String literals are blanked first so parentheses inside annotation text (descriptions) cannot end
        // the annotation's argument list early.
        const code = source.replace(/'(?:\\.|[^'\\])*'/g, "''");
        const isEntryPoint =
            /@(AuraEnabled|InvocableMethod)\b(\([^)]*\))?\s+(public|global)\s+static\b/i.test(code) ||
            /@RestResource\b/i.test(code);
        if (isEntryPoint && !granted('apexClass', name)) {
            report('missing-class-access', name, 'Apex entry point not granted in any permission set classAccesses');
        }
        const factsSelector = isEntryPoint && source.match(/\b[A-Za-z0-9_]*FactsSelector\b/);
        if (factsSelector) {
            report(
                'facts-selector-exposure',
                name,
                `Entry point uses ${factsSelector[0]} directly; system-mode facts may only be read by services`
            );
        }
        if (!ENTRY_POINT_PATTERN.test(source) && !referencedOutside(name, [file])) {
            report('unreferenced-apex', name, 'Not referenced by any Apex, trigger, LWC or metadata');
        }
    }

    // --- Custom fields
    for (const file of files.filter((f) => /\/objects\/[^/]+\/fields\/[^/]+\.field-meta\.xml$/.test(f))) {
        const object = file.split('/objects/')[1].split('/')[0];
        if (/__(mdt|e)$/.test(object)) continue;
        const xml = text.get(file);
        const type = (xml.match(/<type>([^<]+)<\/type>/) || [])[1];
        if (/<required>true<\/required>/.test(xml) || FLS_EXEMPT_TYPES.has(type)) continue;
        const field = `${object}.${stem(file, '.field-meta.xml')}`;
        if (!granted('field', field)) {
            report(
                'missing-field-permission',
                field,
                'Custom field not granted in any permission set fieldPermissions'
            );
        }
    }

    // --- Custom permissions
    for (const file of byType('customPermissions', '.customPermission-meta.xml')) {
        const name = stem(file, '.customPermission-meta.xml');
        if (
            !new RegExp(`<customPermissions>\\s*<enabled>true</enabled>\\s*<name>${escape(name)}</name>`).test(
                permissionXml
            )
        ) {
            report('unassigned-custom-permission', name, 'No permission set grants this custom permission');
        }
    }

    // --- Tabs
    for (const file of byType('tabs', '.tab-meta.xml')) {
        const name = stem(file, '.tab-meta.xml');
        if (!referencedOutside(name, [file]))
            report('unreferenced-tab', name, 'Tab is in no app and no permission set');
    }

    // --- LWC
    const lwcDirs = [
        ...new Set(files.filter((f) => /\/lwc\/[^/]+\//.test(f)).map((f) => f.replace(/(\/lwc\/[^/]+)\/.*$/, '$1')))
    ];
    for (const dir of lwcDirs) {
        const name = path.basename(dir);
        if (!referencedOutside(name, [dir]))
            report('unreferenced-lwc', name, 'Used by no Lightning page, component or action');
    }

    // --- Screen flows
    for (const file of byType('flows', '.flow-meta.xml')) {
        const xml = text.get(file);
        if (!/<processType>Flow<\/processType>/.test(xml) || /<triggerType>/.test(xml)) continue;
        const name = stem(file, '.flow-meta.xml');
        if (!referencedOutside(name, [file]))
            report('unreferenced-flow', name, 'Screen flow launched by no action, page, flow or permission set');
    }

    // --- HXL widgets, Custom Lightning Types, VIPs
    const bundleDirs = (type) => [
        ...new Set(
            files.filter((f) => f.includes(`/${type}/`)).map((f) => f.replace(new RegExp(`(/${type}/[^/]+)/.*$`), '$1'))
        )
    ];
    for (const dir of bundleDirs('uiWidgets')) {
        const name = path.basename(dir);
        if (!referencedOutside(name, [dir]))
            report('unreferenced-widget', name, 'No Custom Lightning Type renderer binds this widget');
    }
    // A type with a renderer is an entry point (picked as an Agentforce action's output rendering in Setup).
    for (const dir of bundleDirs('lightningTypes')) {
        const name = path.basename(dir);
        const hasRenderer = files.includes(`${dir}/renderer.json`);
        if (!hasRenderer && !referencedOutside(name, [dir]))
            report('unreferenced-clt', name, 'No renderer, and no MCP resource or other type references this type');
    }
    // OmniStudio components are referenced by name (Type_SubType for IPs), not by versioned unique name.
    const omniName = (file) => {
        const xml = text.get(file);
        // Last match: element-level <type>/<name> tags precede the component's own (alphabetical order).
        const tag = (t) => [...xml.matchAll(new RegExp(`<${t}>([^<]+)</${t}>`, 'g'))].pop()?.[1];
        return tag('type') && tag('subType') ? `${tag('type')}_${tag('subType')}` : tag('name');
    };
    const omniChecks = [
        [
            'omniIntegrationProcedures',
            'unreferenced-vip',
            'Integration Procedure called by no FlexCard, OmniScript or Apex'
        ],
        ['omniDataTransforms', 'unreferenced-datamapper', 'Data Mapper used by no Integration Procedure or FlexCard'],
        ['omniUiCard', 'unreferenced-flexcard', 'FlexCard placed on no Lightning page or parent card']
    ];
    for (const [dir, check, detail] of omniChecks) {
        for (const file of byType(dir, '-meta.xml')) {
            const name = omniName(file);
            if (!referencedOutside(name, [file])) report(check, name, detail);
        }
    }

    // --- Report
    const allowed = new Set((config.allowlist || []).map((a) => `${a.check}|${a.item}`));
    const blocking = findings.filter((f) => !allowed.has(`${f.check}|${f.item}`));
    const accepted = findings.filter((f) => allowed.has(`${f.check}|${f.item}`));

    console.log(`Audited ${files.length} files in: ${modules.join(', ')}`);
    for (const f of accepted) {
        const reason = config.allowlist.find((a) => a.check === f.check && a.item === f.item).reason;
        console.log(`ALLOW ${f.check}: ${f.item} - ${reason}`);
    }
    for (const f of blocking) console.error(`ERROR ${f.check}: ${f.item} - ${f.detail}`);
    if (blocking.length) {
        console.error(`\n${blocking.length} orphaned metadata / missing permission finding(s).`);
        process.exit(1);
    }
    console.log('No orphaned metadata or missing permissions.');
}

function escape(value) {
    return value.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

main();
