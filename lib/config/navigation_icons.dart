import 'package:flutter/cupertino.dart';

/// Shared navigation icon family used by the mobile and desktop navigation
/// surfaces. Context-specific action icons keep their own semantic symbols.
typedef _AppNavigationTab = ({IconData icon, IconData activeIcon, String label});

class AppNavigationIcons {
  AppNavigationIcons._();

  static const tabs = <_AppNavigationTab>[
    (
      icon: CupertinoIcons.bubble_left,
      activeIcon: CupertinoIcons.bubble_left_fill,
      label: 'AiChat',
    ),
    (
      icon: CupertinoIcons.person_2,
      activeIcon: CupertinoIcons.person_2_fill,
      label: '通讯录',
    ),
    (
      icon: CupertinoIcons.compass,
      activeIcon: CupertinoIcons.compass_fill,
      label: '朋友圈',
    ),
    (
      icon: CupertinoIcons.person_crop_circle,
      activeIcon: CupertinoIcons.person_crop_circle_fill,
      label: '我',
    ),
  ];
}
