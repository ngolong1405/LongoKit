// Two languages: English at the root, Vietnamese under /vi.
export type Lang = "en" | "vi";

/** A site path ("/", "/mouse", "/#downloads") in the given language. */
export function localize(lang: Lang, path: string): string {
  if (lang === "en") return path;
  if (path === "/") return "/vi/";
  if (path.startsWith("/#")) return "/vi/" + path.slice(1);
  return "/vi" + path;
}

/** The same page in the other language. */
export function counterpart(pathname: string): { lang: Lang; href: string } {
  const isVi = pathname === "/vi" || pathname.startsWith("/vi/");
  if (isVi) return { lang: "en", href: pathname.replace(/^\/vi/, "") || "/" };
  return { lang: "vi", href: localize("vi", pathname === "" ? "/" : pathname) };
}

export function pick<T>(lang: Lang, strings: { en: T; vi: T }): T {
  return strings[lang];
}
