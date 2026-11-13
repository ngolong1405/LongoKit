using System.Windows;
using System.Windows.Interop;
using System.Windows.Media;

using LongoDisplay.Model;

namespace LongoDisplay.Engine;

/// <summary>
/// Dimming in software: a black layer over a screen, as dark as asked. The pointer goes through it, it's never active,
/// and it's left out of screenshots and screen sharing.
/// </summary>
internal sealed class Dimmer
{
    private readonly Dictionary<string, Window> layers = new();

    public void Set(Display display, double amount)
    {
        if (amount <= 0.001)
        {
            if (layers.Remove(display.Key, out var gone)) gone.Close();
            return;
        }
        if (!layers.TryGetValue(display.Key, out var layer))
        {
            layer = new Window
            {
                WindowStyle = WindowStyle.None,
                AllowsTransparency = true,
                Background = Brushes.Black,
                ShowInTaskbar = false,
                ShowActivated = false,
                Topmost = true,
                IsHitTestVisible = false,
                ResizeMode = ResizeMode.NoResize,
            };
            var (left, top, width, height) = (display.Left, display.Top, display.Width, display.Height);
            layer.SourceInitialized += (_, _) =>
            {
                var handle = new WindowInteropHelper(layer).Handle;
                var style = Native.GetWindowLong(handle, Native.ExStyle);
                Native.SetWindowLong(handle, Native.ExStyle, style | Native.Transparent | Native.ToolWindow | Native.Layered | Native.NoActivate);
                Native.SetWindowDisplayAffinity(handle, Native.ExcludeFromCapture);
                // In pixels: the window's own size in WPF units would depend on the screen's scale.
                Native.SetWindowPos(handle, Native.Topmost, left, top, width, height, Native.NoActivateFlag | Native.ShowWindow);
            };
            layers[display.Key] = layer;
            layer.Opacity = amount;
            layer.Show();
            return;
        }
        layer.Opacity = amount;
    }

    public void Clear()
    {
        foreach (var layer in layers.Values) layer.Close();
        layers.Clear();
    }
}
