// Facts shown on the site, in one place so they stay true as the apps change.
export const repo = "https://github.com/ngolong1405/LongoKit";
export const mouseVersion = "0.2.9";
// Direct link to the .dmg of the current release, so the download starts right away.
// When releasing a new version, bump mouseVersion and upload LongoMouse-<version>.dmg to tag mouse-macos/v<version>.
export const mouseDownload = `${repo}/releases/download/mouse-macos/v${mouseVersion}/LongoMouse-${mouseVersion}.dmg`;
export const mouseReleaseNotes = `${repo}/releases/tag/mouse-macos/v${mouseVersion}`;
export const displayVersion = "0.1.3";
// Same for Longo Display: bump displayVersion and upload LongoDisplay-<version>.dmg to tag display-macos/v<version>.
export const displayDownload = `${repo}/releases/download/display-macos/v${displayVersion}/LongoDisplay-${displayVersion}.dmg`;
export const displayReleaseNotes = `${repo}/releases/tag/display-macos/v${displayVersion}`;
// Null shows "coming soon" and the build-from-source command instead of a download.
// When releasing, set keysVersion and upload LongoKeys-<version>.dmg to tag keys-macos/v<version>.
export const keysVersion: string | null = "0.1.2";
export const keysDownload = keysVersion ? `${repo}/releases/download/keys-macos/v${keysVersion}/LongoKeys-${keysVersion}.dmg` : null;
export const keysReleaseNotes = keysVersion ? `${repo}/releases/tag/keys-macos/v${keysVersion}` : null;
export const keysBuildFromSource = "git clone https://github.com/ngolong1405/LongoKit && cd LongoKit/apps/keys-macos && ./scripts/build-app.sh";
export const shotVersion = "0.2.1";
// Same for Longo Shot: bump shotVersion and upload LongoShot-<version>.dmg to tag shot-macos/v<version>.
export const shotDownload = `${repo}/releases/download/shot-macos/v${shotVersion}/LongoShot-${shotVersion}.dmg`;
export const shotReleaseNotes = `${repo}/releases/tag/shot-macos/v${shotVersion}`;
export const shotBuildFromSource = "git clone https://github.com/ngolong1405/LongoKit && cd LongoKit/apps/shot-macos && ./scripts/build-app.sh";
// Set to a Buy Me a Coffee / Ko-fi / payment link to show the "buy me a coffee" buttons.
export const coffeeURL: string | null = null;
export const licenseURL = `${repo}/blob/main/LICENSE.md`;
export const buildFromSource = "git clone https://github.com/ngolong1405/LongoKit && cd LongoKit/apps/mouse-macos && ./scripts/build-app.sh";
