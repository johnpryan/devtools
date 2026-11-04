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
import 'package:web/web.dart' hide SizedBox;

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
  });

  group('$ExtensionManager message validation', () {
    testWidgets('ignores messages from untrusted origins', (tester) async {
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

      final untrustedEvent = MessageEvent(
        'message',
        MessageEventInit(
          data: DevToolsExtensionEvent(
            DevToolsExtensionEventType.themeUpdate,
            data: {
              ExtensionEventParameters.theme:
                  ExtensionEventParameters.themeValueLight,
            },
          ).toJson().jsify(),
          origin: 'https://evil.example.com',
          source: window.parent,
        ),
      );
      expect(
        extensionManager.isValidEventOriginAndSource(untrustedEvent),
        isFalse,
      );
      window.dispatchEvent(untrustedEvent);
      expect(receivedEvent, isNull);
    });

    testWidgets('ignores messages from unexpected source window', (
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

      final missingSourceEvent = MessageEvent(
        'message',
        MessageEventInit(
          data: DevToolsExtensionEvent(
            DevToolsExtensionEventType.themeUpdate,
            data: {
              ExtensionEventParameters.theme:
                  ExtensionEventParameters.themeValueLight,
            },
          ).toJson().jsify(),
          origin: window.origin,
          source: null,
        ),
      );
      expect(
        extensionManager.isValidEventOriginAndSource(missingSourceEvent),
        isFalse,
      );
      window.dispatchEvent(missingSourceEvent);
      expect(receivedEvent, isNull);
    });

    testWidgets('processes messages with valid origin and source', (
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

      final validEvent = MessageEvent(
        'message',
        MessageEventInit(
          data: DevToolsExtensionEvent(
            DevToolsExtensionEventType.themeUpdate,
            data: {
              ExtensionEventParameters.theme:
                  ExtensionEventParameters.themeValueLight,
            },
          ).toJson().jsify(),
          origin: window.origin,
          source: window.parent,
        ),
      );
      expect(extensionManager.isValidEventOriginAndSource(validEvent), isTrue);
      window.dispatchEvent(validEvent);
      await tester.pump();
      expect(receivedEvent, isNotNull);
      expect(receivedEvent!.type, DevToolsExtensionEventType.themeUpdate);
      expect(extensionManager.darkThemeEnabled.value, isFalse);
    });
  });
}
