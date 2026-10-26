const { jestConfig } = require('@salesforce/sfdx-lwc-jest/config');

module.exports = {
    ...jestConfig,
    modulePathIgnorePatterns: ['<rootDir>/.localdevserver'],
    // UI bundles (React) run their own Vitest suites: npm run test:ui-bundles
    testPathIgnorePatterns: [
        ...(jestConfig.testPathIgnorePatterns || ['/node_modules/']),
        '<rootDir>/modules/.*/uiBundles/'
    ]
};
