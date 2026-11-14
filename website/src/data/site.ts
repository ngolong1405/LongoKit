// Facts shown on the site, in one place so they stay true as the apps change.
export const repo = "https://github.com/ngolong1405/LongoKit";
export const mouseVersion = "0.2.12";
// Direct link to the .dmg of the current release, so the download starts right away.
// When releasing a new version, bump mouseVersion and upload LongoMouse-<version>.dmg to tag mouse-macos/v<version>.
export const mouseDownload = `${repo}/releases/download/mouse-macos/v${mouseVersion}/LongoMouse-${mouseVersion}.dmg`;
export const mouseReleaseNotes = `${repo}/releases/tag/mouse-macos/v${mouseVersion}`;
export const displayVersion = "0.1.7";
// Same for Longo Display: bump displayVersion and upload LongoDisplay-<version>.dmg to tag display-macos/v<version>.
export const displayDownload = `${repo}/releases/download/display-macos/v${displayVersion}/LongoDisplay-${displayVersion}.dmg`;
export const displayReleaseNotes = `${repo}/releases/tag/display-macos/v${displayVersion}`;
// Null shows "coming soon" and the build-from-source command instead of a download.
// When releasing, set keysVersion and upload LongoKeys-<version>.dmg to tag keys-macos/v<version>.
export const keysVersion: string | null = "0.1.5";
export const keysDownload = keysVersion ? `${repo}/releases/download/keys-macos/v${keysVersion}/LongoKeys-${keysVersion}.dmg` : null;
export const keysReleaseNotes = keysVersion ? `${repo}/releases/tag/keys-macos/v${keysVersion}` : null;
export const keysBuildFromSource = "git clone https://github.com/ngolong1405/LongoKit && cd LongoKit/apps/keys-macos && ./scripts/build-app.sh";
export const shotVersion = "0.2.9";
// Same for Longo Shot: bump shotVersion and upload LongoShot-<version>.dmg to tag shot-macos/v<version>.
export const shotDownload = `${repo}/releases/download/shot-macos/v${shotVersion}/LongoShot-${shotVersion}.dmg`;
export const shotReleaseNotes = `${repo}/releases/tag/shot-macos/v${shotVersion}`;
export const shotBuildFromSource = "git clone https://github.com/ngolong1405/LongoKit && cd LongoKit/apps/shot-macos && ./scripts/build-app.sh";
export const shareVersion = "0.1.2";
// Longo Share: bump shareVersion and upload LongoShare-<version>.dmg to tag share-macos/v<version>.
export const shareDownload = `${repo}/releases/download/share-macos/v${shareVersion}/LongoShare-${shareVersion}.dmg`;
export const shareReleaseNotes = `${repo}/releases/tag/share-macos/v${shareVersion}`;
export const flowVersion = "0.1.0";
// Longo Flow: bump flowVersion and upload LongoFlow-<version>.dmg to tag flow-macos/v<version>.
export const flowDownload = `${repo}/releases/download/flow-macos/v${flowVersion}/LongoFlow-${flowVersion}.dmg`;
export const flowReleaseNotes = `${repo}/releases/tag/flow-macos/v${flowVersion}`;
export const kitVersion = "0.1.11";
// LongoKit, the five apps as modules of one: bump kitVersion and upload LongoKit-<version>.dmg to tag kit-macos/v<version>.
export const kitDownload = `${repo}/releases/download/kit-macos/v${kitVersion}/LongoKit-${kitVersion}.dmg`;
export const kitReleaseNotes = `${repo}/releases/tag/kit-macos/v${kitVersion}`;
export const kitBuildFromSource = "git clone https://github.com/ngolong1405/LongoKit && cd LongoKit/apps/kit-macos && ./scripts/build-app.sh";
// Set to a Buy Me a Coffee / Ko-fi / payment link to show the "buy me a coffee" buttons.
export const coffeeURL: string | null = null;
export const licenseURL = `${repo}/blob/main/LICENSE.md`;
export const buildFromSource = "git clone https://github.com/ngolong1405/LongoKit && cd LongoKit/apps/mouse-macos && ./scripts/build-app.sh";
// The Windows apps (beta): one .exe per app and processor, at tag <app>-windows/v<windowsVersion>.
export const windowsVersion = "0.1.2";
const windowsApp = (app: string, name: string, version = windowsVersion) => ({
  version,
  x64: `${repo}/releases/download/${app}-windows/v${version}/${name}-${version}-x64.exe`,
  arm64: `${repo}/releases/download/${app}-windows/v${version}/${name}-${version}-arm64.exe`,
  notes: `${repo}/releases/tag/${app}-windows/v${version}`,
});
export const mouseWindows = windowsApp("mouse", "LongoMouse");
export const displayWindows = windowsApp("display", "LongoDisplay");
export const shotWindows = windowsApp("shot", "LongoShot", "0.1.3");
export const kitWindows = windowsApp("kit", "LongoKit", "0.1.3");
// Longo Share has its own Windows version.
export const shareWindowsVersion = "0.1.1";
export const shareWindows = windowsApp("share", "LongoShare", shareWindowsVersion);
