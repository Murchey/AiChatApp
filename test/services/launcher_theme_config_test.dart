import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:xml/xml.dart';

void main() {
  test('every launcher alias supplies Flutter normal theme metadata', () {
    final document = XmlDocument.parse(
        File('android/app/src/main/AndroidManifest.xml').readAsStringSync());
    final aliases = document.findAllElements('activity-alias').toList();
    expect(aliases, hasLength(3));
    for (final alias in aliases) {
      final normalTheme = alias.findElements('meta-data').where((entry) =>
          entry.getAttribute('android:name') ==
          'io.flutter.embedding.android.NormalTheme');
      expect(normalTheme.single.getAttribute('android:resource'),
          '@style/NormalTheme',
          reason:
              '${alias.getAttribute('android:name')} must exit the splash theme');
    }
    for (final directory in ['values-v31', 'values-night-v31']) {
      final styles = XmlDocument.parse(
          File('android/app/src/main/res/$directory/styles.xml')
              .readAsStringSync());
      final launch = styles
          .findAllElements('style')
          .firstWhere((style) => style.getAttribute('name') == 'LaunchTheme');
      final items = {
        for (final item in launch.findElements('item'))
          item.getAttribute('name'): item.innerText
      };
      expect(items['android:windowNoTitle'], 'true');
      expect(items['android:windowActionBar'], 'false');
    }
  });
}
