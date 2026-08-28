import { defineConfig } from "vitest/config"

// Separate from vite.config.js on purpose: vite-plugin-ruby wires up Rails
// asset manifest paths that have no business running under a test process.
export default defineConfig({
  test: {
    environment: "node",
    include: ["app/frontend/**/*.test.js"],
    setupFiles: ["./vitest.setup.js"],
  },
})
