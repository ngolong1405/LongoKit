using System.Security.Cryptography;
using System.Security.Cryptography.X509Certificates;

namespace LongoShare;

/// <summary>
/// This device's self-signed certificate for HTTPS, made once and kept, so its fingerprint (the certificate's SHA-256)
/// stays the same: that's how other devices know it again.
/// </summary>
public static class Certificate
{
    public static X509Certificate2 LoadOrCreate(string path)
    {
        if (File.Exists(path))
        {
            try
            {
                return new X509Certificate2(File.ReadAllBytes(path), (string?)null, X509KeyStorageFlags.Exportable);
            }
            catch (CryptographicException)
            {
                // Unreadable: a new one.
            }
        }
        var certificate = Create();
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        File.WriteAllBytes(path, certificate.Export(X509ContentType.Pfx));
        return certificate;
    }

    public static X509Certificate2 Create()
    {
        using var key = RSA.Create(2048);
        var request = new CertificateRequest("CN=Longo Share", key, HashAlgorithmName.SHA256, RSASignaturePadding.Pkcs1);
        var made = request.CreateSelfSigned(DateTimeOffset.UtcNow.AddDays(-1), DateTimeOffset.UtcNow.AddYears(10));
        // Re-read from PFX: on Windows a key made in memory can't be used by SslStream otherwise.
        return new X509Certificate2(made.Export(X509ContentType.Pfx), (string?)null, X509KeyStorageFlags.Exportable);
    }

    /// <summary>The SHA-256 of the certificate, in hex, as LocalSend uses it.</summary>
    public static string Fingerprint(X509Certificate certificate) =>
        Convert.ToHexString(SHA256.HashData(certificate.GetRawCertData())).ToLowerInvariant();
}
