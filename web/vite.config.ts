import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";
import qbtheme from "../../qbtheme/vite-plugin.mjs";

export default defineConfig({
  plugins: [qbtheme(), react()],
  base: "./",
  build: { outDir: "build", emptyOutDir: true },
  test: { include: ["src/**/*.test.{ts,tsx}"] },
});
