"""Rebuild Hsin_theme using the supplied artwork. Requires Python + Pillow."""
import json
from pathlib import Path
from zipfile import ZipFile, ZIP_DEFLATED

from PIL import Image, ImageDraw, ImageFont, ImageOps

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / 'developDocs' / '心月狐主题素材'
OUTPUT = ROOT / 'developDocs' / 'themes' / 'Hsin_theme'
IMAGES = OUTPUT / 'images'
NAVY = '#182B49'


def square(source, name, size):
    image = Image.open(source).convert('RGBA')
    bounds = image.getchannel('A').getbbox()
    if bounds:
        image = image.crop(bounds)
    image = ImageOps.contain(image, (size - 16, size - 16), Image.Resampling.LANCZOS)
    canvas = Image.new('RGBA', (size, size))
    canvas.alpha_composite(image, ((size - image.width) // 2, (size - image.height) // 2))
    canvas.save(IMAGES / name, optimize=True)


def build():
    IMAGES.mkdir(parents=True, exist_ok=True)
    manifest = {
        'id': 'Hsin_theme', 'name': '心月狐',
        'description': '藏青白字与左侧心月狐装饰；首页和通讯录使用角色照片背景。',
        'preview': 'images/preview.png', 'navigation': {},
    }
    for slot, original in {
        'chat': 'Home.png', 'contacts': '2.png',
        'discover': 'moments.png', 'profile': 'me.png',
    }.items():
        name = f'nav-{slot}.png'
        square(SOURCE / 'nav bar img' / original, name, 192)
        manifest['navigation'][slot] = {
            'normal': f'images/{name}', 'selected': f'images/{name}',
            'width': 192, 'height': 192,
            'size': 36,
        }

    # The supplied horizontal banner is already composed. Preserve its native
    # framing and dimensions rather than reusing the old portrait crop.
    header = Image.open(SOURCE / 'HeaderImg.png').convert('RGB')
    header.save(IMAGES / 'header.png', optimize=True)
    manifest['headers'] = {
        slot: {'file': 'images/header.png', 'width': header.width, 'height': header.height}
        for slot in ('home', 'contacts')
    }

    square(SOURCE / 'chat_bubble_icon.png', 'bubble-leading.png', 320)
    bubble = Image.new('RGBA', (720, 360))
    ImageDraw.Draw(bubble).rounded_rectangle((0, 0, 719, 359), radius=72, fill=NAVY)
    bubble = bubble.resize((240, 120), Image.Resampling.LANCZOS)
    bubble.save(IMAGES / 'self-bubble.png', optimize=True)
    manifest['selfBubble'] = {
        'file': 'images/self-bubble.png', 'width': 240, 'height': 120,
        'stretchInsets': {'left': 24, 'top': 24, 'right': 24, 'bottom': 24},
        'textColor': '#FFFFFF',
        'leading': {'file': 'images/bubble-leading.png', 'width': 320, 'height': 320,
                    'size': 56, 'gap': 8},
    }
    (OUTPUT / 'content.json').write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    preview()
    # Stable file ordering; never include source artwork, secrets or this script.
    archive = OUTPUT.with_suffix('.zip')
    with ZipFile(archive, 'w', ZIP_DEFLATED) as zipped:
        for file in sorted(OUTPUT.rglob('*')):
            if file.is_file():
                zipped.write(file, file.relative_to(OUTPUT).as_posix())
    print(archive)


def preview():
    font_file = Path('C:/Windows/Fonts/msyh.ttc')
    if not font_file.exists():
        raise RuntimeError('Set font_file to a local CJK font to generate the preview.')
    font = ImageFont.truetype(str(font_file), 22)
    title = ImageFont.truetype(str(font_file), 30)
    canvas = Image.new('RGB', (900, 760), '#E7EAF0')
    draw = ImageDraw.Draw(canvas)
    draw.text((28, 20), '心月狐 · Hsin_theme', font=title, fill=NAVY)
    for x, dark in ((24, False), (462, True)):
        bg, ink = ('#171C27', '#FFFFFF') if dark else ('#FFFFFF', NAVY)
        draw.rounded_rectangle((x, 80, x + 414, 694), 20, fill=bg)
        header = ImageOps.fit(Image.open(IMAGES / 'header.png'), (414, 90),
                              Image.Resampling.LANCZOS, centering=(0.5, 0.3))
        canvas.paste(header, (x, 80))
        draw.text((x + 16, 88), '通讯录' if dark else '首页', font=font, fill=NAVY,
                  stroke_width=2, stroke_fill='#FFFFFF')
        draw.text((x + 18, 224), '深色模式' if dark else '浅色模式', font=font, fill=ink)
        for y, text in ((286, '你好呀。'), (402, '很高兴和你聊天。\n今天也要开心哦！')):
            height = 86 if y == 286 else 126
            draw.rounded_rectangle((x + 54, y, x + 388, y + height), 16, fill=NAVY)
            icon = Image.open(IMAGES / 'bubble-leading.png').resize((80, 80))
            canvas.paste(icon, (x + 22, y - 8), icon)
            draw.multiline_text((x + 114, y + 20), text, font=font, fill='white', spacing=8)
        for index, slot in enumerate(('chat', 'contacts', 'discover', 'profile')):
            icon = Image.open(IMAGES / f'nav-{slot}.png').resize((58, 58))
            canvas.paste(icon, (x + 26 + 100 * index, 605), icon)
        draw.ellipse((x + 20, 599, x + 90, 669), outline='#A7B5CF', width=2)
    draw.text((24, 714), '制作预览示意；实际布局由 App 自适应，选中标记沿用原导航。', font=font, fill=NAVY)
    canvas.save(IMAGES / 'preview.png', optimize=True)


if __name__ == '__main__':
    build()
