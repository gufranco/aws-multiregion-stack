import { defineConfig } from 'vitest/config';

export default defineConfig({
  test: {
    globals: true,
    environment: 'node',
    passWithNoTests: true,
    include: ['**/*.test.ts'],
    coverage: {
      provider: 'v8',
      reporter: ['text', 'lcov', 'html'],
      include: ['**/src/**/*.ts'],
      exclude: ['**/node_modules/**', '**/dist/**', '**/*.test.ts'],
    },
    testTimeout: 30000,
    hookTimeout: 30000,
  },
});
