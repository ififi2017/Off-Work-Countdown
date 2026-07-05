import { defineConfig } from "vitest/config";
import { fileURLToPath } from "node:url";

// Resolve the "@/..." path alias (mirrors tsconfig paths) for tests.
const root = fileURLToPath(new URL(".", import.meta.url)).replace(/\/$/, "");

export default defineConfig({
  resolve: {
    alias: {
      "@": root,
    },
  },
});
