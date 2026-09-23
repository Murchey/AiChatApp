import 'package:ai_chat/services/workshop_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('selects the first published release for repository update preview', () {
    final release = latestPublishedReleaseFromJson([
      {
        'tag_name': 'v2.1.0-beta',
        'body': '预发布内容',
        'prerelease': true,
      },
      {
        'tag_name': 'v2.0.0',
        'body': '# 真实更新说明\n\n- 已发布',
        'draft': false,
        'prerelease': false,
      },
    ]);

    expect(release, isNotNull);
    expect(release!.tag, 'v2.0.0');
    expect(release.body, '# 真实更新说明\n\n- 已发布');
  });

  test('uses release name when the latest release has no body', () {
    final release = latestPublishedReleaseFromJson([
      {'tag_name': 'V1.4.0', 'name': '稳定版', 'body': ''},
    ]);

    expect(release, isNotNull);
    expect(release!.body, '稳定版');
  });
}
