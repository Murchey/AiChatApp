from pathlib import Path

def find_class_block(text, class_decl):
    i = text.find(class_decl)
    if i < 0:
        return None
    k = text.find("{", i)
    depth = 0
    for p in range(k, len(text)):
        if text[p] == "{":
            depth += 1
        elif text[p] == "}":
            depth -= 1
            if depth == 0:
                return i, p + 1
    return None

src = Path(r"D:\Projects\vibecoding\AiChatApp\lib\screens\character_detail_screen.dart")
t = src.read_text(encoding="utf-8")
# physics class
for decl in ["class _MomentsScrollPhysics extends BouncingScrollPhysics"]:
    b = find_class_block(t, decl)
    if not b:
        print("MISS", decl)
        continue
    s,e = b
    chunk = t[s:e].replace("_MomentsScrollPhysics", "MomentsScrollPhysics")
    t = t[:s]+t[e:]
    t = t.replace("_MomentsScrollPhysics", "MomentsScrollPhysics")
    Path(r"D:\Projects\vibecoding\AiChatApp\lib\widgets\character\moments_scroll_physics.dart").write_text(
        "import 'package:flutter/cupertino.dart';\nimport 'package:flutter/physics.dart';\n\n/// 朋友圈列表滚动物理（顶部橡皮筋、底部硬截止）。\n" + chunk + "\n",
        encoding="utf-8",
    )
    print("ok physics")
if "moments_scroll_physics.dart" not in t:
    t = t.replace("import '../config/theme.dart';", "import '../config/theme.dart';\nimport '../widgets/character/moments_scroll_physics.dart';")
src.write_text(t, encoding="utf-8")
print("done")
