using System.Globalization;

namespace LongoKit.UI;

/// <summary>English, Vietnamese, or as Windows is set.</summary>
public enum AppLanguage { System, English, Vietnamese }

/// <summary>
/// The apps are written in English; each one registers its Vietnamese table. <see cref="L"/> looks a string up in the
/// language picked, falling back to the English it was given.
/// </summary>
public static class Localizer
{
    private static readonly Dictionary<string, string> Vietnamese = new();

    public static AppLanguage Language { get; set; } = AppLanguage.System;

    public static bool IsVietnamese => Language switch
    {
        AppLanguage.Vietnamese => true,
        AppLanguage.English => false,
        // Windows' display language (0x2A: Vietnamese), not .NET's culture: the apps run without ICU's language data.
        _ => (GetUserDefaultUILanguage() & 0x3FF) == 0x2A,
    };

    [System.Runtime.InteropServices.DllImport("kernel32.dll")]
    private static extern ushort GetUserDefaultUILanguage();

    /// <summary>Adds a table of Vietnamese strings (English → Vietnamese); a later table wins on the same key.</summary>
    public static void Register(IReadOnlyDictionary<string, string> vietnamese)
    {
        foreach (var (english, translated) in vietnamese) Vietnamese[english] = translated;
    }

    /// <summary>The string in the language picked; <paramref name="args"/> fill its {0}, {1}...</summary>
    public static string L(string english, params object[] args)
    {
        var text = IsVietnamese && Vietnamese.TryGetValue(english, out var translated) ? translated : english;
        return args.Length == 0 ? text : string.Format(CultureInfo.CurrentCulture, text, args);
    }

    static Localizer() => Register(Strings.Vietnamese);
}
