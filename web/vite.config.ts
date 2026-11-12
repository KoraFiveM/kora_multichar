import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";
import kora_theme from "../../kora_theme/vite-plugin.mjs";

export default defineConfig({
  plugins: [kora_theme(), react()],
  base: "./",
  build: { outDir: "build", emptyOutDir: true },
  test: { include: ["src/**/*.test.{ts,tsx}"] },
});
