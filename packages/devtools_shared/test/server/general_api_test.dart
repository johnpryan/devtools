// Copyright 2024 The Flutter Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file or at https://developers.google.com/open-source/licenses/bsd.

import 'dart:io';

import 'package:devtools_shared/devtools_server.dart';
import 'package:devtools_shared/devtools_shared.dart';
import 'package:devtools_shared/src/extensions/extension_manager.dart';
import 'package:devtools_shared/src/server/server_api.dart' as server;
import 'package:dtd/dtd.dart';
import 'package:path/path.dart' as p;
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

import '../fakes.dart';
import '../helpers/helpers.dart';

void main() {
  group('General DevTools server API', () {
    group(apiNotifyForVmServiceConnection, () {
      Future<Response> sendNotifyRequest({
        required DtdInfo? dtd,
        Map<String, Object?>? queryParameters,
        // ignore: avoid-redundant-async, returning FutureOr.
      }) async {
        final request = Request(
          'get',
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
        Future<Response> updateWorkspaceRoots({
          required Uri root,
          required bool connected,
        }) async {
          return await server.VmServiceHandler.updateDtdWorkspaceRoots(
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
          final tempDir1 = Directory.systemTemp.createTempSync(
            'package_root_1_',
          );
          final tempDir2 = Directory.systemTemp.createTempSync(
            'package_root_2_',
          );
          File(p.join(tempDir1.path, 'pubspec.yaml')).createSync();
          Directory(p.join(tempDir2.path, '.dart_tool')).createSync();
          addTearDown(() async {
            await deleteDirectoryWithRetry(tempDir1);
            await deleteDirectoryWithRetry(tempDir2);
          });

          await verifyWorkspaceRoots({});
          final rootUri1 = Uri.file(tempDir1.path);
          final rootUri2 = Uri.file(tempDir2.path);

          var response = await updateWorkspaceRoots(
            root: rootUri1,
            connected: true,
          );
          expect(response.statusCode, HttpStatus.ok);
          await verifyWorkspaceRoots({rootUri1});

          // Add a second root and verify the roots are unioned.
          response = await updateWorkspaceRoots(
            root: rootUri2,
            connected: true,
          );
          expect(response.statusCode, HttpStatus.ok);
          await verifyWorkspaceRoots({rootUri1, rootUri2});

          // Verify duplicates cannot be added.
          response = await updateWorkspaceRoots(
            root: rootUri2,
            connected: true,
          );
          expect(response.statusCode, HttpStatus.ok);
          await verifyWorkspaceRoots({rootUri1, rootUri2});

          // Verify roots are removed for disconnect events.
          response = await updateWorkspaceRoots(
            root: rootUri2,
            connected: false,
          );
          expect(response.statusCode, HttpStatus.ok);
          await verifyWorkspaceRoots({rootUri1});
          response = await updateWorkspaceRoots(
            root: rootUri1,
            connected: false,
          );
          expect(response.statusCode, HttpStatus.ok);
          await verifyWorkspaceRoots({});
        }, timeout: const Timeout.factor(4));

        test('rejects user home directory', () async {
          final homePath =
              Platform.environment['HOME'] ??
              Platform.environment['USERPROFILE'];
          expect(homePath, isNotNull);
          final response = await updateWorkspaceRoots(
            root: Uri.file(homePath!),
            connected: true,
          );
          expect(response.statusCode, HttpStatus.badRequest);
          await verifyWorkspaceRoots({});
        });

        test(
          'rejects filesystem root and single-segment top-level directories',
          () async {
            for (final uri in [
              Uri.parse('file:///'),
              Uri.parse('file:///Users'),
              Uri.parse('file:///tmp'),
            ]) {
              final response = await updateWorkspaceRoots(
                root: uri,
                connected: true,
              );
              expect(response.statusCode, HttpStatus.badRequest);
              await verifyWorkspaceRoots({});
            }
          },
        );

        test('rejects non-existent directory', () async {
          final response = await updateWorkspaceRoots(
            root: Uri.parse('file:///Users/me/non_existent_package_root_12345'),
            connected: true,
          );
          expect(response.statusCode, HttpStatus.badRequest);
          await verifyWorkspaceRoots({});
        });

        test('rejects directory without pubspec.yaml or .dart_tool', () async {
          final emptyTempDir = Directory.systemTemp.createTempSync(
            'non_package_dir_',
          );
          addTearDown(() async {
            await deleteDirectoryWithRetry(emptyTempDir);
          });
          final response = await updateWorkspaceRoots(
            root: Uri.file(emptyTempDir.path),
            connected: true,
          );
          expect(response.statusCode, HttpStatus.badRequest);
          await verifyWorkspaceRoots({});
        });
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
