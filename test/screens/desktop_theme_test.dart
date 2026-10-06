import 'package:ai_chat/screens/desktop/desktop_theme.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('desktop interaction colors follow the selected accent', () {
    const palette = DesktopPalette(Brightness.light, Color(0xFF07C160));

    expect(palette.accent, const Color(0xFF07C160));
    expect(palette.railIconActive, const Color(0xFF07C160));
  });

  test('desktop message bubbles keep their independent color palette', () {
    const palette = DesktopPalette(Brightness.dark, Color(0xFF07C160));

    expect(palette.bubbleSelf, const Color(0xFF0A84FF));
    expect(palette.bubbleOther, const Color(0xFF292C33));
  });
}
