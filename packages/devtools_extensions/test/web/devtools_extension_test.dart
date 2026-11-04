// Copyright 2023 The Flutter Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file or at https://developers.google.com/open-source/licenses/bsd.

@TestOn('browser')
library;

import 'dart:js_interop';

import 'package:devtools_extensions/api.dart';
import 'package:devtools_extensions/devtools_extensions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web/web.dart';

void main() {
  group('Global managers', () {
    test('accessing early throws error', () {
      expect(() => serviceManager, throwsStateError);
      expect(() => extensionManager, throwsStateError);
      expect(() => dtdManager, throwsStateError);
    });

    testWidgets('building $DevToolsExtension initializes globals', (
      tester,
    ) async {
      await tester.pumpWidget(const DevToolsExtension(child: SizedBox()));
      expect(serviceManager, isNotNull);
      expect(extensionManager, isNotNull);
      expect(dtdManager, isNotNull);
    });

    testWidgets('$ExtensionManager validates MessageEvent origin and source', (
      tester,
    ) async {
      DevToolsExtensionEvent? receivedEvent;
      await tester.pumpWidget(
        DevToolsExtension(
          eventHandlers: {
            DevToolsExtensionEventType.themeUpdate: (event) {
              receivedEvent = event;
            },
          },
          child: const SizedBox(),
        ),
      );

      final validSameOriginEvent = MessageEvent(
        'message',
        MessageEventInit(
          origin: window.origin,
          source: window.parent,
          data: {
            'type': DevToolsExtensionEventType.themeUpdate.name,
            'data': {
              ExtensionEventParameters.theme:
                  ExtensionEventParameters.themeValueLight,
            },
          }.jsify(),
        ),
      );
      expect(
        extensionManager.isAllowedMessageEvent(validSameOriginEvent),
        isTrue,
      );

      final validLoopbackEvent = MessageEvent(
        'message',
        MessageEventInit(
          origin: 'http://127.0.0.1:9100',
          source: window.parent,
        ),
      );
      expect(
        extensionManager.isAllowedMessageEvent(validLoopbackEvent),
        isTrue,
      );

      final untrustedOriginEvent = MessageEvent(
        'message',
        MessageEventInit(
          origin: 'https://evil.example.com',
          source: window.parent,
          data: {
            'type': DevToolsExtensionEventType.themeUpdate.name,
            'data': {
              ExtensionEventParameters.theme:
                  ExtensionEventParameters.themeValueLight,
            },
          }.jsify(),
        ),
      );
      expect(
        extensionManager.isAllowedMessageEvent(untrustedOriginEvent),
        isFalse,
      );

      final nullOriginEvent = MessageEvent(
        'message',
        MessageEventInit(origin: 'null', source: window.parent),
      );
      expect(extensionManager.isAllowedMessageEvent(nullOriginEvent), isFalse);

      final otherIframe = HTMLIFrameElement();
      document.body!.appendChild(otherIframe);
      addTearDown(otherIframe.remove);
      final mismatchedSourceEvent = MessageEvent(
        'message',
        MessageEventInit(
          origin: window.origin,
          source: otherIframe.contentWindow,
          data: {
            'type': DevToolsExtensionEventType.themeUpdate.name,
            'data': {
              ExtensionEventParameters.theme:
                  ExtensionEventParameters.themeValueLight,
            },
          }.jsify(),
        ),
      );
      expect(
        extensionManager.isAllowedMessageEvent(mismatchedSourceEvent),
        isFalse,
      );

      // Dispatch untrusted and mismatched-source events and verify they are
      // ignored.
      window.dispatchEvent(untrustedOriginEvent);
      window.dispatchEvent(mismatchedSourceEvent);
      expect(receivedEvent, isNull);

      // Dispatch valid event and verify it is accepted.
      window.dispatchEvent(validSameOriginEvent);
      await tester.pump();
      expect(receivedEvent, isNotNull);
      expect(receivedEvent!.type, DevToolsExtensionEventType.themeUpdate);
    });
  });
}
