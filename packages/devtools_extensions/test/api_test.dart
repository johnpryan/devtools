// Copyright 2023 The Flutter Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file or at https://developers.google.com/open-source/licenses/bsd.

import 'package:devtools_extensions/api.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('$DevToolsExtensionEvent', () {
    test('parse', () {
      var event = DevToolsExtensionEvent.parse({
        'type': 'ping',
        'data': {'foo': 'bar'},
      });
      expect(event.type, DevToolsExtensionEventType.ping);
      expect(event.data, {'foo': 'bar'});

      event = DevToolsExtensionEvent.parse({
        'type': 'pong',
        'data': {'baz': 'bob'},
      });
      expect(event.type, DevToolsExtensionEventType.pong);
      expect(event.data, {'baz': 'bob'});

      event = DevToolsExtensionEvent.parse({'type': 'idk'});
      expect(event.type, DevToolsExtensionEventType.unknown);
      expect(event.data, isNull);
    });

    test('tryParse', () {
      var event = DevToolsExtensionEvent.tryParse({
        'type': 'ping',
        'data': {'foo': 'bar'},
      });
      expect(event, isNotNull);

      event = DevToolsExtensionEvent.tryParse('bad input');
      expect(event, isNull);

      event = DevToolsExtensionEvent.tryParse({'more', 'bad', 'input'});
      expect(event, isNull);

      event = DevToolsExtensionEvent.tryParse({1: 'bad', 2: 'input'});
      expect(event, isNull);
    });

    test('toJson', () {
      var event = DevToolsExtensionEvent(DevToolsExtensionEventType.ping);
      expect(event.toJson(), {'type': 'ping'});

      event = DevToolsExtensionEvent(
        DevToolsExtensionEventType.pong,
        data: {'foo': 'bar'},
      );
      expect(event.toJson(), {
        'type': 'pong',
        'data': {'foo': 'bar'},
      });

      event = DevToolsExtensionEvent(
        DevToolsExtensionEventType.unknown,
        data: {'foo': 'bar'},
      );
      expect(event.toJson(), {
        'type': 'unknown',
        'data': {'foo': 'bar'},
      });
    });
  });

  group('$DevToolsExtensionEventType', () {
    test('parses for expected values', () {
      expect(
        DevToolsExtensionEventType.from('ping'),
        DevToolsExtensionEventType.ping,
      );
      expect(
        DevToolsExtensionEventType.from('pong'),
        DevToolsExtensionEventType.pong,
      );

      expect(
        DevToolsExtensionEventType.from('forceReload'),
        DevToolsExtensionEventType.forceReload,
      );

      expect(
        DevToolsExtensionEventType.from('showNotification'),
        DevToolsExtensionEventType.showNotification,
      );

      expect(
        DevToolsExtensionEventType.from('showBannerMessage'),
        DevToolsExtensionEventType.showBannerMessage,
      );

      expect(
        DevToolsExtensionEventType.from('copyToClipboard'),
        DevToolsExtensionEventType.copyToClipboard,
      );

      expect(
        DevToolsExtensionEventType.from('vmServiceConnection'),
        DevToolsExtensionEventType.vmServiceConnection,
      );

      expect(
        DevToolsExtensionEventType.from('themeUpdate'),
        DevToolsExtensionEventType.themeUpdate,
      );
    });

    test('parses for unexpected values', () {
      expect(
        DevToolsExtensionEventType.from('PING'),
        DevToolsExtensionEventType.unknown,
      );
      expect(
        DevToolsExtensionEventType.from('pongg'),
        DevToolsExtensionEventType.unknown,
      );
    });

    test('supportedForDirection', () {
      verifyEventDirection(DevToolsExtensionEventType.ping, (
        bidirectional: false,
        toDevTools: false,
        toExtension: true,
      ));
      verifyEventDirection(DevToolsExtensionEventType.pong, (
        bidirectional: false,
        toDevTools: true,
        toExtension: false,
      ));
      verifyEventDirection(DevToolsExtensionEventType.forceReload, (
        bidirectional: false,
        toDevTools: false,
        toExtension: true,
      ));
      verifyEventDirection(DevToolsExtensionEventType.vmServiceConnection, (
        bidirectional: true,
        toDevTools: true,
        toExtension: true,
      ));
      verifyEventDirection(DevToolsExtensionEventType.themeUpdate, (
        bidirectional: false,
        toDevTools: false,
        toExtension: true,
      ));
      verifyEventDirection(DevToolsExtensionEventType.showNotification, (
        bidirectional: false,
        toDevTools: true,
        toExtension: false,
      ));
      verifyEventDirection(DevToolsExtensionEventType.showBannerMessage, (
        bidirectional: false,
        toDevTools: true,
        toExtension: false,
      ));
      verifyEventDirection(DevToolsExtensionEventType.copyToClipboard, (
        bidirectional: false,
        toDevTools: true,
        toExtension: false,
      ));
      verifyEventDirection(DevToolsExtensionEventType.unknown, (
        bidirectional: true,
        toDevTools: true,
        toExtension: true,
      ));
    });
  });

  group('$ShowNotificationExtensionEvent', () {
    test('constructs for expected values', () {
      final event = DevToolsExtensionEvent.parse({
        'type': 'showNotification',
        'data': {'message': 'foo message'},
      });
      final showNotificationEvent = ShowNotificationExtensionEvent.from(event);
      expect(showNotificationEvent.message, 'foo message');
    });
    test('throws for unexpected values', () {
      final event1 = DevToolsExtensionEvent.parse({
        'type': 'showNotification',
        'data': {
          // Missing required fields.
        },
      });
      expect(() {
        ShowNotificationExtensionEvent.from(event1);
      }, throwsFormatException);

      final event2 = DevToolsExtensionEvent.parse({
        'type': 'showNotification',
        'data': {
          // Bad key.
          'msg': 'foo message',
        },
      });
      expect(() {
        ShowNotificationExtensionEvent.from(event2);
      }, throwsFormatException);

      final event3 = DevToolsExtensionEvent.parse({
        'type': 'showNotification',
        'data': {
          // Bad value.
          'message': false,
        },
      });
      expect(() {
        ShowNotificationExtensionEvent.from(event3);
      }, throwsFormatException);

      final event4 = DevToolsExtensionEvent.parse({
        // Wrong type.
        'type': 'showBannerMessage',
        'data': {'message': 'foo message'},
      });
      expect(() {
        ShowNotificationExtensionEvent.from(event4);
      }, throwsAssertionError);
    });
  });

  group('$ShowBannerMessageExtensionEvent', () {
    test('constructs for expected values', () {
      var event = DevToolsExtensionEvent.parse({
        'type': 'showBannerMessage',
        'data': {
          'id': 'fooMessageId',
          'message': 'foo message',
          'bannerMessageType': 'warning',
          'extensionName': 'foo',
        },
      });
      var showBannerMessageEvent = ShowBannerMessageExtensionEvent.from(event);

      expect(showBannerMessageEvent.messageId, 'fooMessageId');
      expect(showBannerMessageEvent.message, 'foo message');
      expect(showBannerMessageEvent.bannerMessageType, 'warning');
      expect(showBannerMessageEvent.extensionName, 'foo');
      expect(showBannerMessageEvent.ignoreIfAlreadyDismissed, true);

      event = DevToolsExtensionEvent.parse({
        'type': 'showBannerMessage',
        'data': {
          'id': 'blah',
          'message': 'blah message',
          'bannerMessageType': 'error',
          'extensionName': 'blah',
          'ignoreIfAlreadyDismissed': false,
        },
      });
      showBannerMessageEvent = ShowBannerMessageExtensionEvent.from(event);

      expect(showBannerMessageEvent.messageId, 'blah');
      expect(showBannerMessageEvent.message, 'blah message');
      expect(showBannerMessageEvent.bannerMessageType, 'error');
      expect(showBannerMessageEvent.extensionName, 'blah');
      expect(showBannerMessageEvent.ignoreIfAlreadyDismissed, false);
    });
    test('throws for unexpected values', () {
      final event1 = DevToolsExtensionEvent.parse({
        'type': 'showBannerMessage',
        'data': {
          // Missing required fields.
          'extensionName': 'foo',
        },
      });
      expect(() {
        ShowBannerMessageExtensionEvent.from(event1);
      }, throwsFormatException);

      final event2 = DevToolsExtensionEvent.parse({
        'type': 'showBannerMessage',
        'data': {
          // Bad keys.
          'bad_key': 'fooMessageId',
          'messages': 'foo message',
          'bannerMessageTypeee': 'warning',
          'extension_name': 'foo',
        },
      });
      expect(() {
        ShowBannerMessageExtensionEvent.from(event2);
      }, throwsFormatException);

      final event3 = DevToolsExtensionEvent.parse({
        'type': 'showBannerMessage',
        'data': {
          // Bad values.
          'id': 1,
          'message': 'foo message',
          'bannerMessageType': 2.0,
          'extensionName': 'foo',
        },
      });
      expect(() {
        ShowBannerMessageExtensionEvent.from(event3);
      }, throwsFormatException);

      final event4 = DevToolsExtensionEvent.parse({
        // Wrong type.
        'type': 'showNotification',
        'data': {
          'id': 'fooMessageId',
          'message': 'foo message',
          'bannerMessageType': 'warning',
          'extensionName': 'foo',
        },
      });
      expect(() {
        ShowBannerMessageExtensionEvent.from(event4);
      }, throwsAssertionError);
    });
  });

  group('$CopyToClipboardExtensionEvent', () {
    test('constructs for expected values', () {
      final event = DevToolsExtensionEvent.parse({
        'type': 'copyToClipboard',
        'data': {'content': 'foo content', 'successMessage': 'foo success'},
      });
      final copyToClipboardEvent = CopyToClipboardExtensionEvent.from(event);
      expect(copyToClipboardEvent.content, 'foo content');
      expect(copyToClipboardEvent.successMessage, 'foo success');
    });
    test('throws for unexpected values', () {
      final event1 = DevToolsExtensionEvent.parse({
        'type': 'copyToClipboard',
        'data': {
          // Missing required fields.
        },
      });
      expect(() {
        CopyToClipboardExtensionEvent.from(event1);
      }, throwsFormatException);

      final event2 = DevToolsExtensionEvent.parse({
        'type': 'copyToClipboard',
        'data': {
          // Bad key.
          'msg': 'foo content',
          'successMessage': 'foo success',
        },
      });
      expect(() {
        CopyToClipboardExtensionEvent.from(event2);
      }, throwsFormatException);

      final event3 = DevToolsExtensionEvent.parse({
        'type': 'copyToClipboard',
        'data': {
          // Bad value.
          'content': false,
          'successMessage': 'foo success',
        },
      });
      expect(() {
        CopyToClipboardExtensionEvent.from(event3);
      }, throwsFormatException);

      final event4 = DevToolsExtensionEvent.parse({
        // Wrong type.
        'type': 'showBannerMessage',
        'data': {'content': 'foo content', 'successMessage': 'foo success'},
      });
      expect(() {
        CopyToClipboardExtensionEvent.from(event4);
      }, throwsAssertionError);
    });
  });

  group('Origin validation helpers', () {
    test('isLoopbackOrigin', () {
      expect(isLoopbackOrigin('http://localhost:9100'), isTrue);
      expect(isLoopbackOrigin('https://localhost:9100'), isTrue);
      expect(isLoopbackOrigin('http://127.0.0.1:9100'), isTrue);
      expect(isLoopbackOrigin('http://[::1]:9100'), isTrue);

      expect(isLoopbackOrigin(''), isFalse);
      expect(isLoopbackOrigin('null'), isFalse);
      expect(isLoopbackOrigin('https://evil.example.com'), isFalse);
      expect(isLoopbackOrigin('ws://127.0.0.1:9100'), isFalse);
      expect(isLoopbackOrigin('data:text/html,hello'), isFalse);
    });

    test('isValidExtensionHostOrigin', () {
      const extensionOrigin = 'http://127.0.0.1:9100';

      // Exact origin match is allowed.
      expect(
        isValidExtensionHostOrigin(
          eventOrigin: extensionOrigin,
          extensionOrigin: extensionOrigin,
        ),
        isTrue,
      );

      // Empty or untrusted origins are rejected.
      expect(
        isValidExtensionHostOrigin(
          eventOrigin: '',
          extensionOrigin: extensionOrigin,
        ),
        isFalse,
      );
      expect(
        isValidExtensionHostOrigin(
          eventOrigin: 'https://evil.example.com',
          extensionOrigin: extensionOrigin,
        ),
        isFalse,
      );
      expect(
        isValidExtensionHostOrigin(
          eventOrigin: 'http://127.0.0.1:8804',
          extensionOrigin: extensionOrigin,
        ),
        isFalse,
      );

      // Different loopback port matching document.referrer is rejected in
      // release mode, but allowed in non-release mode (e.g., `dt run`).
      expect(
        isValidExtensionHostOrigin(
          eventOrigin: 'http://localhost:54321',
          extensionOrigin: extensionOrigin,
          documentReferrer: 'http://localhost:54321/inspector?uri=...',
        ),
        isFalse,
      );
      expect(
        isValidExtensionHostOrigin(
          eventOrigin: 'http://localhost:54321',
          extensionOrigin: extensionOrigin,
          documentReferrer: 'http://localhost:54321/inspector?uri=...',
          isReleaseMode: false,
        ),
        isTrue,
      );

      // Attacker on another loopback port not matching document.referrer is
      // rejected even in non-release mode.
      expect(
        isValidExtensionHostOrigin(
          eventOrigin: 'http://127.0.0.1:8804',
          extensionOrigin: extensionOrigin,
          documentReferrer: 'http://127.0.0.1:9100/?uri=...',
          isReleaseMode: false,
        ),
        isFalse,
      );

      // Non-loopback document.referrer is rejected in non-release mode.
      expect(
        isValidExtensionHostOrigin(
          eventOrigin: 'https://evil.example.com',
          extensionOrigin: extensionOrigin,
          documentReferrer: 'https://evil.example.com/attack.html',
          isReleaseMode: false,
        ),
        isFalse,
      );
    });

    test('isValidExtensionOrigin', () {
      const extensionUrl =
          'http://127.0.0.1:9100/devtools_extensions/foo_ext/index.html?theme=dark';

      expect(
        isValidExtensionOrigin(
          eventOrigin: 'http://127.0.0.1:9100',
          extensionUrl: extensionUrl,
        ),
        isTrue,
      );
      expect(
        isValidExtensionOrigin(eventOrigin: '', extensionUrl: extensionUrl),
        isFalse,
      );
      expect(
        isValidExtensionOrigin(
          eventOrigin: 'http://127.0.0.1:8804',
          extensionUrl: extensionUrl,
        ),
        isFalse,
      );
      expect(
        isValidExtensionOrigin(
          eventOrigin: 'https://evil.example.com',
          extensionUrl: extensionUrl,
        ),
        isFalse,
      );
      expect(
        isValidExtensionOrigin(
          eventOrigin: 'http://127.0.0.1:9100',
          extensionUrl: 'data:text/html;charset=utf-8,placeholder',
        ),
        isFalse,
      );
    });
  });
}

void verifyEventDirection(
  DevToolsExtensionEventType type,
  ({bool bidirectional, bool toDevTools, bool toExtension}) expected,
) {
  expect(
    type.supportedForDirection(ExtensionEventDirection.bidirectional),
    expected.bidirectional,
  );
  expect(
    type.supportedForDirection(ExtensionEventDirection.toDevTools),
    expected.toDevTools,
  );
  expect(
    type.supportedForDirection(ExtensionEventDirection.toExtension),
    expected.toExtension,
  );
}
