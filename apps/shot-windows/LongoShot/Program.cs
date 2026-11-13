using LongoKit.UI;

namespace LongoShot.App;

internal static class Program
{
    [STAThread]
    private static int Main(string[] args) =>
        new LongoShell(new AppInfo("shot", "Longo Shot", "shot.ico", "https://longokit.vercel.app/shot",
                                   "https://github.com/ngolong1405/LongoKit/releases"), new[] { new ShotModule() }).Run(args);
}
