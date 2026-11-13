using LongoDisplay;
using LongoMouse;
using LongoShot;
using LongoKit.UI;

namespace LongoKit.App;

internal static class Program
{
    [STAThread]
    private static int Main(string[] args) =>
        new LongoShell(new AppInfo("kit", "LongoKit", "kit.ico", "https://longokit.vercel.app/kit",
                                   "https://github.com/ngolong1405/LongoKit/releases", Suite: true),
                       new ILongoModule[] { new MouseModule(), new DisplayModule(), new ShotModule() }).Run(args);
}
