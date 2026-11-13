using System.Windows.Media.Imaging;
using System.Windows.Threading;
using LongoKit.UI;
using LongoShot.Engine;

namespace LongoShot.Model;

/// <summary>A capture kept for Recent: its file (in the save folder, or Shot's cache when only copied) and when.</summary>
public sealed class Recent
{
    public string File { get; set; } = "";
    public DateTime Time { get; set; }
    public bool Cached { get; set; }
}

/// <summary>What's saved.</summary>
public sealed class ShotState
{
    public bool IsEnabled { get; set; } = true;
    public bool SaveToFolder { get; set; } = true;
    public string Folder { get; set; } = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), "Downloads");
    public bool CopyToClipboard { get; set; } = true;
    public bool DrawAfterCapture { get; set; } = true;
    public bool ShowPreview { get; set; } = true;
    public bool KeepRecent { get; set; } = true;
    /// <summary>"auto", or a Windows language tag ("vi", "ja").</summary>
    public string TextLanguage { get; set; } = "auto";
    public bool JoinLines { get; set; }
    public List<Recent> Recent { get; set; } = new();
}

/// <summary>Longo Shot's settings and Recent (the last 10 captures), as on the Mac.</summary>
public sealed class ShotModel
{
    public const string StoreName = "shot";
    public const int RecentCount = 10;

    private readonly ShotState state;
    private readonly bool live;
    private readonly DispatcherTimer saveTimer = new() { Interval = TimeSpan.FromSeconds(0.5) };

    public event Action? Changed;

    public ShotModel(bool live, ShotState? state = null)
    {
        this.live = live;
        this.state = state ?? Store.Load<ShotState>(StoreName);
        saveTimer.Tick += (_, _) =>
        {
            saveTimer.Stop();
            if (live) Store.Save(StoreName, this.state);
        };
    }

    public ShotState State => state;

    public void Change(Action<ShotState> change)
    {
        change(state);
        saveTimer.Stop();
        saveTimer.Start();
        Changed?.Invoke();
    }

    public IReadOnlyList<Recent> RecentCaptures => state.Recent.Where(r => !live || File.Exists(r.File)).ToList();

    /// <summary>Shot's own folder for copied-only captures kept for Recent.</summary>
    public static string Cache => Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "LongoKit", "Shot", "Recent");

    /// <summary>Adds a capture to Recent; one dropped from it that only Shot kept is deleted.</summary>
    public void Remember(string file, bool cached)
    {
        if (!state.KeepRecent) return;
        Change(s =>
        {
            s.Recent.Insert(0, new Recent { File = file, Time = DateTime.Now, Cached = cached });
            foreach (var old in s.Recent.Skip(RecentCount).Where(r => r.Cached))
            {
                try { File.Delete(old.File); } catch (IOException) { } catch (UnauthorizedAccessException) { }
            }
            if (s.Recent.Count > RecentCount) s.Recent.RemoveRange(RecentCount, s.Recent.Count - RecentCount);
        });
    }

    /// <summary>A small copy of a capture for Recent, decoded at the size shown.</summary>
    public static BitmapImage? Thumbnail(string file, int width = 160)
    {
        try
        {
            var image = new BitmapImage();
            image.BeginInit();
            image.UriSource = new Uri(file);
            image.DecodePixelWidth = width;
            image.CacheOption = BitmapCacheOption.OnLoad;
            image.EndInit();
            image.Freeze();
            return image;
        }
        catch (Exception)
        {
            return null;
        }
    }

    public void Flush()
    {
        if (!saveTimer.IsEnabled) return;
        saveTimer.Stop();
        if (live) Store.Save(StoreName, state);
    }
}
