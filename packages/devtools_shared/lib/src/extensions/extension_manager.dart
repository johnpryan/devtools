// Copyright 2023 The Flutter Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file or at https://developers.google.com/open-source/licenses/bsd.

import 'package:collection/collection.dart';
import 'package:dtd/dtd.dart';
import 'package:extension_discovery/extension_discovery.dart';
import 'package:path/path.dart' as path;

import '../common.dart';
import 'constants.dart';
import 'extension_model.dart';

/// The default location for the DevTools extension, relative to
/// `<parent_package_root>/extension/devtools/`.
const extensionBuildDefault = 'build';

/// Responsible for storing the available DevTools extensions and managing the
/// content that DevTools server will serve at `build/devtools_extensions`.
///
/// When [serveAvailableExtensions] is called, the available extensions will be
/// looked up using package:extension_discovery, and the available extension's
/// assets will be copied to the `build/devtools_extensions` directory that
/// DevTools server is serving.
class ExtensionsManager {
  /// The list of available DevTools extensions that are being served by the
  /// DevTools server.
  ///
  /// This list will be cleared and re-populated each time
  /// [serveAvailableExtensions] is called.
  final devtoolsExtensions = <DevToolsExtensionConfig>[];

  final _extensionLocationsByIdentifier = <String, String?>{};

  /// Returns the absolute path of the assets for the extension with identifier
  /// [extensionIdentifier].
  ///
  /// This caches values upon first request for faster lookup.
  String? lookupLocationFor(String extensionIdentifier) {
    return _extensionLocationsByIdentifier.putIfAbsent(
      extensionIdentifier,
      () => devtoolsExtensions
          .firstWhereOrNull((e) => e.identifier == extensionIdentifier)
          ?.extensionAssetsPath,
    );
  }

  /// Whether [uri] matches the `devtools_options.yaml` file URI of any
  /// currently served extension in [devtoolsExtensions].
  bool isServedDevToolsOptionsUri(Uri uri) {
    if (uri.scheme != 'file' || uri.host.isNotEmpty) return false;
    final targetPath = path.normalize(uri.toFilePath());
    return devtoolsExtensions.any((ext) {
      final extUri = Uri.tryParse(ext.devtoolsOptionsUri);
      if (extUri == null || extUri.scheme != 'file' || extUri.host.isNotEmpty) {
        return false;
      }
      return path.equals(path.normalize(extUri.toFilePath()), targetPath);
    });
  }

  /// Serves any available DevTools extensions for the given
  /// [rootFileUriString], where [rootFileUriString] is the root for a Dart or
  /// Flutter project containing the `.dart_tool/` directory.
  ///
  /// [rootFileUriString] is expected to be a file URI string (e.g. starting
  /// with 'file://').
  ///
  /// This method first looks up the available extensions using
  /// package:extension_discovery, and the available extension's
  /// assets will be copied to the `build/devtools_extensions` directory that
  /// DevTools server is serving.
  Future<void> serveAvailableExtensions(
    String? rootFileUriString,
    List<String> logs,
    DtdInfo? dtd, {
    Iterable<Uri> allowedRuntimePackageRoots = const <Uri>[],
  }) async {
    logs.add(
      'ExtensionsManager.serveAvailableExtensions for '
      'rootPathFileUri: $rootFileUriString',
    );

    _clear();
    final parsingErrors = StringBuffer();

    final allowedRoots = <Uri>{...allowedRuntimePackageRoots};
    var staticProjectRoots = const <Uri>[];

    final dtdUri = dtd?.localUri;
    if (dtdUri != null) {
      DartToolingDaemon? dartToolingDaemon;
      try {
        dartToolingDaemon = await DartToolingDaemon.connect(dtdUri);
        final workspaceRoots = await dartToolingDaemon.getIDEWorkspaceRoots();
        allowedRoots.addAll(workspaceRoots.ideWorkspaceRoots);

        final projectRoots = await dartToolingDaemon.getProjectRoots(
          depth: staticExtensionsSearchDepth,
        );
        staticProjectRoots = projectRoots.uris ?? const <Uri>[];
        allowedRoots.addAll(staticProjectRoots);
      } finally {
        await dartToolingDaemon?.close();
      }
    }

    // Find all runtime extensions for [rootFileUriString], if non-null and
    // non-empty.
    if (rootFileUriString != null && rootFileUriString.isNotEmpty) {
      _assertUriFormat(rootFileUriString);
      final rootUri = Uri.parse(rootFileUriString);
      if (!_isWithinAllowedRoots(rootUri, allowedRoots)) {
        throw ArgumentError.value(
          rootFileUriString,
          'rootFileUriString',
          'must be within an active DTD workspace root or connected VM service '
              'package root',
        );
      }

      logs.add(
        'ExtensionsManager.serveAvailableExtensions adding extensions for app '
        'root.',
      );
      await _addExtensionsForRoot(
        rootFileUriString,
        logs: logs,
        parsingErrors: parsingErrors,
        staticContext: false,
      );
    }

    // Find all static extensions for the project roots, which are derived from
    // the Dart Tooling Daemon, and add them to [devtoolsExtensions].
    if (dtdUri != null) {
      logs.add(
        'ExtensionsManager.serveAvailableExtensions adding extensions for '
        'DTD project roots: $staticProjectRoots',
      );

      for (final root in staticProjectRoots) {
        // Skip the runtime app root. These extensions have already been
        // added to [devtoolsExtensions].
        if (root.toString() == rootFileUriString) continue;

        await _addExtensionsForRoot(
          root.toString(),
          logs: logs,
          parsingErrors: parsingErrors,
          staticContext: true,
        );
      }
    }

    if (parsingErrors.isNotEmpty) {
      throw ExtensionParsingException(
        'Encountered errors while parsing extension config.yaml '
        'files:\n$parsingErrors',
      );
    }
  }

  /// Finds the available extensions for the package root at
  /// [rootFileUriString], generates [DevToolsExtensionConfig] objects, and adds
  /// them to [devtoolsExtensions].
  Future<void> _addExtensionsForRoot(
    String rootFileUriString, {
    required List<String> logs,
    required StringBuffer parsingErrors,
    required bool staticContext,
  }) async {
    _assertUriFormat(rootFileUriString);
    final List<Extension> extensions;
    final packageConfigPath = findPackageConfig(Uri.parse(rootFileUriString));
    extensions = await findExtensions(
      'devtools',
      packageConfig: packageConfigPath,
    );
    logs.add(
      'ExtensionsManager._addExtensionsForRoot find extensions for '
      'config: $packageConfigPath, result: '
      '${extensions.map((e) => e.package).toList()}',
    );

    for (final extension in extensions) {
      final config = extension.config;

      // TODO(https://github.com/dart-lang/pub/issues/4042): make this check
      // more robust.
      final isPubliclyHosted =
          (extension.rootUri.path.contains('pub.dev') ||
                  extension.rootUri.path.contains('pub.flutter-io.cn'))
              .toString();

      // This should be relative to the 'extension/devtools/' directory and
      // defaults to 'build';
      final relativeExtensionLocation =
          config['buildLocation'] as String? ?? 'build';

      final packageRoot = path.normalize(extension.rootUri.toFilePath());
      final location = path.normalize(
        path.join(
          packageRoot,
          'extension',
          'devtools',
          relativeExtensionLocation,
        ),
      );

      // Verify that this extension's build location is a subdirectory of the
      // package providing the extension. Usually this is
      // $HOME/.pub-cache/hosted/pub.dev/foo-1.0.0/extension/devtools/build.
      //
      // This prevents packages from declaring a build location outside of
      // their package directory (e.g. ../../../../.ssh/)
      if (!path.isWithin(packageRoot, location)) {
        parsingErrors.writeln(
          'Ignoring extension from package "${extension.package}": invalid '
          'buildLocation "$relativeExtensionLocation" outside package root.',
        );
        continue;
      }

      try {
        final extensionConfig = DevToolsExtensionConfig.parse({
          ...config,
          DevToolsExtensionConfig.packageNameKey: extension.package,
          DevToolsExtensionConfig.extensionAssetsPathKey: location,
          // The [packageConfigPath] will look like
          // 'pkg/.dart_tool/package_config.json' so we will store the
          // devtools_options.yaml file at the 'pkg' root:
          // 'pkg/devtools_options.yaml'.
          DevToolsExtensionConfig.devtoolsOptionsUriKey: path.url.join(
            path.url.dirname(path.url.dirname(packageConfigPath.toString())),
            devtoolsOptionsFileName,
          ),
          DevToolsExtensionConfig.isPubliclyHostedKey: isPubliclyHosted,
          DevToolsExtensionConfig.detectedFromStaticContextKey: staticContext
              .toString(),
        });
        devtoolsExtensions.add(extensionConfig);
      } on StateError catch (e) {
        parsingErrors.writeln(e.message);
        continue;
      }
    }
  }

  bool _isWithinAllowedRoots(Uri candidateUri, Iterable<Uri> allowedRoots) {
    if (candidateUri.scheme != 'file' || candidateUri.host.isNotEmpty) {
      return false;
    }
    final candidatePath = path.normalize(candidateUri.toFilePath());
    for (final allowedRoot in allowedRoots) {
      if (allowedRoot.scheme != 'file' || allowedRoot.host.isNotEmpty) {
        continue;
      }
      final allowedPath = path.normalize(allowedRoot.toFilePath());
      if (path.equals(allowedPath, candidatePath) ||
          path.isWithin(allowedPath, candidatePath)) {
        return true;
      }
    }
    return false;
  }

  void _assertUriFormat(String? uriString) {
    if (uriString == null) return;
    final uri = Uri.tryParse(uriString);
    if (!uriString.startsWith('file://') ||
        uri == null ||
        uri.scheme != 'file' ||
        uri.host.isNotEmpty) {
      throw ArgumentError.value(uriString, 'must be a file:// URI String');
    }
  }

  void _clear() {
    _extensionLocationsByIdentifier.clear();
    devtoolsExtensions.clear();
  }
}

/// Exception type for errors encountered while parsing DevTools extension
/// config.yaml files.
class ExtensionParsingException extends FormatException {
  const ExtensionParsingException(super.message);
}
