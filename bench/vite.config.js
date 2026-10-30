import { defineConfig } from "vite";
import leanscript from "@leanscript/vite-plugin";

export default defineConfig({
  plugins: [leanscript()],
  // Profiles are only readable with the original names.
  build: { minify: false },
});
