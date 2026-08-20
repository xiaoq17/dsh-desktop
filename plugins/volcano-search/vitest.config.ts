import { defineConfig } from "vitest/config";

/**
 * Vitest config — source-plane test execution (mirrors dsk-poc): tests import
 * the plugin's `src/*.ts` directly, never the built `lib/`.
 */
export default defineConfig({
  test: {
    include: ["tests/**/*.test.ts"],
  },
});
