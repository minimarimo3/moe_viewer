import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:moe_viewer/src/core/models/folder_setting.dart';
import 'package:moe_viewer/src/core/services/duplicate_service.dart';

void main() {
  test('DuplicateService groups identical files', () async {
    final tempDir = await Directory.systemTemp.createTemp('dup_test_');
    addTearDown(() async => tempDir.delete(recursive: true));

    final a = File('${tempDir.path}/a.jpg');
    final b = File('${tempDir.path}/sub/b.jpg')..createSync(recursive: true);
    final c = File('${tempDir.path}/c.jpg');

    // Two identical contents
    await a.writeAsBytes([1,2,3,4,5]);
    await b.writeAsBytes([1,2,3,4,5]);
    await c.writeAsBytes([9,9,9]);

    final service = DuplicateService();
    final groups = await service.findDuplicates([
      FolderSetting(path: tempDir.path, isEnabled: true, isDeletable: true),
    ]);

    // Should have at least one group containing a and b
    final allPaths = groups.values.expand((e) => e).toList();
    expect(allPaths.contains(a.path), true);
    expect(allPaths.contains(b.path), true);
    expect(allPaths.contains(c.path), false);
  });
}
