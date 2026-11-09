// Facts shown on the site, in one place so they stay true as the apps change.
export const repo = "https://github.com/ngolong1405/LongoKit";
export const mouseVersion = "0.2.3";
// Direct link to the .dmg of the current release, so the download starts right away.
// When releasing a new version, bump mouseVersion and upload LongoMouse-<version>.dmg to tag mouse-macos/v<version>.
export const mouseDownload = `${repo}/releases/download/mouse-macos/v${mouseVersion}/LongoMouse-${mouseVersion}.dmg`;
export const mouseReleaseNotes = `${repo}/releases/tag/mouse-macos/v${mouseVersion}`;
export const displayVersion = "0.1.0";
// Same for Longo Display: bump displayVersion and upload LongoDisplay-<version>.dmg to tag display-macos/v<version>.
export const displayDownload = `${repo}/releases/download/display-macos/v${displayVersion}/LongoDisplay-${displayVersion}.dmg`;
export const displayReleaseNotes = `${repo}/releases/tag/display-macos/v${displayVersion}`;
// Set to a Buy Me a Coffee / Ko-fi / payment link to show the "buy me a coffee" buttons.
export const coffeeURL: string | null = null;
export const licenseURL = `${repo}/blob/main/LICENSE.md`;
export const buildFromSource = "git clone https://github.com/ngolong1405/LongoKit && cd LongoKit/apps/mouse-macos && ./scripts/build-app.sh";
