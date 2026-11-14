using System.Runtime.InteropServices;

namespace LongoKit.UI;

/// <summary>
/// Where an app keeps what it saves: its own folder in Downloads ("Longo Shot", "Longo Share"), made at launch, as
/// Telegram does. The person can pick another one; that one is kept.
/// </summary>
public static class AppFolder
{
    private static readonly Guid DownloadsId = new("374DE290-123F-4565-9164-39C4925E467B");

    [DllImport("shell32.dll")]
    private static extern int SHGetKnownFolderPath([MarshalAs(UnmanagedType.LPStruct)] Guid id, uint flags, IntPtr token, out IntPtr path);

    /// <summary>The Downloads folder, wherever the person moved it.</summary>
    public static string Downloads
    {
        get
        {
            if (OperatingSystem.IsWindows() && SHGetKnownFolderPath(DownloadsId, 0, IntPtr.Zero, out var pointer) == 0)
            {
                var path = Marshal.PtrToStringUni(pointer);
                Marshal.FreeCoTaskMem(pointer);
                if (!string.IsNullOrEmpty(path)) return path;
            }
            return Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), "Downloads");
        }
    }

    /// <summary>The app's own folder: Downloads\<paramref name="name"/>.</summary>
    public static string Standard(string name) => Path.Combine(Downloads, name);

    /// <summary>
    /// The folder to use: the one the person picked, or the app's own. Downloads itself (the old default) moves to the
    /// app's own folder. The folder is made if it isn't there.
    /// </summary>
    public static string Resolve(string? saved, string name)
    {
        var folder = Standard(name);
        if (!string.IsNullOrWhiteSpace(saved) && !Same(saved, Downloads) &&
            !Same(saved, Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), "Downloads")))
            folder = saved;
        try
        {
            Directory.CreateDirectory(folder);
        }
        catch (Exception)
        {
            // A drive that's gone: saving says so when it happens.
        }
        return folder;
    }

    private static bool Same(string a, string b) =>
        string.Equals(Path.GetFullPath(a).TrimEnd('\\', '/'), Path.GetFullPath(b).TrimEnd('\\', '/'), StringComparison.OrdinalIgnoreCase);
}
