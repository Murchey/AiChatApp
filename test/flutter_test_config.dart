import 'dart:async';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  FlutterSecureStorage.setMockInitialValues({});
  await testMain();
}
