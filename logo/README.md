# EverAuras artwork

`EVERAURAS.jpg` is the master badge (2048x2048, dark disc on white); `EVERAURAS.png` is a tighter
667x662 crop of it (opaque, not used by the build). `tools/forever_patches.py`
installs the rendered set from `build/` into the addon on every rebuild, replacing upstream's logo
files by name, and points `## IconTexture` at `icon.tga`.

| File (build/) | Size | Used for |
|---|---|---|
| `logo_256_round.tga` | 256x256 RGBA | the badge in the top-left corner of the options window |
| `logo_256.tga`, `logo_64.tga`, `logo_64_nobg.tga` | 256 / 64 | upstream's other logo slots (selectable textures) |
| `icon.tga` | 32x32 RGBA | addon-list icon (`## IconTexture`) |

Re-render after changing the master (Python with Pillow):

```python
from PIL import Image, ImageDraw
src = Image.open("logo/EVERAURAS.jpg").convert("RGBA"); W, H = src.size; S = 4
mask = Image.new("L", (W*S, H*S), 0); r = (min(W, H)//2 - 6)*S
ImageDraw.Draw(mask).ellipse((W*S//2-r, H*S//2-r, W*S//2+r, H*S//2+r), fill=255)
src.putalpha(mask.resize((W, H), Image.LANCZOS))
for name, size in [("logo_256_round.tga",256),("logo_256.tga",256),("logo_64.tga",64),("logo_64_nobg.tga",64),("icon.tga",32)]:
    src.resize((size, size), Image.LANCZOS).save("logo/build/" + name, format="TGA")
```

The original WeakAuras/M33kAuras files are kept next to this README (`logo_*.tga`, `icon.blp`,
`waheart.tga`) for reference; `waheart.tga` (the Thanks button) is still upstream's.
