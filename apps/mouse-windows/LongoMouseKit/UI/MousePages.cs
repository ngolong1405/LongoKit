using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Input;
using LongoMouse.Model;
using LongoKit.UI;
using static LongoKit.UI.Localizer;

namespace LongoMouse.UI;

/// <summary>Longo Mouse's pages and menu, laid out as in the Mac app.</summary>
internal static class MousePages
{
    private static LiveView Live(MouseModule module, Func<FrameworkElement> build) =>
        new(build, refresh => module.Changed += refresh, refresh => module.Changed -= refresh);

    // MARK: - General

    public static FrameworkElement General(MouseModule module) => Live(module, () =>
    {
        var model = module.Model;
        var power = Ui.Card(Ui.Setting(model.IsEnabled ? L("{0} is on", module.Title) : L("{0} is off", module.Title),
            model.IsEnabled ? L("Buttons and scrolling are working.") : L("Off: the mouse works as Windows has it."),
            Ui.Switch(model.IsEnabled, on => model.IsEnabled = on), "\uE7E8"));
        var guard = Ui.Column(14, Ui.Setting(L("Double-Click Fix"), L("For a worn mouse that clicks twice: a second click this soon after the first is ignored."),
                                             Ui.Switch(model.ClickGuard, on => model.ClickGuard = on), "\uE8B0"));
        if (model.ClickGuard)
        {
            var label = Ui.Text($"{model.ClickGuardMs} ms", 11.5, FontWeights.SemiBold, "TextSecondary", "MonoFont");
            var slider = Ui.Level(model.ClickGuardMs, value =>
            {
                var rounded = (int)Math.Round(value / 5) * 5;
                label.Text = $"{rounded} ms";
                model.ClickGuardMs = rounded;
            }, 20, 150);
            slider.Width = 220;
            guard.Children.Add(Ui.Hairline());
            guard.Children.Add(Ui.Setting(L("Ignore a second click within"), L("Left and right buttons."), Ui.Row(10, slider, label)));
        }
        var follow = Ui.Card(Ui.Setting(L("Switch settings with the mouse in use"),
            L("A mouse with its own buttons or scrolling gets them as soon as it moves."), Ui.Switch(model.AutoSwitch, on => model.AutoSwitch = on), "\uE8AB"));
        return Ui.Column(16, Ui.Section(L("Status")), power, Ui.Section(L("Mouse")), Ui.Card(guard), follow);
    });

    // MARK: - Profiles

    /// <summary>All mice, or one of them: which settings the page shows. A mouse can have its own.</summary>
    private static FrameworkElement Profiles(MouseModule module, bool buttons)
    {
        var model = module.Model;
        var choices = new List<(string Key, string Title)> { ("", L("All mice")) };
        choices.AddRange(model.Connected.Select(m => (m.Key, model.NameOf(m.Key) + (m.Key == model.InUse ? " •" : ""))));
        var picker = Ui.Segmented(choices, module.Selected ?? "", key => module.Select(key == "" ? null : key));
        var column = Ui.Column(12, Ui.Spread(Ui.Text(L("Settings for"), 12, FontWeights.Medium, "TextSecondary"), picker));
        if (module.Selected is { } selected)
        {
            var own = buttons ? model.HasOwnButtons(selected) : model.HasOwnScroll(selected);
            column.Children.Add(Ui.Card(Ui.Setting(buttons ? L("Own buttons for this mouse") : L("Own scrolling for this mouse"),
                own ? L("This mouse keeps its own; the others share theirs.") : L("Off: this mouse uses the settings of all mice."),
                Ui.Switch(own, on =>
                {
                    if (buttons) model.SetOwnButtons(selected, on);
                    else model.SetOwnScroll(selected, on);
                }), "\uE962")));
        }
        return column;
    }

    /// <summary>Whether the page's controls edit something: all mice always; a mouse, once it has its own.</summary>
    private static bool Editable(MouseModule module, bool buttons) => module.Selected is not { } key ||
        (buttons ? module.Model.HasOwnButtons(key) : module.Model.HasOwnScroll(key));

    // MARK: - Scrolling

    public static FrameworkElement Scrolling(MouseModule module) => Live(module, () =>
    {
        var model = module.Model;
        var key = module.Selected;
        var card = Ui.Card(WheelSettings(model, key));
        card.IsEnabled = Editable(module, buttons: false);
        if (!card.IsEnabled) card.Opacity = 0.5;
        return Ui.Column(16, Profiles(module, buttons: false), Ui.Section(L("Mouse Wheel")), card);
    });

    private static FrameworkElement WheelSettings(MouseModel model, string? key)
    {
        var scroll = model.Scroll(key);
        var direction = Ui.Segmented(new[] { (false, L("Classic")), (true, L("Natural")) }, scroll.Natural, natural => model.SetScroll(key, s => s.Natural = natural));
        var time = Ui.Text($"{Math.Round(ScrollMath.Duration(scroll.Smoothness) * 1000)} ms", 11.5, FontWeights.SemiBold, "TextSecondary", "MonoFont");
        var timeSlider = Ui.Level(scroll.Smoothness, value =>
        {
            time.Text = $"{Math.Round(ScrollMath.Duration(value) * 1000)} ms";
            model.SetScroll(key, s => s.Smoothness = value);
        });
        timeSlider.Width = 200;
        timeSlider.IsEnabled = scroll.Smooth;
        var speed = Ui.Text($"{scroll.Speed:0.00}×", 11.5, FontWeights.SemiBold, "TextSecondary", "MonoFont");
        var speedSlider = Ui.Level(scroll.Speed, value =>
        {
            var rounded = Math.Round(value / 0.05) * 0.05;
            speed.Text = $"{rounded:0.00}×";
            model.SetScroll(key, s => s.Speed = rounded);
        }, 0.5, 2);
        speedSlider.Width = 200;
        speedSlider.IsEnabled = scroll.CustomSpeed;
        return Ui.Column(14,
            Ui.Setting(L("Scroll Direction"), L("Natural: the content follows your finger, as on a phone."), direction, "\uE8CB"),
            Ui.Hairline(),
            Ui.Setting(L("Smooth Scrolling"), L("Each notch glides and slows down at the end."), Ui.Switch(scroll.Smooth, on => model.SetScroll(key, s => s.Smooth = on)), "\uE8B3"),
            Ui.Setting(L("Animation Time"), null, Ui.Row(10, timeSlider, time)),
            Ui.Hairline(),
            Ui.Setting(L("Custom Scroll Speed"), null, Ui.Switch(scroll.CustomSpeed, on => model.SetScroll(key, s => s.CustomSpeed = on)), "\uEC4A"),
            Ui.Setting(L("Scroll Speed"), null, Ui.Row(10, speedSlider, speed)),
            Ui.Hairline(),
            Ui.Setting(L("Scroll sideways with Shift"), L("Shift + wheel scrolls left and right."), Ui.Switch(scroll.ShiftSideways, on => model.SetScroll(key, s => s.ShiftSideways = on)), "\uE8AB"),
            Ui.Setting(L("Back & forward with Ctrl+Shift"), L("Ctrl + Shift + wheel goes back and forward in browsers."), Ui.Switch(scroll.BackForward, on => model.SetScroll(key, s => s.BackForward = on)), "\uE72B"));
    }

    // MARK: - Buttons

    public static FrameworkElement Buttons(MouseModule module) => Live(module, () =>
    {
        var model = module.Model;
        var key = module.Selected;
        var cards = Ui.Column(14);
        foreach (var button in new[] { MouseButton.Middle, MouseButton.Back, MouseButton.Forward })
        {
            var rows = Ui.Column(10, Ui.Row(10, Ui.Glyph(button == MouseButton.Middle ? "\uE962" : button == MouseButton.Back ? "\uE72B" : "\uE72A", 16, "VioletLight"),
                                              Ui.Text(ButtonName(button), 14, FontWeights.SemiBold)));
            foreach (var gesture in Enum.GetValues<Gesture>())
            {
                rows.Children.Add(Ui.Hairline());
                rows.Children.Add(Ui.Spread(Ui.Text(GestureName(gesture), 13, color: "TextSecondary"),
                                            ActionPicker(module, key, button, gesture)));
            }
            cards.Children.Add(Ui.Card(rows));
        }
        cards.IsEnabled = Editable(module, buttons: true);
        if (!cards.IsEnabled) cards.Opacity = 0.5;
        var note = Ui.Text(L("Left and right clicks stay as they are. A gesture set to Nothing keeps the button's own click."), 11.5, color: "TextFaint", wrap: true);
        return Ui.Column(16, Profiles(module, buttons: true), cards, note);
    });

    /// <summary>The action of one gesture: a button showing it, opening the actions that gesture can have.</summary>
    private static Button ActionPicker(MouseModule module, string? key, MouseButton button, Gesture gesture)
    {
        var model = module.Model;
        var action = model.ActionOf(key, button, gesture);
        var title = action == MouseAction.Shortcut && model.ShortcutOf(key, button, gesture) is { } combo ? combo.Name : ActionName(action);
        var picker = Ui.Ghost(title, () => { }, "\uE70D");
        picker.MinWidth = 200;
        picker.Click += (_, _) =>
        {
            var menu = new ContextMenu { PlacementTarget = picker, Placement = PlacementMode.Bottom };
            foreach (var group in Groups(gesture))
            {
                if (menu.Items.Count > 0) menu.Items.Add(new Separator());
                foreach (var choice in group)
                {
                    var item = new MenuItem { Header = ActionName(choice), IsCheckable = true, IsChecked = choice == action };
                    item.Click += (_, _) =>
                    {
                        if (choice == MouseAction.Shortcut) Record(picker, combo => model.SetAction(key, button, gesture, MouseAction.Shortcut, combo));
                        else model.SetAction(key, button, gesture, choice);
                    };
                    menu.Items.Add(item);
                }
            }
            menu.IsOpen = true;
        };
        return picker;
    }

    /// <summary>Waits for a key combination on <paramref name="picker"/>; Esc cancels.</summary>
    private static void Record(Button picker, Action<KeyCombo> recorded)
    {
        picker.Content = Ui.Text(L("Press a key combination…"), 12, FontWeights.Medium, "Solar");
        picker.Focusable = true;
        picker.Focus();
        Keyboard.Focus(picker);
        void OnKey(object sender, KeyEventArgs e)
        {
            var key = e.Key == Key.System ? e.SystemKey : e.Key;
            if (key is Key.LeftCtrl or Key.RightCtrl or Key.LeftAlt or Key.RightAlt or Key.LeftShift or Key.RightShift or Key.LWin or Key.RWin) return;
            e.Handled = true;
            picker.PreviewKeyDown -= OnKey;
            if (key == Key.Escape)
            {
                picker.Content = Ui.Text(L("Cancelled"), 12, FontWeights.Medium, "TextMuted");
                return;
            }
            var modifiers = Keyboard.Modifiers;
            var windows = Keyboard.IsKeyDown(Key.LWin) || Keyboard.IsKeyDown(Key.RWin);
            recorded(new KeyCombo(KeyInterop.VirtualKeyFromKey(key), modifiers.HasFlag(ModifierKeys.Control), modifiers.HasFlag(ModifierKeys.Alt),
                                  modifiers.HasFlag(ModifierKeys.Shift), windows));
        }
        picker.PreviewKeyDown += OnKey;
    }

    private static IEnumerable<MouseAction[]> Groups(Gesture gesture) => gesture switch
    {
        Gesture.Drag => new[] { new[] { MouseAction.None }, new[] { MouseAction.DragDesktops, MouseAction.DragTaskView, MouseAction.DragScroll } },
        Gesture.Scroll => new[] { new[] { MouseAction.None }, new[] { MouseAction.ScrollZoom, MouseAction.ScrollDesktops, MouseAction.ScrollHorizontal } },
        _ => new[]
        {
            new[] { MouseAction.None },
            new[] { MouseAction.Back, MouseAction.Forward },
            new[] { MouseAction.TaskView, MouseAction.ShowDesktop, MouseAction.Start, MouseAction.DesktopLeft, MouseAction.DesktopRight },
            new[] { MouseAction.PrimaryClick, MouseAction.PrimaryDoubleClick, MouseAction.SecondaryClick, MouseAction.MiddleClick },
            new[] { MouseAction.PlayPause, MouseAction.NextTrack, MouseAction.PreviousTrack, MouseAction.VolumeUp, MouseAction.VolumeDown, MouseAction.Mute },
            new[] { MouseAction.Shortcut },
        },
    };

    public static string ButtonName(MouseButton button) => button switch
    {
        MouseButton.Middle => L("Middle button (wheel)"),
        MouseButton.Back => L("Back side button"),
        _ => L("Forward side button"),
    };

    public static string GestureName(Gesture gesture) => gesture switch
    {
        Gesture.Click => L("Click"),
        Gesture.DoubleClick => L("Double Click"),
        Gesture.Hold => L("Hold"),
        Gesture.Drag => L("Hold & Drag"),
        _ => L("Hold & Scroll"),
    };

    public static string ActionName(MouseAction action) => action switch
    {
        MouseAction.None => L("Nothing"),
        MouseAction.TaskView => L("Task View"),
        MouseAction.ShowDesktop => L("Show Desktop"),
        MouseAction.Start => L("Start Menu"),
        MouseAction.DesktopLeft => L("Desktop on the Left"),
        MouseAction.DesktopRight => L("Desktop on the Right"),
        MouseAction.Back => L("Back"),
        MouseAction.Forward => L("Forward"),
        MouseAction.PrimaryClick => L("Left Click"),
        MouseAction.PrimaryDoubleClick => L("Double Left Click"),
        MouseAction.SecondaryClick => L("Right Click"),
        MouseAction.MiddleClick => L("Middle Click"),
        MouseAction.Shortcut => L("Shortcut Key…"),
        MouseAction.PlayPause => L("Play / Pause"),
        MouseAction.NextTrack => L("Next Track"),
        MouseAction.PreviousTrack => L("Previous Track"),
        MouseAction.VolumeUp => L("Volume Up"),
        MouseAction.VolumeDown => L("Volume Down"),
        MouseAction.Mute => L("Mute"),
        MouseAction.DragDesktops => L("Switch Desktops (sideways)"),
        MouseAction.DragTaskView => L("Task View (up) · Desktop (down)"),
        MouseAction.DragScroll => L("Grab to Scroll"),
        MouseAction.ScrollZoom => L("Zoom"),
        MouseAction.ScrollDesktops => L("Switch Desktops"),
        _ => L("Scroll Sideways"),
    };

    // MARK: - Mice

    public static FrameworkElement Mice(MouseModule module) => Live(module, () =>
    {
        var model = module.Model;
        var list = Ui.Column(0);
        foreach (var device in model.Connected)
        {
            if (list.Children.Count > 0) list.Children.Add(Ui.Hairline().Margin(0, 12, 0, 12));
            list.Children.Add(MouseRow(module, device.Key, connected: true));
        }
        if (model.Connected.Count == 0) list.Children.Add(Ui.Text(L("No mouse found. Connect one, or pair it in Bluetooth settings."), 12, color: "TextMuted", wrap: true));
        var page = Ui.Column(14, Ui.Text(L("CONNECTED MICE ({0})", model.Connected.Count), 11, FontWeights.SemiBold, "TextMuted", "MonoFont"), Ui.Card(list));
        var remembered = model.Devices.Keys.Where(k => model.Connected.All(c => c.Key != k)).ToList();
        if (remembered.Count > 0)
        {
            var old = Ui.Column(0);
            foreach (var key in remembered)
            {
                if (old.Children.Count > 0) old.Children.Add(Ui.Hairline().Margin(0, 10, 0, 10));
                old.Children.Add(MouseRow(module, key, connected: false));
            }
            page.Children.Add(Ui.Text(L("REMEMBERED, NOT CONNECTED"), 11, FontWeights.SemiBold, "TextMuted", "MonoFont"));
            page.Children.Add(Ui.Card(old));
        }
        return page;
    });

    private static FrameworkElement MouseRow(MouseModule module, string key, bool connected)
    {
        var model = module.Model;
        var profile = model.Devices.TryGetValue(key, out var found) ? found : new DeviceProfile();
        var chips = Ui.Row(6,
            key == model.InUse ? Ui.Chip(L("In use"), "Emerald", dot: true) : null,
            Ui.Chip(model.HasOwnButtons(key) ? L("Own buttons") : L("Shared buttons"), model.HasOwnButtons(key) ? "VioletLight" : "TextMuted"),
            Ui.Chip(model.HasOwnScroll(key) ? L("Own scrolling") : L("Shared scrolling"), model.HasOwnScroll(key) ? "VioletLight" : "TextMuted"));
        var detail = connected
            ? string.Join(" · ", new[] { profile.Manufacturer, profile.Connection, key }.Where(s => !string.IsNullOrEmpty(s)))
            : L("Last seen {0}", profile.LastSeen.ToString("g"));
        var text = Ui.Column(3, Ui.Row(8, Ui.Text(profile.Name, 14, FontWeights.SemiBold), chips), Ui.Text(detail, 11.5, color: "TextMuted"));
        var heading = Ui.Row(12, Ui.Glyph("\uE962", 20, "VioletLight"), text);
        FrameworkElement trailing = connected
            ? Ui.Ghost(L("Customize"), () =>
            {
                module.Select(key);
                module.ShowTab(2);
            }, "\uE76C")
            : Ui.Ghost(L("Forget"), () => model.Forget(key), "\uE74D");
        return Ui.Spread(heading, trailing);
    }

    // MARK: - Menu

    public static FrameworkElement Menu(MouseModule module) => Live(module, () =>
    {
        var model = module.Model;
        var following = model.Following;
        var scroll = model.Scroll(following);
        var title = L("Scrolling") + " · " + (following != null && model.HasOwnScroll(following) ? model.NameOf(following) : L("All mice"));
        var direction = Ui.Segmented(new[] { (false, L("Classic")), (true, L("Natural")) }, scroll.Natural, natural => model.SetScroll(following, s => s.Natural = natural));
        var speed = Ui.Text($"{scroll.Speed:0.00}×", 11.5, FontWeights.SemiBold, "TextSecondary", "MonoFont");
        var slider = Ui.Level(scroll.Speed, value =>
        {
            var rounded = Math.Round(value / 0.05) * 0.05;
            speed.Text = $"{rounded:0.00}×";
            model.SetScroll(following, s =>
            {
                s.Speed = rounded;
                s.CustomSpeed = true;
            });
        }, 0.5, 2);
        slider.Width = 190;
        var column = Ui.Column(12,
            Ui.Text(title, 12, FontWeights.SemiBold, "TextSecondary"),
            Ui.Spread(Ui.Text(L("Direction"), 13), direction),
            Ui.Spread(Ui.Text(L("Smooth Scrolling"), 13), Ui.Switch(scroll.Smooth, on => model.SetScroll(following, s => s.Smooth = on))),
            Ui.Spread(Ui.Text(L("Speed"), 13), Ui.Row(8, slider, speed)),
            Ui.Hairline(),
            Ui.Text(L("Mice"), 12, FontWeights.SemiBold, "TextSecondary"));
        foreach (var device in model.Connected)
        {
            var dot = new System.Windows.Shapes.Ellipse { Width = 6, Height = 6 }.Res(System.Windows.Shapes.Shape.FillProperty, device.Key == model.InUse ? "Emerald" : "TextFaint");
            column.Children.Add(Ui.Row(8, dot, Ui.Text(model.NameOf(device.Key), 13), Ui.Text(device.Connection, 11, color: "TextMuted")));
        }
        if (model.Connected.Count == 0) column.Children.Add(Ui.Text(L("No mouse found."), 12, color: "TextMuted"));
        if (!model.IsEnabled) column.Opacity = 0.5;
        return column;
    });
}
