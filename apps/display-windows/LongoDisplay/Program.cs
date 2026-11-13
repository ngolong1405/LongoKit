using LongoKit.UI;

namespace LongoDisplay.App;

internal static class Program
{
    [STAThread]
    private static int Main(string[] args) =>
        new LongoShell(new AppInfo("display", "Longo Display", "display.ico", "https://longokit.vercel.app/display",
                                   "https://github.com/ngolong1405/LongoKit/releases"), new[] { new DisplayModule() }).Run(args);
}
