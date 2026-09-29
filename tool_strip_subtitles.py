from pathlib import Path
import re

p = Path(r"D:\Projects\vibecoding\AiChatApp\lib\screens\chat_settings_screen.dart")
t = p.read_text(encoding="utf-8")

# Remove subtitle: const Text('...') / subtitle: Text( ... ), including multi-line
# Keep model list subtitle (contains modelName / formatContextLength)

def remove_subtitle_blocks(text):
    # Match subtitle: Text(...); or subtitle: const Text('...');
    # Use a simple scanner
    result = []
    i = 0
    key = "subtitle:"
    while True:
        j = text.find(key, i)
        if j < 0:
            result.append(text[i:])
            break
        # skip if this is model list (has formatContextLength nearby)
        nearby = text[j:j+250]
        if "formatContextLength" in nearby:
            result.append(text[i:j+1])
            i = j + 1
            continue
        result.append(text[i:j])
        # find start of expression after subtitle:
        k = j + len(key)
        while k < len(text) and text[k] in " \n\t":
            k += 1
        # parse until matching comma at depth 0 of parens
        depth = 0
        started = False
        while k < len(text):
            c = text[k]
            if c == "(":
                depth += 1
                started = True
            elif c == ")":
                depth -= 1
            elif c == "," and started and depth == 0:
                k += 1
                break
            k += 1
        i = k
    return "".join(result)

t2 = remove_subtitle_blocks(t)
# clean double commas leftover / empty lines
t2 = t2.replace(",\n\n              ,", ",\n              ")
p.write_text(t2, encoding="utf-8")
print("removed subtitles, braces", t2.count("{"), t2.count("}"))
print("remaining subtitle", t2.count("subtitle:"))
