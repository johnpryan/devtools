// Copyright 2024 The Flutter Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file or at https://developers.google.com/open-source/licenses/bsd.

import 'package:dtd/dtd.dart';
import 'package:meta/meta.dart';

// ignore: unused-code, false positive.
const _fileUriPrefix = 'file://';

final _windowsDriveLetterRegExp = RegExp(r'^[a-zA-Z]:$');

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
/// slash.
Future<String> packageRootFromFileUriString(
  String fileUriString, {
  DartToolingDaemon? dtd,
  @visibleForTesting bool throwOnDtdSearchFailed = false,
}) async {
  final parsedUri = _validateFileUri(fileUriString, 'fileUriString');
  if (_effectivePathSegments(parsedUri).length < 2) {
    throw ArgumentError.value(
      fileUriString,
      'fileUriString',
      'URI cannot be a top-level or root directory.',
    );
  }

  if (dtd != null) {
    // Use type [Object] so we can store exceptions of all types.
    Object? exception;
    var listedAnyDirectory = false;

    var uri = parsedUri;
    while (uri.pathSegments.length > 1) {
      // Remove the last path segment.
      uri = uri.replace(
        pathSegments: uri.pathSegments.sublist(0, uri.pathSegments.length - 1),
      );
      try {
        final directoryContents = await dtd.listDirectoryContents(uri);
        listedAnyDirectory = true;
        final containsDartToolDirectory = (directoryContents.uris ?? const [])
            .any((uri) => uri.path.endsWith('.dart_tool/'));
        if (containsDartToolDirectory) {
          final uriAsString = uri.toString();
          return _assertUriFormatAndReturn(
            uriAsString.endsWith('/')
                ? uriAsString.substring(0, uriAsString.length - 1)
                : uriAsString,
          );
        }
      } catch (e) {
        // Fail gracefully on exception, and proceed to using heuristic below.
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
    if (listedAnyDirectory || exception == null) {
      throw ArgumentError.value(
        fileUriString,
        'fileUriString',
        'Could not find a Dart package root (.dart_tool) for URI.',
      );
    }
  }

  // If we do not have access to DTD or if we failed to detect the package root
  // by walking the directory structure, default to using a regexp heuristic.
  final directoryRegExp = RegExp(
    r'\/(lib|bin|integration_test|test|benchmark|example)\/.+\.dart',
  );
  final directoryIndex = fileUriString.lastIndexOf(directoryRegExp);
  if (directoryIndex != -1) {
    fileUriString = fileUriString.substring(0, directoryIndex);
  }
  return _assertUriFormatAndReturn(fileUriString);
}

Uri _validateFileUri(String uriString, String argumentName) {
  final parsedUri = Uri.tryParse(uriString);
  if (!uriString.startsWith(_fileUriPrefix) ||
      parsedUri == null ||
      parsedUri.scheme != 'file' ||
      parsedUri.host.isNotEmpty) {
    throw ArgumentError.value(
      uriString,
      argumentName,
      'Invalid URI format: expected a local file:// URI String with an empty '
      'host.',
    );
  }
  return parsedUri;
}

/// Returns the non-empty path segments of [uri], excluding any leading Windows
/// drive letter segment (e.g. `C:`).
List<String> _effectivePathSegments(Uri uri) {
  final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
  if (segments.isNotEmpty &&
      _windowsDriveLetterRegExp.hasMatch(segments.first)) {
    return segments.sublist(1);
  }
  return segments;
}

String _assertUriFormatAndReturn(String uriString) {
  final parsedUri = _validateFileUri(uriString, 'uriString');
  if (uriString.endsWith('/')) {
    throw ArgumentError.value(
      uriString,
      'uriString',
      'Invalid URI format: should not have a trailing slash.',
    );
  }
  if (_effectivePathSegments(parsedUri).length < 2) {
    throw ArgumentError.value(
      uriString,
      'uriString',
      'URI cannot be a top-level or root directory.',
    );
  }
  return uriString;
}
