// Copyright 2022 The Flutter Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file or at https://developers.google.com/open-source/licenses/bsd.

import 'package:devtools_shared/src/service_utils.dart';
import 'package:test/test.dart';

void main() {
  group('normalizeVmServiceUri', () {
    test('normalizes simple URIs', () {
      expect(
        normalizeVmServiceUri('http://127.0.0.1:60667/72K34Xmq0X0=').toString(),
        equals('http://127.0.0.1:60667/72K34Xmq0X0='),
      );
      expect(
        normalizeVmServiceUri(
          'http://127.0.0.1:60667/72K34Xmq0X0=/   ',
        ).toString(),
        equals('http://127.0.0.1:60667/72K34Xmq0X0=/'),
      );
      expect(
        normalizeVmServiceUri('http://127.0.0.1:60667').toString(),
        equals('http://127.0.0.1:60667'),
      );
      expect(
        normalizeVmServiceUri('http://127.0.0.1:60667/').toString(),
        equals('http://127.0.0.1:60667/'),
      );
    });

    test('properly strips leading whitespace and trailing URI fragments', () {
      expect(
        normalizeVmServiceUri(
          '  http://127.0.0.1:60667/72K34Xmq0X0=/#/vm',
        ).toString(),
        equals('http://127.0.0.1:60667/72K34Xmq0X0=/'),
      );
      expect(
        normalizeVmServiceUri(
          '  http://127.0.0.1:60667/72K34Xmq0X0=/#/vm  ',
        ).toString(),
        equals('http://127.0.0.1:60667/72K34Xmq0X0=/'),
      );
    });

    test('properly handles encoded urls', () {
      expect(
        normalizeVmServiceUri(
          'http%3A%2F%2F127.0.0.1%3A58824%2FCnvgRrQJG7w%3D',
        ).toString(),
        equals('http://127.0.0.1:58824/CnvgRrQJG7w='),
      );

      expect(
        normalizeVmServiceUri(
          'http%3A%2F%2F127.0.0.1%3A58824%2FCnvgRrQJG7w%3D  ',
        ).toString(),
        equals('http://127.0.0.1:58824/CnvgRrQJG7w='),
      );

      expect(
        normalizeVmServiceUri(
          '  http%3A%2F%2F127.0.0.1%3A58824%2FCnvgRrQJG7w%3D   ',
        ).toString(),
        equals('http://127.0.0.1:58824/CnvgRrQJG7w='),
      );
    });

    test('handles prefixed devtools server uris', () {
      expect(
        normalizeVmServiceUri(
          'http://127.0.0.1:9101?uri=http%3A%2F%2F127.0.0.1%3A56142%2FHOwgrxalK00%3D%2F',
        ).toString(),
        equals('http://127.0.0.1:56142/HOwgrxalK00=/'),
      );
    });

    test('Returns null when given a non-absolute url', () {
      expect(normalizeVmServiceUri('my/page'), null);
    });

    test('allows valid schemes and loopback hosts', () {
      expect(
        normalizeVmServiceUri('http://127.0.0.1:60667/72K34Xmq0X0=').toString(),
        equals('http://127.0.0.1:60667/72K34Xmq0X0='),
      );
      expect(
        normalizeVmServiceUri(
          'https://127.0.0.1:60667/72K34Xmq0X0=',
        ).toString(),
        equals('https://127.0.0.1:60667/72K34Xmq0X0='),
      );
      expect(
        normalizeVmServiceUri('ws://localhost:8181/ws').toString(),
        equals('ws://localhost:8181/ws'),
      );
      expect(
        normalizeVmServiceUri('wss://localhost:8181/ws').toString(),
        equals('wss://localhost:8181/ws'),
      );
      expect(
        normalizeVmServiceUri('sse://127.0.0.1:8181').toString(),
        equals('sse://127.0.0.1:8181'),
      );
      expect(
        normalizeVmServiceUri('sses://localhost:8181').toString(),
        equals('sses://localhost:8181'),
      );
      expect(
        normalizeVmServiceUri('http://[::1]:60667/72K34Xmq0X0=').toString(),
        equals('http://[::1]:60667/72K34Xmq0X0='),
      );
      expect(
        normalizeVmServiceUri('http://127.0.1.1:8181').toString(),
        equals('http://127.0.1.1:8181'),
      );
    });

    test('returns null for non-loopback hosts', () {
      expect(normalizeVmServiceUri('ws://attacker.evil/fake'), isNull);
      expect(normalizeVmServiceUri('http://192.168.1.1:8181'), isNull);
      expect(normalizeVmServiceUri('http://10.0.0.1:8181'), isNull);
      expect(normalizeVmServiceUri('http://127.0.0.1.evil.com:8181'), isNull);
    });

    test('returns null for disallowed schemes and malformed URIs', () {
      expect(normalizeVmServiceUri('file:///etc/passwd'), isNull);
      expect(normalizeVmServiceUri('javascript:alert(1)'), isNull);
      expect(normalizeVmServiceUri('ftp://127.0.0.1:8181/'), isNull);
      expect(normalizeVmServiceUri('data:text/plain;base64,SGVsbG8='), isNull);
      expect(normalizeVmServiceUri('http://[::1:8181'), isNull);
    });
  });
}
