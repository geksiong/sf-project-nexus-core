const globals = require('globals');
const lwcConfig = require('@salesforce/eslint-config-lwc');
const jestPlugin = require('eslint-plugin-jest');

module.exports = [
    {
        ignores: ['node_modules/**', 'coverage/**', '.sf/**', '.sfdx/**', '.localdevserver/**']
    },
    {
        files: ['modules/**/lwc/**/*.js'],
        ...lwcConfig.configs.recommended[0]
    },
    ...lwcConfig.configs.recommended.slice(1).map((config) => ({ files: ['modules/**/lwc/**/*.js'], ...config })),
    {
        files: ['modules/**/lwc/**/__tests__/**/*.js'],
        plugins: { jest: jestPlugin },
        languageOptions: { globals: { ...globals.node, ...globals.jest } },
        rules: { '@lwc/lwc/no-async-operation': 'off' }
    },
    {
        files: ['scripts/**/*.js', '*.config.js'],
        languageOptions: { ecmaVersion: 2022, sourceType: 'commonjs', globals: globals.node }
    }
];
