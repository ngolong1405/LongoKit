using System.Text.Json;
using System.Text.Json.Serialization;

namespace LongoKit.UI;

/// <summary>
/// Settings kept as JSON in %APPDATA%\LongoKit, one file per module. A module and its own app read and write the same
/// file, so they share one set of settings (they never run at once).
/// </summary>
public static class Store
{
    public static string Folder { get; set; } =
        Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "LongoKit");

    private static readonly JsonSerializerOptions Options = new()
    {
        WriteIndented = true,
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        Converters = { new JsonStringEnumConverter(JsonNamingPolicy.CamelCase) },
    };

    public static string PathOf(string name) => System.IO.Path.Combine(Folder, name + ".json");

    /// <summary>The settings saved under <paramref name="name"/>, or new ones if there are none (or they can't be read).</summary>
    public static T Load<T>(string name) where T : new()
    {
        try
        {
            var path = PathOf(name);
            if (File.Exists(path)) return JsonSerializer.Deserialize<T>(File.ReadAllText(path), Options) ?? new T();
        }
        catch (Exception error) when (error is JsonException or IOException or UnauthorizedAccessException)
        {
            // Unreadable settings start over rather than stop the app.
        }
        return new T();
    }

    /// <summary>Saves <paramref name="value"/> under <paramref name="name"/>, written whole so it's never half there.</summary>
    public static void Save<T>(string name, T value)
    {
        Directory.CreateDirectory(Folder);
        var path = PathOf(name);
        var temporary = path + ".tmp";
        File.WriteAllText(temporary, JsonSerializer.Serialize(value, Options));
        File.Move(temporary, path, overwrite: true);
    }
}
