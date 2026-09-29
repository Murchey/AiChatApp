from pathlib import Path
p = Path(r"D:\Projects\vibecoding\AiChatApp\lib\screens\profile_screen.dart")
t = p.read_text(encoding="utf-8")
old = "const Padding(\n                        padding: EdgeInsets.all(12),\n                        child: Text(\n                          '暂无日志',"
new = "Padding(\n                        padding: const EdgeInsets.all(12),\n                        child: Text(\n                          '暂无日志',"
if old in t:
    t = t.replace(old, new)
    print("replaced")
else:
    print("pattern not found")
    # show context
    i = t.find("暂无日志")
    print(repr(t[i-80:i+80]))
p.write_text(t, encoding="utf-8")
