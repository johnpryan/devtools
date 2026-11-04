// Copyright 2022 The Flutter Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file or at https://developers.google.com/open-source/licenses/bsd.

class RegisteredService {
  const RegisteredService({required this.service, required this.title});

  final String service;
  final String title;
}

/// Flutter memory service registered by Flutter Tools.
///
/// We call this service to get version information about the Flutter Android
/// memory info using Android's ADB.
const flutterMemory = RegisteredService(
  service: 'flutterMemoryInfo',
  title: 'Flutter Memory Info',
);

const flutterListViews = '_flutter.listViews';

/// Flutter engine returns estimate how much memory is used by layer/picture
/// raster cache entries in bytes.
const flutterEngineRasterCache = '_flutter.estimateRasterCacheMemory';

/// Returns a normalized vm service uri.
///
/// Removes trailing characters, trailing url fragments, and decodes urls that
/// were accidentally encoded.
///
/// For example, given a [value] of http://127.0.0.1:60667/72K34Xmq0X0=/#/vm,
/// this method will return the URI http://127.0.0.1:60667/72K34Xmq0X0=/.
///
/// Returns null if the [Uri] parsed from [value] is not [Uri.isAbsolute]
/// (i.e., it has no scheme or it has a fragment), if its scheme is not one of
/// the allowed VM service schemes (`http`, `https`, `ws`, `wss`, `sse`,
/// `sses`), or if its host is not a loopback address (`localhost`, `127.x.x.x`,
/// or `::1`).
Uri? normalizeVmServiceUri(String value) {
  value = value.trim();

  // Clean up urls that have a devtools server's prefix, aka:
  // http://127.0.0.1:9101?uri=http%3A%2F%2F127.0.0.1%3A56142%2FHOwgrxalK00%3D%2F
  const uriParamToken = '?uri=';
  if (value.contains(uriParamToken)) {
    value = value.substring(
      value.indexOf(uriParamToken) + uriParamToken.length,
    );
  }

  // Cleanup encoded urls likely copied from the uri of an existing running
  // DevTools app.
  if (value.contains('%3A%2F%2F')) {
    try {
      value = Uri.decodeFull(value);
    } on ArgumentError {
      return null;
    }
  }
  final uri = Uri.tryParse(value.trim())?.removeFragment();
  if (uri == null || !uri.isAbsolute) {
    return null;
  }
  const allowedSchemes = {'http', 'https', 'ws', 'wss', 'sse', 'sses'};
  if (!allowedSchemes.contains(uri.scheme) || !isLoopbackHost(uri.host)) {
    return null;
  }
  if (uri.path.endsWith('/')) return uri;
  return uri.replace(path: uri.path);
}

final _ipv4LoopbackRegex = RegExp(
  r'^127(?:\.(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)){3}$',
);

/// Returns whether [host] is a loopback host (`localhost`, `127.x.x.x`, or
/// IPv6 `::1`).
bool isLoopbackHost(String host) {
  final normalizedHost = host.toLowerCase();
  if (normalizedHost == 'localhost' ||
      normalizedHost == '::1' ||
      normalizedHost == '[::1]' ||
      normalizedHost == '0:0:0:0:0:0:0:1' ||
      normalizedHost == '[0:0:0:0:0:0:0:1]') {
    return true;
  }
  return _ipv4LoopbackRegex.hasMatch(normalizedHost);
}
