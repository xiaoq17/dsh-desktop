import { defineConfig } from "vitest/config";

/**
 * Vitest config — source-plane test execution (mirrors dsk-poc): tests import
 * plugin sources directly (never the built lib). Coverage runs per-file 100%
 * over the plugin source tree (see docs/testing.md).
 */
export default defineConfig({
  test: {
    include: ["plugins/*/tests/**/*.test.ts"],
    coverage: {
      provider: "v8",
      include: ["plugins/*/src/**/*.ts"],
      thresholds: {
        lines: 100,
        functions: 100,
        statements: 100,
        branches: 100,
        perFile: true,
      },
    },
  },
});
