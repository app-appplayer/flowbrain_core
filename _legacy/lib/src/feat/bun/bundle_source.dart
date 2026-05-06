/// Bundle source types for FEAT-BUN.
///
/// Sealed class hierarchy representing where a bundle can be loaded from:
/// local file, HTTP URL, or marketplace.
library;

/// Source location for a bundle to be installed.
sealed class BundleSource {
  const BundleSource();

  /// Create a file-based source.
  factory BundleSource.file(String path) = FileBundleSource;

  /// Create an HTTP-based source.
  factory BundleSource.http(String url) = HttpBundleSource;

  /// Create a marketplace source.
  factory BundleSource.marketplace({
    required String id,
    String? version,
  }) = MarketplaceBundleSource;

  /// Parse from a reference string.
  ///
  /// Handles `marketplace://id`, `http(s)://...`, and file paths.
  factory BundleSource.fromRef(String source, {String? version}) {
    if (source.startsWith('marketplace://')) {
      final id = source.replaceFirst('marketplace://', '');
      return BundleSource.marketplace(id: id, version: version);
    }
    if (source.startsWith('http://') || source.startsWith('https://')) {
      return BundleSource.http(source);
    }
    return BundleSource.file(source);
  }
}

/// Load bundle from a local file path.
class FileBundleSource extends BundleSource {
  /// Absolute or relative file path.
  final String path;

  const FileBundleSource(this.path);
}

/// Load bundle from an HTTP(S) URL.
class HttpBundleSource extends BundleSource {
  /// Full URL to the bundle JSON.
  final String url;

  const HttpBundleSource(this.url);
}

/// Load bundle from the marketplace registry.
class MarketplaceBundleSource extends BundleSource {
  /// Marketplace bundle identifier.
  final String id;

  /// Optional version constraint.
  final String? version;

  const MarketplaceBundleSource({required this.id, this.version});
}
