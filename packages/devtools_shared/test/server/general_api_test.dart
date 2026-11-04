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
        late Directory tempDir;

        setUp(() {
          tempDir = Directory.systemTemp.createTempSync('dtd_roots_test_');
        });

        tearDown(() async {
          await deleteDirectoryWithRetry(tempDir);
        });

        Future<Response> updateWorkspaceRoots({
          required Uri root,
          required bool connected,
        }) {
          return server.VmServiceHandler.updateDtdWorkspaceRoots(
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
          final pkgDir1 = Directory(p.join(tempDir.path, 'package_root_1'))
            ..createSync(recursive: true);
          File(p.join(pkgDir1.path, 'pubspec.yaml')).createSync();
          final pkgDir2 = Directory(p.join(tempDir.path, 'package_root_2'))
            ..createSync(recursive: true);
          File(
            p.join(pkgDir2.path, '.dart_tool', 'package_config.json'),
          ).createSync(recursive: true);

          final rootUri1 = Uri.file(pkgDir1.path);
          final rootUri2 = Uri.file(pkgDir2.path);

          final add1Response = await updateWorkspaceRoots(
            root: rootUri1,
            connected: true,
          );
          expect(add1Response.statusCode, HttpStatus.ok);
          await verifyWorkspaceRoots({rootUri1});

          // Add a second root and verify the roots are unioned.
          final add2Response = await updateWorkspaceRoots(
            root: rootUri2,
            connected: true,
          );
          expect(add2Response.statusCode, HttpStatus.ok);
          await verifyWorkspaceRoots({rootUri1, rootUri2});

          // Verify duplicates cannot be added.
          final dupResponse = await updateWorkspaceRoots(
            root: rootUri2,
            connected: true,
          );
          expect(dupResponse.statusCode, HttpStatus.ok);
          await verifyWorkspaceRoots({rootUri1, rootUri2});

          // Verify roots are removed for disconnect events.
          final remove2Response = await updateWorkspaceRoots(
            root: rootUri2,
            connected: false,
          );
          expect(remove2Response.statusCode, HttpStatus.ok);
          await verifyWorkspaceRoots({rootUri1});
          final remove1Response = await updateWorkspaceRoots(
            root: rootUri1,
            connected: false,
          );
          expect(remove1Response.statusCode, HttpStatus.ok);
          await verifyWorkspaceRoots({});
        }, timeout: const Timeout.factor(4));

        test('rejects filesystem root and single-segment paths', () async {
          await verifyWorkspaceRoots({});
          for (final invalidUri in [
            Uri.parse('file:///'),
            Uri.parse('file:///Users'),
            Uri.parse('file:///tmp'),
          ]) {
            final response = await updateWorkspaceRoots(
              root: invalidUri,
              connected: true,
            );
            expect(
              response.statusCode,
              HttpStatus.badRequest,
              reason: 'Expected $invalidUri to be rejected',
            );
          }
          await verifyWorkspaceRoots({});
        });

        test('rejects non-file schemes and non-empty hosts', () async {
          await verifyWorkspaceRoots({});
          for (final invalidUri in [
            Uri.parse('http://localhost/path/to/pkg'),
            Uri.parse('file://evil.host/path/to/pkg'),
          ]) {
            final response = await updateWorkspaceRoots(
              root: invalidUri,
              connected: true,
            );
            expect(
              response.statusCode,
              HttpStatus.badRequest,
              reason: 'Expected $invalidUri to be rejected',
            );
          }
          await verifyWorkspaceRoots({});
        });

        test('rejects user home directory (HOME and USERPROFILE)', () async {
          await verifyWorkspaceRoots({});
          final homeDir =
              Platform.environment['HOME'] ??
              Platform.environment['USERPROFILE'];
          if (homeDir != null && homeDir.isNotEmpty) {
            final response = await updateWorkspaceRoots(
              root: Uri.file(homeDir),
              connected: true,
            );
            expect(response.statusCode, HttpStatus.badRequest);
            expect(await response.readAsString(), contains('home directory'));

            // Also verify a symlink pointing to the home directory is rejected.
            final symlinkToHome = Link(p.join(tempDir.path, 'home_link'))
              ..createSync(homeDir);
            final symlinkResponse = await updateWorkspaceRoots(
              root: Uri.file(symlinkToHome.path),
              connected: true,
            );
            expect(symlinkResponse.statusCode, HttpStatus.badRequest);
            expect(
              await symlinkResponse.readAsString(),
              contains('home directory'),
            );
          }

          // Verify both HOME and USERPROFILE environment variables are checked
          // even when the directory contains a pubspec.yaml file.
          final fakeHomePkg = Directory(p.join(tempDir.path, 'fake_home'))
            ..createSync(recursive: true);
          File(p.join(fakeHomePkg.path, 'pubspec.yaml')).createSync();
          expect(
            server.VmServiceHandler.isValidRootPackageUri(
              Uri.file(fakeHomePkg.path),
            ),
            isTrue,
          );
          expect(
            server.VmServiceHandler.isValidRootPackageUri(
              Uri.file(fakeHomePkg.path),
              environment: {'HOME': fakeHomePkg.path},
            ),
            isFalse,
          );
          expect(
            server.VmServiceHandler.isValidRootPackageUri(
              Uri.file(fakeHomePkg.path),
              environment: {'USERPROFILE': fakeHomePkg.path},
            ),
            isFalse,
          );

          await verifyWorkspaceRoots({});
        });

        test(
          'rejects directories that do not exist or lack package markers',
          () async {
            await verifyWorkspaceRoots({});

            // Non-existent directory.
            final nonExistentUri = Uri.file(
              p.join(tempDir.path, 'does_not_exist'),
            );
            final nonExistentResponse = await updateWorkspaceRoots(
              root: nonExistentUri,
              connected: true,
            );
            expect(nonExistentResponse.statusCode, HttpStatus.badRequest);
            expect(
              await nonExistentResponse.readAsString(),
              contains('directory does not exist'),
            );

            // Existing directory without pubspec.yaml or
            // .dart_tool/package_config.json (only an empty .dart_tool dir).
            final nonPackageDir = Directory(p.join(tempDir.path, 'not_a_pkg'))
              ..createSync(recursive: true);
            Directory(
              p.join(nonPackageDir.path, '.dart_tool'),
            ).createSync(recursive: true);
            final nonPackageResponse = await updateWorkspaceRoots(
              root: Uri.file(nonPackageDir.path),
              connected: true,
            );
            expect(nonPackageResponse.statusCode, HttpStatus.badRequest);
            expect(
              await nonPackageResponse.readAsString(),
              contains(
                'directory does not contain pubspec.yaml or '
                '.dart_tool/package_config.json',
              ),
            );

            await verifyWorkspaceRoots({});
          },
        );
      });

      group('detectRootPackageForVmService', () {
        TestDartApp? app;
        String? vmServiceUriString;

        setUp(() async {
          app = TestDartApp();
          vmServiceUriString = await app!.start();
          expect(vmServiceUriString, isNotEmpty);
          File(p.join(app!.directory.path, 'pubspec.yaml')).createSync();
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

        test(
          'rejects and does not cache root directory without package markers',
          () async {
            File(p.join(app!.directory.path, 'pubspec.yaml')).deleteSync();
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
                if (response.message == null ||
                    !response.message!.contains('Invalid package root URI')) {
                  throw Exception('VM not ready: ${response.message}');
                }
              },
              maxRetries: 20,
              retryDelay: const Duration(milliseconds: 500),
            );
            expect(response.success, false);
            expect(
              response.message,
              contains(
                'directory does not contain pubspec.yaml or '
                '.dart_tool/package_config.json',
              ),
            );
            expect(response.uri, isNull);

            // Verify the rejected root was not cached for disconnect.
            final disconnectResponse =
                await server.VmServiceHandler.detectRootPackageForVmService(
                  vmServiceUriAsString: vmServiceUriString!,
                  vmServiceUri: vmServiceUri!,
                  connected: false,
                  dtd: testDtdConnection!,
                );
            expect(disconnectResponse, (
              success: true,
              message: null,
              uri: null,
            ));
          },
        );
      });
    });
  });
}
