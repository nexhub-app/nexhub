#!/usr/bin/env python3
"""从 assets/icon/icon.png 生成各平台启动图标。

仅作为开发工具：运行 `flutter pub run flutter_launcher_icons` 也会自动生成
（见 pubspec.yaml 的 flutter_launcher_icons 配置）。本脚本在没有 Flutter 环境的
情况下直接产出 Windows / Android / iOS / Web / macOS / Linux 图标，便于预览与离线构建。
"""
import json
import os

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "assets", "icon", "icon.png")
LIGHT_BLUE = (0x5B, 0x9B, 0xD5, 255)


def load():
    return Image.open(SRC).convert("RGBA")


def square(im, size, bg=None):
    img = im.resize((size, size), Image.LANCZOS)
    if bg is not None:
        canvas = Image.new("RGBA", (size, size), bg)
        canvas = Image.alpha_composite(canvas, img)
        return canvas.convert("RGB")
    return img


def save_png(path, im):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    im.save(path, "PNG")
    print("wrote", os.path.relpath(path, ROOT))


def gen_windows(im):
    sizes = [16, 32, 48, 64, 128, 256]
    out = os.path.join(ROOT, "windows", "runner", "resources")
    os.makedirs(out, exist_ok=True)
    imgs = [im.resize((s, s), Image.LANCZOS) for s in sizes]
    imgs[0].save(os.path.join(out, "app_icon.ico"),
                 sizes=[(s, s) for s in sizes])
    print("wrote windows/runner/resources/app_icon.ico")


def gen_android(im):
    densities = {"mdpi": 48, "hdpi": 72, "xhdpi": 96,
                 "xxhdpi": 144, "xxxhdpi": 192}
    for d, sz in densities.items():
        folder = os.path.join(ROOT, "android", "app", "src", "main",
                              "res", f"mipmap-{d}")
        save_png(os.path.join(folder, "ic_launcher.png"), square(im, sz))
        save_png(os.path.join(folder, "ic_launcher_round.png"), square(im, sz))
    # 自适应图标
    adapt = {"mdpi": 108, "hdpi": 162, "xhdpi": 216,
             "xxhdpi": 324, "xxxhdpi": 432}
    for d, sz in adapt.items():
        folder = os.path.join(ROOT, "android", "app", "src", "main",
                              "res", f"mipmap-{d}")
        save_png(os.path.join(folder, "ic_launcher_background.png"),
                 Image.new("RGBA", (sz, sz), LIGHT_BLUE))
        fg = Image.new("RGBA", (sz, sz), (0, 0, 0, 0))
        inner = int(sz * 0.66)
        logo = im.resize((inner, inner), Image.LANCZOS)
        fg.paste(logo, ((sz - inner) // 2, (sz - inner) // 2), logo)
        save_png(os.path.join(folder, "ic_launcher_foreground.png"), fg)
    anydpi = os.path.join(ROOT, "android", "app", "src", "main",
                          "res", "mipmap-anydpi-v26")
    os.makedirs(anydpi, exist_ok=True)
    xml = ('<?xml version="1.0" encoding="utf-8"?>\n'
           '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
           '    <background android:drawable="@mipmap/ic_launcher_background"/>\n'
           '    <foreground android:drawable="@mipmap/ic_launcher_foreground"/>\n'
           '</adaptive-icon>\n')
    for name in ("ic_launcher.xml", "ic_launcher_round.xml"):
        with open(os.path.join(anydpi, name), "w", encoding="utf-8") as f:
            f.write(xml)
    print("wrote android mipmap icons + adaptive xml")


def gen_appiconset(im, base):
    entries = [
        ("Icon-20@2x.png", 40, "20x20", "2x"),
        ("Icon-20@3x.png", 60, "20x20", "3x"),
        ("Icon-29@2x.png", 58, "29x29", "2x"),
        ("Icon-29@3x.png", 87, "29x29", "3x"),
        ("Icon-40@2x.png", 80, "40x40", "2x"),
        ("Icon-40@3x.png", 120, "40x40", "3x"),
        ("Icon-60@2x.png", 120, "60x60", "2x"),
        ("Icon-60@3x.png", 180, "60x60", "3x"),
        ("Icon-1024.png", 1024, "1024x1024", "1x"),
    ]
    out = os.path.join(ROOT, base, "Assets.xcassets", "AppIcon.appiconset")
    os.makedirs(out, exist_ok=True)
    images = []
    for name, sz, pt, scale in entries:
        save_png(os.path.join(out, name), square(im, sz))
        images.append({"size": pt, "scale": scale,
                       "idiom": "universal", "filename": name})
    contents = {"images": images,
                "info": {"version": 1, "author": "xcode"}}
    with open(os.path.join(out, "Contents.json"), "w", encoding="utf-8") as f:
        json.dump(contents, f, indent=2)
    print("wrote", base, "AppIcon.appiconset")


def gen_web(im):
    out = os.path.join(ROOT, "web", "icons")
    os.makedirs(out, exist_ok=True)
    save_png(os.path.join(out, "Icon-192.png"), square(im, 192))
    save_png(os.path.join(out, "Icon-512.png"), square(im, 512))
    manifest = {
        "name": "nexhub",
        "short_name": "nexhub",
        "start_url": ".",
        "display": "standalone",
        "background_color": "#5B9BD5",
        "theme_color": "#5B9BD5",
        "icons": [
            {"src": "icons/Icon-192.png",
             "sizes": "192x192", "type": "image/png"},
            {"src": "icons/Icon-512.png",
             "sizes": "512x512", "type": "image/png"},
        ],
    }
    with open(os.path.join(ROOT, "web", "manifest.json"), "w",
              encoding="utf-8") as f:
        json.dump(manifest, f, indent=2)
    print("wrote web icons + manifest.json")


def gen_linux(im):
    out = os.path.join(ROOT, "linux", "flutter")
    os.makedirs(out, exist_ok=True)
    save_png(os.path.join(out, "icons.png"), square(im, 512))
    print("wrote linux/flutter/icons.png")


def main():
    im = load()
    gen_windows(im)
    gen_android(im)
    gen_appiconset(im, os.path.join("ios", "Runner"))
    gen_appiconset(im, os.path.join("macos", "Runner"))
    gen_web(im)
    gen_linux(im)
    print("done")


if __name__ == "__main__":
    main()
