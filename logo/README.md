# ForeverAuras logo files

Originals copied from the addon. TGA opens directly in Photoshop, GIMP, Paint.NET and Krita.
PNG copies are here only so they can be previewed in chat; edit the TGA or export back to TGA.

| File | Size | Format | Where it shows up |
|---|---|---|---|
| `logo_256_round.tga` | 256x256 | 32-bit RGBA, transparent | **The round badge in the top-left corner of the options window.** The main one to redesign. |
| `logo_256.tga` | 256x256 | 24-bit RGB, no alpha | Square version, selectable as an aura texture |
| `logo_64.tga` | 64x64 | 24-bit RGB | Small square version |
| `logo_64_nobg.tga` | 64x64 | 32-bit RGBA, transparent | Small version without background |
| `icon.blp` | 32x32 | BLP2, DXT5 | Addon-list icon (`## IconTexture` in the TOC) |
| `waheart.tga` | 80x80 | 32-bit RGBA | The heart on the "Thanks" button |

## Putting a new logo back in

1. Export as **32-bit TGA with alpha**, uncompressed or RLE, same pixel size as the original.
2. Drop it into
   `D:\World of Warcraft\World of Warcraft\_classic_beta_\Interface\AddOns\ForeverAuras\Media\Textures\`
3. `/reload` in game.

Keep the dimensions a power of two (32, 64, 128, 256). WoW silently refuses textures that are not.

For the addon-list icon you do **not** need BLP: WoW accepts TGA there too. Save it as
`icon.tga` and point the TOC at it:

```
## IconTexture: Interface\AddOns\ForeverAuras\Media\Textures\icon.tga
```

## Making it survive a rebuild

`tools/rebuild_foreverauras.sh` wipes the addon folder and reinstalls from upstream, which
would overwrite a hand-placed logo. Once the new art is final, keep the master copies in this
folder and add a copy step to the build script so branding is re-applied automatically, the
same way the rename is.
