# LongoKit website

The landing page, built with [Astro](https://astro.build). The current page is a placeholder until the
real design is ready.

```sh
npm install
npm run dev       # http://localhost:4321
npm run build     # static site in dist/
```

Colors, fonts, and logos come from [`../brand`](../brand) (`tokens.css` is imported in
`src/styles/global.css`), so the site always matches the apps.

Deploy: point Vercel, Netlify, or Cloudflare Pages at this folder (`website/`), with build command
`npm run build` and output directory `dist`.
