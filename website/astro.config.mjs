import { defineConfig } from "astro/config";
import tailwindcss from "@tailwindcss/vite";

export default defineConfig({
  site: "https://longokit.vercel.app",
  vite: {
    plugins: [tailwindcss()],
    // Shared logos, fonts, and tokens live in ../brand, outside this project.
    server: { fs: { allow: [".."] } },
  },
});
