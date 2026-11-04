// Copyright 2024 The Flutter Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file or at https://developers.google.com/open-source/licenses/bsd.

import 'dart:io';

import 'package:devtools_shared/devtools_server.dart';
import 'package:devtools_shared/devtools_shared.dart';
import 'package:devtools_shared/src/extensions/extension_manager.dart';
import 'package:devtools_shared/src/server/server_api.dart' as server;
import 'package:dtd/dtd.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

import '../fakes.dart';
import '../helpers/helpers.dart';

void main() {
  group('General DevTools server API', () {
    group('request validation', () {
      Future<Response> handleRequest({
        String method = 'post',
        Uri? uri,
        Map<String, Object>? headers,
      }) async {
        final request = Request(
          method,
          uri ??
              Uri(
                scheme: 'https',
                host: 'localhost',
                port: 9100,
                path: apiGetFlutterGAClientId,
              ),
          headers: headers,
        );
        return await server.ServerApi.handle(
          request,
          extensionsManager: ExtensionsManager(),
          deeplinkManager: FakeDeeplinkManager(),
        );
      }

      test('rejects GET requests with 405 Method Not Allowed', () async {
        final response = await handleRequest(method: 'get');
        expect(response.statusCode, HttpStatus.methodNotAllowed);
        expect(
          await response.readAsString(),
          contains('Method Not Allowed: POST required'),
        );
      });

      test('rejects non-loopback Host headers and requestedUri host', () async {
        for (final invalidHost in [
          'evil.example.com',
          'evil.example.com:9100',
          '127.evil.example.com',
          '192.168.1.1',
          'evil.example.com@localhost',
        ]) {
          final response = await handleRequest(headers: {'host': invalidHost});
          expect(
            response.statusCode,
            HttpStatus.forbidden,
            reason: 'Expected Host header "$invalidHost" to be rejected',
          );
        }

        final nonLoopbackUriResponse = await handleRequest(
          uri: Uri(
            scheme: 'https',
            host: 'evil.example.com',
            port: 9100,
            path: apiGetFlutterGAClientId,
          ),
        );
        expect(nonLoopbackUriResponse.statusCode, HttpStatus.forbidden);
      });

      test(
        'rejects non-loopback or mismatched-port Origin headers with 403 Forbidden',
        () async {
          for (final invalidOrigin in [
            'https://evil.example.com',
            'http://evil.example.com:9100',
            'null',
            'http://localhost:8888',
            'http://127.0.0.1:8888',
            'http://localhost',
          ]) {
            final response = await handleRequest(
              headers: {'origin': invalidOrigin},
            );
            expect(
              response.statusCode,
              HttpStatus.forbidden,
              reason: 'Expected Origin header "$invalidOrigin" to be rejected',
            );
          }
        },
      );

      test('rejects Sec-Fetch-Site: cross-site with 403 Forbidden', () async {
        final crossSiteResponse = await handleRequest(
          headers: {'sec-fetch-site': 'cross-site'},
        );
        expect(crossSiteResponse.statusCode, HttpStatus.forbidden);

        final sameSiteResponse = await handleRequest(
          headers: {'sec-fetch-site': 'same-site'},
        );
        expect(sameSiteResponse.statusCode, HttpStatus.forbidden);
      });

      test(
        'succeeds with valid loopback Host, matching loopback Origin, and Sec-Fetch-Site: same-origin',
        () async {
          for (final validHost in [
            'localhost:9100',
            '127.0.0.1:9100',
            '127.0.1.1:9100',
            '[::1]:9100',
          ]) {
            final response = await handleRequest(
              headers: {
                'host': validHost,
                'origin': 'https://localhost:9100',
                'sec-fetch-site': 'same-origin',
              },
            );
            expect(
              response.statusCode,
              HttpStatus.ok,
              reason: 'Expected valid Host "$validHost" to succeed',
            );
          }
        },
      );
    });

    group(apiNotifyForVmServiceConnection, () {
      Future<Response> sendNotifyRequest({
        required DtdInfo? dtd,
        Map<String, Object?>? queryParameters,
        // ignore: avoid-redundant-async, returning FutureOr.
      }) async {
        final request = Request(
          'post',
          Uri(
            scheme: 'https',
            host: 'localhost',
            path: apiNotifyForVmServiceConnection,
            queryParameters: queryParameters,
          ),
        );
        return server.ServerApi.handle(
          request,
          extensionsManager: ExtensionsManager(),
          deeplinkManager: FakeDeeplinkManager(),
          dtd: dtd,
        );
      }

      test('succeeds when DTD is not available', () async {
        final response = await sendNotifyRequest(
          dtd: null,
          queryParameters: {
            apiParameterValueKey: 'fake_uri',
            apiParameterVmServiceConnected: 'true',
          },
        );
        expect(response.statusCode, HttpStatus.ok);
        expect(await response.readAsString(), isEmpty);
      });

      test('returns badRequest for invalid VM service argument', () async {
        final response = await sendNotifyRequest(
          dtd: DtdInfo(Uri.parse('ws://dtd/uri'), secret: 'fake_secret'),
          queryParameters: {
            apiParameterValueKey: 'fake_uri',
            apiParameterVmServiceConnected: 'true',
          },
        );
        expect(response.statusCode, HttpStatus.badRequest);
        expect(
          await response.readAsString(),
          contains('Cannot normalize VM service URI'),
        );
      });
      test(
        'returns badRequest for invalid $apiParameterVmServiceConnected argument',
        () async {
          final response = await sendNotifyRequest(
            dtd: DtdInfo(Uri.parse('ws://dtd/uri'), secret: 'fake_secret'),
            queryParameters: {
              apiParameterValueKey: 'ws://127.0.0.1:8181/LEpVqqD7E_Y=/ws',
              apiParameterVmServiceConnected: 'bad_arg',
            },
          );
          expect(response.statusCode, HttpStatus.badRequest);
          expect(
            await response.readAsString(),
            contains('Cannot parse $apiParameterVmServiceConnected parameter'),
          );
        },
      );
    });

    group('endpoints that require DTD', () {
      TestDtdConnectionInfo? dtd;
      DartToolingDaemon? testDtdConnection;

      setUp(() async {
        dtd = await startDtd();
        expect(dtd!.info, isNotNull, reason: 'Error starting DTD for test');
        testDtdConnection = await DartToolingDaemon.connect(
          dtd!.info!.localUri,
        );
      });

      tearDown(() async {
        await testDtdConnection?.close();
        dtd?.process?.kill();
        await dtd?.process?.exitCode;
        dtd = null;
      });

      group('updateDtdWorkspaceRoots', () {
        Future<void> updateWorkspaceRoots({
          required Uri root,
          required bool connected,
        }) async {
          await server.VmServiceHandler.updateDtdWorkspaceRoots(
            testDtdConnection!,
            dtdConnectionInfo: dtd!.info!,
            rootFromVmService: root,
            connected: connected,
            api: ServerApi(),
          );
        }

        Future<void> verifyWorkspaceRoots(Set<Uri> roots) async {
          final currentRoots = (await testDtdConnection!.getIDEWorkspaceRoots())
              .ideWorkspaceRoots;
          expect(currentRoots, hasLength(roots.length));
          expect(currentRoots, containsAll(roots));
        }

        test('adds and removes workspace roots', () async {
          await verifyWorkspaceRoots({});
          final rootUri1 = Uri.parse('file:///Users/me/package_root_1');
          final rootUri2 = Uri.parse('file:///Users/me/package_root_2');

          await updateWorkspaceRoots(root: rootUri1, connected: true);
          await verifyWorkspaceRoots({rootUri1});

          // Add a second root and verify the roots are unioned.
          await updateWorkspaceRoots(root: rootUri2, connected: true);
          await verifyWorkspaceRoots({rootUri1, rootUri2});

          // Verify duplicates cannot be added.
          await updateWorkspaceRoots(root: rootUri2, connected: true);
          await verifyWorkspaceRoots({rootUri1, rootUri2});

          // Verify roots are removed for disconnect events.
          await updateWorkspaceRoots(root: rootUri2, connected: false);
          await verifyWorkspaceRoots({rootUri1});
          await updateWorkspaceRoots(root: rootUri1, connected: false);
          await verifyWorkspaceRoots({});
        }, timeout: const Timeout.factor(4));
      });

      group('detectRootPackageForVmService', () {
        TestDartApp? app;
        String? vmServiceUriString;

        setUp(() async {
          app = TestDartApp();
          vmServiceUriString = await app!.start();
          expect(vmServiceUriString, isNotEmpty);
        });

        tearDown(() async {
          await app?.kill();
          app = null;
          vmServiceUriString = null;
        });

        test('succeeds for a connect event', () async {
          final vmServiceUri = normalizeVmServiceUri(vmServiceUriString!);
          expect(vmServiceUri, isNotNull);
          late server.DetectRootPackageResponse response;
          await runWithRetry(
            callback: () async {
              response =
                  await server.VmServiceHandler.detectRootPackageForVmService(
                    vmServiceUriAsString: vmServiceUriString!,
                    vmServiceUri: vmServiceUri!,
                    connected: true,
                    dtd: testDtdConnection!,
                  );
              if (!response.success) throw Exception('VM not ready');
            },
            maxRetries: 20,
            retryDelay: const Duration(milliseconds: 500),
          );
          expect(response.success, true);
          expect(response.message, isNull);
          expect(response.uri, isNotNull);
          expect(response.uri!.toFilePath(), endsWith(app!.directory.path));
        });

        test('succeeds for a disconnect event when cache is empty', () async {
          final response =
              await server.VmServiceHandler.detectRootPackageForVmService(
                vmServiceUriAsString: vmServiceUriString!,
                vmServiceUri: Uri.parse('ws://127.0.0.1:63555/fake-uri=/ws'),
                connected: false,
                dtd: testDtdConnection!,
              );
          expect(response, (success: true, message: null, uri: null));
        });

        test(
          'succeeds for a disconnect event when cache contains entry for VM service',
          () async {
            final vmServiceUri = normalizeVmServiceUri(vmServiceUriString!);
            expect(vmServiceUri, isNotNull);
            late server.DetectRootPackageResponse response;
            await runWithRetry(
              callback: () async {
                response =
                    await server.VmServiceHandler.detectRootPackageForVmService(
                      vmServiceUriAsString: vmServiceUriString!,
                      vmServiceUri: vmServiceUri!,
                      connected: true,
                      dtd: testDtdConnection!,
                    );
                if (!response.success) throw Exception('VM not ready');
              },
              maxRetries: 20,
              retryDelay: const Duration(milliseconds: 500),
            );
            expect(response.success, true);
            expect(response.message, isNull);
            expect(response.uri, isNotNull);
            expect(response.uri!.toFilePath(), endsWith(app!.directory.path));

            final disconnectResponse =
                await server.VmServiceHandler.detectRootPackageForVmService(
                  vmServiceUriAsString: vmServiceUriString!,
                  vmServiceUri: vmServiceUri!,
                  connected: false,
                  dtd: testDtdConnection!,
                );
            expect(disconnectResponse.success, true);
            expect(disconnectResponse.message, isNull);
            expect(disconnectResponse.uri, isNotNull);
            expect(
              disconnectResponse.uri!.toFilePath(),
              endsWith(app!.directory.path),
            );
          },
        );
      });
    });
  });
}
