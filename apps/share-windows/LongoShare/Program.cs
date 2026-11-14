using LongoKit.UI;
using LongoShare.Windows;

namespace LongoShare.App;

internal static class Program
{
    [STAThread]
    private static int Main(string[] args) =>
        new LongoShell(new AppInfo("share", "Longo Share", "share.ico", "https://longokit.vercel.app/share",
                                   "https://github.com/ngolong1405/LongoKit/releases"), new[] { new ShareModule() }).Run(args);
}
