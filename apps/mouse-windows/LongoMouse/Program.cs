using LongoKit.UI;

namespace LongoMouse.App;

internal static class Program
{
    [STAThread]
    private static int Main(string[] args) =>
        new LongoShell(new AppInfo("mouse", "Longo Mouse", "mouse.ico", "https://longokit.vercel.app/mouse",
                                   "https://github.com/ngolong1405/LongoKit/releases"), new[] { new MouseModule() }).Run(args);
}
