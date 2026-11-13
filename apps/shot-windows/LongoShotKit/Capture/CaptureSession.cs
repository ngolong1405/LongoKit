using System.Windows;
using System.Windows.Media.Imaging;
using LongoShot.Engine;
using LongoShot.Model;

namespace LongoShot.Capture;

/// <summary>
/// One capture from start to end: the screens frozen the moment the shortcut is pressed, an area picked on them, drawn
/// on in place, then delivered: on the clipboard at once, the PNG written in the background. The capture windows are
/// kept between captures, so the next one comes up at once.
/// </summary>
internal sealed class CaptureSession
{
    private readonly ShotModel model;
    private readonly Action<BitmapSource> readText;
    private readonly Dictionary<string, CaptureWindow> kept = new();
    private readonly List<CaptureWindow> showing = new();
    private IReadOnlyList<Frozen> frozen = Array.Empty<Frozen>();
    private IReadOnlyList<WindowFrame> frames = Array.Empty<WindowFrame>();
    private bool text;

    public bool IsOpen => showing.Count > 0;

    /// <param name="readText">Opens the text read from a capture (⌥⇧3's window).</param>
    public CaptureSession(ShotModel model, Action<BitmapSource> readText)
    {
        this.model = model;
        this.readText = readText;
    }

    /// <summary>Makes the capture windows ahead, so the first capture doesn't wait for them.</summary>
    public void Prepare()
    {
        foreach (var screen in Screens.All()) Window(screen);
    }

    /// <summary>An area or a window (or, with <paramref name="forText"/>, the text in an area).</summary>
    public void PickArea(bool forText)
    {
        if (IsOpen) return;
        text = forText;
        frozen = Screens.Freeze();
        frames = forText ? Array.Empty<WindowFrame>() : Screens.Windows();
        ShowPicking();
    }

    /// <summary>The screen under the pointer, all of it.</summary>
    public void WholeScreen()
    {
        if (IsOpen) return;
        text = false;
        var screen = Engine.Screen.UnderPointer(Screens.All());
        if (screen == null) return;
        frozen = new[] { new Frozen(screen, Screens.Copy(screen.Bounds)) };
        frames = Array.Empty<WindowFrame>();
        if (!model.State.DrawAfterCapture)
        {
            Deliver(frozen[0].Picture, copy: false);
            return;
        }
        ShowPicking();
        showing[0].Edit(showing[0].Bounds);
    }

    private void ShowPicking()
    {
        var prompt = CaptureWindow.PickPrompt(text);
        var under = Engine.Screen.UnderPointer(frozen.Select(f => f.Screen).ToList());
        foreach (var each in frozen)
        {
            var window = Window(each.Screen);
            var bounds = each.Screen.Bounds;
            // The windows on this screen, in its points.
            var rects = frames.Select(f => new Rect((f.Bounds.X - bounds.X) / each.Screen.Scale, (f.Bounds.Y - bounds.Y) / each.Screen.Scale,
                                                    f.Bounds.Width / each.Screen.Scale, f.Bounds.Height / each.Screen.Scale))
                              .Select(r => Rect.Intersect(r, new Rect(0, 0, bounds.Width / each.Screen.Scale, bounds.Height / each.Screen.Scale)))
                              .Where(r => !r.IsEmpty && r.Width > 0)
                              .ToList();
            window.Pick(each, rects, prompt);
            showing.Add(window);
        }
        var focused = showing.FirstOrDefault(w => w.Screen == under) ?? showing.FirstOrDefault();
        focused?.Activate();
        focused?.Focus();
    }

    private CaptureWindow Window(Engine.Screen screen)
    {
        var key = $"{screen.Bounds.X},{screen.Bounds.Y},{screen.Bounds.Width},{screen.Bounds.Height}";
        if (kept.TryGetValue(key, out var window)) return window;
        window = new CaptureWindow(screen);
        window.Picked += OnPicked;
        window.Cancelled += Close;
        window.Back += () =>
        {
            foreach (var each in showing.ToList()) showing.Remove(each);
            ShowPicking();
        };
        window.Finished += OnFinished;
        kept[key] = window;
        return window;
    }

    private void OnPicked(CaptureWindow window, Rect area)
    {
        if (text)
        {
            var part = Cut(window, area);
            Close();
            readText(part);
            return;
        }
        if (!model.State.DrawAfterCapture)
        {
            var part = Cut(window, area);
            Close();
            Deliver(part, copy: false);
            return;
        }
        foreach (var other in showing.Where(w => w != window)) other.DimAll();
        window.Edit(area);
    }

    private void OnFinished(CaptureWindow window, bool? copy)
    {
        if (copy is not { } copying || window.Area is not { } area)
        {
            Close();
            return;
        }
        var pixels = Pixels(window, area);
        var picture = Mark.Render(Screens.Cut(FrozenOf(window).Picture, pixels), window.Drawing.Marks.ToList(), new Point(pixels.X, pixels.Y));
        Close();
        Deliver(picture, copying);
    }

    private Frozen FrozenOf(CaptureWindow window) => frozen.First(f => f.Screen.Bounds == window.Screen.Bounds);

    private static Int32Rect Pixels(CaptureWindow window, Rect area) => new(
        (int)Math.Round(area.X * window.Scale), (int)Math.Round(area.Y * window.Scale),
        (int)Math.Round(area.Width * window.Scale), (int)Math.Round(area.Height * window.Scale));

    private BitmapSource Cut(CaptureWindow window, Rect area) => Screens.Cut(FrozenOf(window).Picture, Pixels(window, area));

    public void Close()
    {
        foreach (var window in showing) window.Put();
        showing.Clear();
    }

    /// <summary>On the clipboard at once (if set, or asked with Ctrl+C); the PNG saved in the background; Recent; the preview.</summary>
    private void Deliver(BitmapSource picture, bool copy)
    {
        var state = model.State;
        if (state.CopyToClipboard || copy) Output.Copy(picture);
        var time = DateTime.Now;
        var dispatcher = Application.Current.Dispatcher;
        Task.Run(async () =>
        {
            var png = Output.Png(picture);
            var saved = state.SaveToFolder ? await Output.Save(png, state.Folder, time) : null;
            var file = saved ?? (state.KeepRecent ? await Output.Save(png, ShotModel.Cache, time) : null);
            await dispatcher.InvokeAsync(() =>
            {
                if (file != null) model.Remember(file, cached: saved == null);
                if (state.ShowPreview) Toast.Show(picture, saved, state.CopyToClipboard || copy);
            });
        });
    }
}
