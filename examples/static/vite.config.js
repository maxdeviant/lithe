import { defineConfig } from "vite";
import leanscript from "@leanscript/vite-plugin";

export default defineConfig({
  plugins: [leanscript()],
  appType: "mpa",
  build: {
    // The generator finds the name of the client's script in the manifest.
    manifest: true,
    rolldownOptions: { input: "Client.lean" },
  },
});
