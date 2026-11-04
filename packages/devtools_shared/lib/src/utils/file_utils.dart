// Copyright 2024 The Flutter Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file or at https://developers.google.com/open-source/licenses/bsd.

import 'package:dtd/dtd.dart';
import 'package:meta/meta.dart';

// ignore: unused-code, false positive.
const _fileUriPrefix = 'file://';

/// Attempts to detect the package root of [fileUriString], which is expected to
/// be a proper file URI (i.e. starts with "file://").
///
/// This method first tries to use the Dart Tooling Daemon to walk the
/// directory structure of [fileUriString] and look for the package root; we
/// consider a directory to be a package root if it contains the `.dart_tool`
/// directory.
///
/// If we cannot find the package root using the Dart Tooling Daemon, we use the
/// heuristic that a Dart executable within a Dart package should reside in one
/// of the following top-level folders:
///
/// * lib
/// * bin
/// * integration_test
/// * test
/// * benchmark
/// * example
///
/// The URI returned will be a file URI String and will NOT have a trailing
/// slash, or `null` if [fileUriString] is not a valid file URI or no valid
/// package root can be detected.
Future<String?> packageRootFromFileUriString(
  String fileUriString, {
  DartToolingDaemon? dtd,
  @visibleForTesting bool throwOnDtdSearchFailed = false,
}) async {
  final uri = Uri.tryParse(fileUriString);
  if (!fileUriString.startsWith(_fileUriPrefix) ||
      uri == null ||
      uri.scheme != 'file' ||
      uri.host.isNotEmpty ||
      uri.pathSegments.contains('..') ||
      uri.pathSegments.contains('.')) {
    return null;
  }

  if (dtd != null) {
    // Use type [Object] so we can store exceptions of all types.
    Object? exception;
    var dtdListedAnyDirectory = false;

    var currentUri = uri;
    while (currentUri.pathSegments.where((s) => s.isNotEmpty).length > 1) {
      final nonEmptySegments = currentUri.pathSegments
          .where((s) => s.isNotEmpty)
          .toList();
      // Remove the last path segment.
      currentUri = currentUri.replace(
        pathSegments: nonEmptySegments.sublist(0, nonEmptySegments.length - 1),
      );
      if (!_isValidPackageRootUri(currentUri)) {
        break;
      }
      try {
        final directoryContents = await dtd.listDirectoryContents(currentUri);
        dtdListedAnyDirectory = true;
        final containsPackageRootMarker = (directoryContents.uris ?? const [])
            .any(
              (entryUri) =>
                  entryUri.path.endsWith('.dart_tool/') ||
                  entryUri.path.endsWith('/pubspec.yaml'),
            );
        if (containsPackageRootMarker) {
          final uriAsString = currentUri.toString();
          return _assertUriFormatAndReturn(
            uriAsString.endsWith('/')
                ? uriAsString.substring(0, uriAsString.length - 1)
                : uriAsString,
          );
        }
      } catch (e) {
        // Fail gracefully on exception.
        exception = e;
        break;
      }
    }
    if (throwOnDtdSearchFailed) {
      throw Exception(
        'Expected DTD to detect the package root for '
        '$fileUriString, but it failed'
        '${exception != null ? ' with exception: $exception' : '.'}',
      );
    }
    if (exception == null || dtdListedAnyDirectory) {
      return null;
    }
    try {
      final workspaceRoots = await dtd.getIDEWorkspaceRoots();
      if (workspaceRoots.ideWorkspaceRoots.isNotEmpty) {
        return null;
      }
    } catch (_) {
      return null;
    }
  }

  // If we do not have access to DTD, default to using a regexp heuristic.
  return _regexPackageRootHeuristic(fileUriString);
}

/// Uses a regular expression heuristic to infer the package root from
/// [fileUriString] by matching standard top-level Dart package directories.
///
/// Returns `null` if no standard package directory is matched or if the
/// truncated candidate URI is not a valid package root (e.g. has fewer than
/// 2 path segments or equals a user home directory).
String? _regexPackageRootHeuristic(String fileUriString) {
  final directoryRegExp = RegExp(
    r'\/(lib|bin|integration_test|test|benchmark|example)\/.+\.dart',
  );
  final directoryIndex = fileUriString.lastIndexOf(directoryRegExp);
  if (directoryIndex == -1) {
    return null;
  }
  final packageRootUriString = fileUriString.substring(0, directoryIndex);
  return _assertUriFormatAndReturn(packageRootUriString);
}

/// Returns whether [uri] is a valid `file://` URI for a package root directory.
///
/// Rejects non-`file` schemes, non-empty hosts, dot-segment traversals, URIs
/// with fewer than 2 path segments, and user home directories.
bool _isValidPackageRootUri(Uri uri) {
  if (uri.scheme != 'file' ||
      uri.host.isNotEmpty ||
      uri.pathSegments.contains('..') ||
      uri.pathSegments.contains('.')) {
    return false;
  }
  final nonEmptySegments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
  final hasWindowsDrive =
      nonEmptySegments.isNotEmpty &&
      RegExp(r'^[a-zA-Z]:$').hasMatch(nonEmptySegments.first);
  final segmentsAfterRoot = hasWindowsDrive
      ? nonEmptySegments.sublist(1)
      : nonEmptySegments;
  if (segmentsAfterRoot.length < 2) {
    return false;
  }
  // Reject user home directories (e.g. /Users/<user>, /home/<user>,
  // C:/Users/<user>, /usr/local/google/home/<user>).
  if (segmentsAfterRoot.length == 2) {
    final topDir = segmentsAfterRoot.first;
    if (topDir == 'Users' ||
        topDir == 'home' ||
        (hasWindowsDrive && topDir.toLowerCase() == 'users')) {
      return false;
    }
  }
  if (segmentsAfterRoot.length == 5 &&
      segmentsAfterRoot[0] == 'usr' &&
      segmentsAfterRoot[1] == 'local' &&
      segmentsAfterRoot[2] == 'google' &&
      segmentsAfterRoot[3] == 'home') {
    return false;
  }
  return true;
}

/// Validates at runtime that [uriString] is a properly formatted `file://`
/// package root URI without a trailing slash, returning `null` if invalid.
String? _assertUriFormatAndReturn(String? uriString) {
  if (uriString == null) return null;
  final uri = Uri.tryParse(uriString);
  if (!uriString.startsWith(_fileUriPrefix) ||
      uriString.endsWith('/') ||
      uri == null ||
      !_isValidPackageRootUri(uri)) {
    return null;
  }
  return uriString;
}
