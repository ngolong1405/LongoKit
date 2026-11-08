import { defineConfig } from "astro/config";

export default defineConfig({
  site: "https://longokit.com",
  // Shared logos, fonts, and tokens live in ../brand, outside this project.
  vite: { server: { fs: { allow: [".."] } } },
});
