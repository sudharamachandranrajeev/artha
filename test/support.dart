import 'dart:io';

import 'package:artha/core/db/database.dart';
import 'package:drift/native.dart';

const testKey = '00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff';

/// A fresh encrypted database in a temp file (memory databases skip the
/// cipher, so a file is the honest test).
Future<AppDatabase> openTestDatabase({String key = testKey, File? file}) async {
  final f = file ?? File('${(await Directory.systemTemp.createTemp('artha')).path}/t.db');
  return AppDatabase(NativeDatabase(f, setup: (db) => applyEncryptionKey(db, key)));
}
