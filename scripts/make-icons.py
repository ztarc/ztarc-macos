#!/usr/bin/env python3
"""Generate the ZTARC asset catalog from the committed ZTARC marks.

Driven by scripts/make-icons.sh. Kept in Python because the only work here that
is not a resize is reading a Windows .ico and compositing the app icon, and
doing either in shell would mean a dependency on ImageMagick that nothing else
in this repository needs.

Two limitations, both deliberate and both worth knowing before you look at the
output and wonder:

  * The mark is only 256x256 in the .ico, and a macOS app icon needs 1024x1024.
    The large sizes are upscaled and will look soft. That is still the right
    trade against shipping the upstream vendor's animal as our app icon, but it
    is a placeholder: regenerate from vector art when there is some.

  * The wordmark is 240x60, so the logo imageset is generated at that size for
    @1x and @2x alike. Upstream does exactly the same thing with its own logo,
    so this is not a regression, but it is not right either.
"""

import json
import os
import struct
import subprocess
import sys
import zlib

# The ZTARC ember, measured from icon-orange.ico rather than typed from memory:
# 95.5% of the mark's saturated pixels are exactly this value.
EMBER = (0xE9, 0x5C, 0x2C)
# The app icon's ground, matching the charcoal upstream uses so the icon still
# reads on both a light and a dark Dock.
CHARCOAL = (0x18, 0x18, 0x19)


# ── PNG ───────────────────────────────────────────────────────────────────────

def read_ico(path):
    """Return (size, RGBA bytes) for the largest 32-bit entry of a .ico."""
    data = open(path, "rb").read()
    count = struct.unpack_from("<HHH", data, 0)[2]
    best = None
    for i in range(count):
        w, h, _, _, _, bpp, size, off = struct.unpack_from("<BBBBHHII", data, 6 + i * 16)
        w, h = w or 256, h or 256
        if bpp == 32 and (best is None or w > best[0]):
            best = (w, h, data[off:off + size])
    if best is None:
        sys.exit("no 32-bit entry in %s" % path)
    w, h, blob = best
    header_size = struct.unpack_from("<I", blob, 0)[0]
    px = blob[header_size:]
    # A .ico's DIB stores rows bottom-up, and claims double height because the
    # AND mask follows the colour data. We only want the colour half.
    out = bytearray()
    stride = w * 4
    for y in range(h - 1, -1, -1):
        row = px[y * stride:(y + 1) * stride]
        for x in range(0, stride, 4):
            b, g, r, a = row[x:x + 4]
            out += bytes((r, g, b, a))
    return w, bytes(out)


def write_png(path, width, height, rgba):
    def chunk(tag, payload):
        return (struct.pack(">I", len(payload)) + tag + payload
                + struct.pack(">I", zlib.crc32(tag + payload) & 0xFFFFFFFF))

    raw = bytearray()
    stride = width * 4
    for y in range(height):
        raw.append(0)                       # filter: none
        raw += rgba[y * stride:(y + 1) * stride]
    png = (b"\x89PNG\r\n\x1a\n"
           + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0))
           + chunk(b"IDAT", zlib.compress(bytes(raw), 9))
           + chunk(b"IEND", b""))
    open(path, "wb").write(png)


def resize(src, dst, size):
    subprocess.run(["sips", "-z", str(size), str(size), src, "--out", dst],
                   check=True, capture_output=True)


# ── Pixel operations ──────────────────────────────────────────────────────────

def recolor(rgba, rgb, alpha_scale=1.0):
    """Force every pixel to one colour, keeping (optionally scaled) alpha.

    Menu bar images are template images: macOS throws the colour away and
    redraws the shape in whatever the menu bar needs, so only alpha carries
    information. Flattening the colour makes that explicit rather than leaving
    orange pixels that happen never to be drawn.
    """
    out = bytearray(rgba)
    for i in range(0, len(out), 4):
        out[i:i + 3] = bytes(rgb)
        if alpha_scale != 1.0:
            out[i + 3] = int(out[i + 3] * alpha_scale)
    return bytes(out)


def rounded_square(size, rgb, radius_ratio=0.2237):
    """A filled rounded square. 0.2237 is Apple's squircle-ish corner ratio."""
    r = size * radius_ratio
    out = bytearray(size * size * 4)
    for y in range(size):
        for x in range(size):
            dx = min(x + 0.5, size - x - 0.5)
            dy = min(y + 0.5, size - y - 0.5)
            if dx < r and dy < r:
                inside = ((r - dx) ** 2 + (r - dy) ** 2) <= r * r
            else:
                inside = True
            i = (y * size + x) * 4
            out[i:i + 3] = bytes(rgb)
            out[i + 3] = 255 if inside else 0
    return bytes(out)


def composite(base, top, size, inset):
    """Alpha-composite `top` centred on `base`, scaled to (1 - 2*inset)."""
    out = bytearray(base)
    span = int(size * (1 - 2 * inset))
    off = (size - span) // 2
    for y in range(span):
        sy = int(y * size / span)
        for x in range(span):
            sx = int(x * size / span)
            s = (sy * size + sx) * 4
            a = top[s + 3] / 255.0
            if a == 0:
                continue
            d = ((y + off) * size + (x + off)) * 4
            for c in range(3):
                out[d + c] = int(top[s + c] * a + out[d + c] * (1 - a))
            out[d + 3] = max(out[d + 3], top[s + 3])
    return bytes(out)


# ── Asset catalog ─────────────────────────────────────────────────────────────

def imageset(path, entries, template=False):
    os.makedirs(path, exist_ok=True)
    contents = {
        "images": [{"filename": f, "idiom": "universal", "scale": s}
                   for f, s in entries],
        "info": {"author": "xcode", "version": 1},
    }
    if template:
        contents["properties"] = {"template-rendering-intent": "template"}
    json.dump(contents, open(os.path.join(path, "Contents.json"), "w"), indent=2)


def main(logo_dir, out, work, brand):
    size, mark = read_ico(os.path.join(logo_dir, "icon-orange.ico"))
    master = os.path.join(work, "mark.png")
    write_png(master, size, size, mark)

    json.dump({"info": {"author": "xcode", "version": 1}},
              open(os.path.join(out, "Contents.json"), "w"), indent=2)

    # Accent colour.
    colorset = os.path.join(out, "AccentColor.colorset")
    os.makedirs(colorset, exist_ok=True)
    color = {
        "color-space": "srgb",
        "components": {
            "alpha": "1.000",
            "red": "%.17f" % (EMBER[0] / 255),
            "green": "%.17f" % (EMBER[1] / 255),
            "blue": "%.17f" % (EMBER[2] / 255),
        },
    }
    json.dump({
        "colors": [
            {"color": color, "idiom": "universal"},
            {"appearances": [{"appearance": "luminosity", "value": "dark"}],
             "color": color, "idiom": "universal"},
        ],
        "info": {"author": "xcode", "version": 1},
    }, open(os.path.join(colorset, "Contents.json"), "w"), indent=2)

    # Menu bar images. 22pt at 1x/2x/3x, template-rendered, so alpha is all that
    # survives. Dimmed and the three loading frames differ from the base only in
    # alpha, which is the one channel the template intent keeps — a "dimmed"
    # variant that differed in colour would render identically to the base.
    black = os.path.join(work, "black.png")
    write_png(black, size, size, recolor(mark, (0, 0, 0)))
    menu_variants = [
        ("MenuBarIcon", "menubar-icon", 1.0),
        ("MenuBarIconDimmed", "menubar-icon-dimmed", 0.40),
        ("MenuBarIconLoading1", "menubar-icon-loading1", 0.30),
        ("MenuBarIconLoading2", "menubar-icon-loading2", 0.60),
        ("MenuBarIconLoading3", "menubar-icon-loading3", 0.90),
    ]
    for setname, stem, alpha in menu_variants:
        src = os.path.join(work, "%s.png" % stem)
        write_png(src, size, size, recolor(mark, (0, 0, 0), alpha))
        target = os.path.join(out, "%s.imageset" % setname)
        os.makedirs(target, exist_ok=True)
        entries = []
        for scale, px in (("1x", 22), ("2x", 44), ("3x", 66)):
            name = "%s.png" % stem if scale == "1x" else "%s@%s.png" % (stem, scale)
            resize(src, os.path.join(target, name), px)
            entries.append((name, scale))
        imageset(target, entries, template=True)

    # The full-colour mark, shown during onboarding as "look for this in your
    # menu bar". Not a template image: it is a picture of the menu bar item.
    target = os.path.join(out, "%sMenuBarIcon.imageset" % brand)
    os.makedirs(target, exist_ok=True)
    name = "%sMenuBarIcon.png" % brand
    resize(master, os.path.join(target, name), 192)
    imageset(target, [(name, "1x")])

    # Wordmark. The ZTARC wordmark is ember on transparent and reads on either
    # ground, so light and dark are the same file — as on Windows, where the two
    # wordmark files are byte-identical for the same reason.
    target = os.path.join(out, "%sLogo.imageset" % brand)
    os.makedirs(target, exist_ok=True)
    entries = []
    for appearance in ("light", "dark"):
        for scale in ("1x", "2x"):
            name = "ztarc-logo-%s%s.png" % (
                appearance, "" if scale == "1x" else "@2x")
            subprocess.run(
                ["cp", os.path.join(logo_dir, "word_mark_black.png"),
                 os.path.join(target, name)], check=True)
            entries.append((name, scale, appearance))
    json.dump({
        "images": [
            {"appearances": [{"appearance": "luminosity", "value": a}],
             "filename": f, "idiom": "universal", "scale": s}
            for f, s, a in entries
        ],
        "info": {"author": "xcode", "version": 1},
    }, open(os.path.join(target, "Contents.json"), "w"), indent=2)

    # App icon, as a classic .appiconset rather than an Icon Composer bundle.
    # Upstream ships a .icon, which is Xcode 26 only; generating an .appiconset
    # here drops the toolchain floor to Xcode 16 for work we had to do anyway,
    # and it is the one asset that absolutely cannot keep the upstream artwork.
    target = os.path.join(out, "AppIcon.appiconset")
    os.makedirs(target, exist_ok=True)
    canvas = composite(rounded_square(size, CHARCOAL), mark, size, 0.14)
    iconsrc = os.path.join(work, "appicon.png")
    write_png(iconsrc, size, size, canvas)
    images = []
    for pt in (16, 32, 128, 256, 512):
        for scale, mult in (("1x", 1), ("2x", 2)):
            px = pt * mult
            name = "icon_%dx%d%s.png" % (pt, pt, "" if scale == "1x" else "@2x")
            resize(iconsrc, os.path.join(target, name), px)
            images.append({"filename": name, "idiom": "mac",
                           "scale": scale, "size": "%dx%d" % (pt, pt)})
    json.dump({"images": images, "info": {"author": "xcode", "version": 1}},
              open(os.path.join(target, "Contents.json"), "w"), indent=2)


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4])
