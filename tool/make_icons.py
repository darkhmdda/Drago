"""Genera todos los iconos de Drago a partir de assets/icon/emblema.png.

Uso: python3 tool/make_icons.py

- Android: icono adaptativo (fondo + emblema dentro de la zona segura, para
  que no se recorte en círculo/gota/cuadrado), icono temático monocromo
  (Android 13+), iconos clásicos por densidad e icono de notificación.
- Web: favicon, iconos 192/512 y versiones «maskable».
"""
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "assets/icon/emblema.png"
BG = (0xF6, 0xD5, 0x8A, 255)  # fondo recomendado #F6D58A
RES = ROOT / "android/app/src/main/res"
DENSITIES = {"mdpi": 1, "hdpi": 1.5, "xhdpi": 2, "xxhdpi": 3, "xxxhdpi": 4}


def emblem() -> Image.Image:
    """Recorta el emblema (ignorando píxeles casi transparentes) a un cuadrado."""
    im = Image.open(SRC).convert("RGBA")
    solid = im.split()[3].point(lambda a: 255 if a > 160 else 0)
    l, t, r, b = solid.getbbox()
    side = max(r - l, b - t)
    cx, cy = (l + r) // 2, (t + b) // 2
    box = (cx - side // 2, cy - side // 2, cx + side // 2, cy + side // 2)
    sq = Image.new("RGBA", (side, side), (0, 0, 0, 0))
    sq.paste(im.crop(box), (0, 0))
    return sq


def place(em: Image.Image, size: int, fraction: float, bg=None) -> Image.Image:
    """Lienzo [size] con el emblema ocupando [fraction] del lado, centrado."""
    canvas = Image.new("RGBA", (size, size), bg or (0, 0, 0, 0))
    d = round(size * fraction)
    e = em.resize((d, d), Image.LANCZOS)
    canvas.alpha_composite(e, ((size - d) // 2, (size - d) // 2))
    return canvas


def silhouette(em: Image.Image) -> Image.Image:
    """Partes doradas en blanco y el resto transparente (notificaciones e icono temático)."""
    px = em.load()
    out = Image.new("RGBA", em.size, (0, 0, 0, 0))
    po = out.load()
    for y in range(em.size[1]):
        for x in range(em.size[0]):
            r, g, b, a = px[x, y]
            if a > 100 and (r + g + b) / 3 > 110:  # dorado (claro), no el marrón
                po[x, y] = (255, 255, 255, a)
    return out


def main():
    em = emblem()
    sil = silhouette(em)

    for name, k in DENSITIES.items():
        d = RES / f"mipmap-{name}"
        d.mkdir(parents=True, exist_ok=True)
        # Icono clásico (Android < 8): cuadrado redondeado lo pone el sistema.
        place(em, round(48 * k), 0.86, BG).save(d / "ic_launcher.png", optimize=True)
        # Capas del icono adaptativo (108dp; zona segura de 66dp → el círculo usa ~60%).
        place(em, round(108 * k), 0.60).save(d / "ic_launcher_foreground.png", optimize=True)
        place(sil, round(108 * k), 0.60).save(d / "ic_launcher_monochrome.png", optimize=True)
        # Icono de notificación (silueta blanca, 24dp).
        n = RES / f"drawable-{name}"
        n.mkdir(parents=True, exist_ok=True)
        place(sil, round(24 * k), 1.0).save(n / "ic_stat_drago.png", optimize=True)

    anydpi = RES / "mipmap-anydpi-v26"
    anydpi.mkdir(parents=True, exist_ok=True)
    (anydpi / "ic_launcher.xml").write_text(
        '<?xml version="1.0" encoding="utf-8"?>\n'
        '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
        '    <background android:drawable="@color/ic_launcher_background"/>\n'
        '    <foreground android:drawable="@mipmap/ic_launcher_foreground"/>\n'
        '    <monochrome android:drawable="@mipmap/ic_launcher_monochrome"/>\n'
        '</adaptive-icon>\n'
    )
    values = RES / "values"
    values.mkdir(parents=True, exist_ok=True)
    (values / "ic_launcher_background.xml").write_text(
        '<?xml version="1.0" encoding="utf-8"?>\n<resources>\n'
        '    <color name="ic_launcher_background">#F6D58A</color>\n'
        '    <color name="notification_accent">#8A5A00</color>\n</resources>\n'
    )

    # Emblema pequeño para usar dentro de la app (pantalla de bloqueo, etc.).
    place(em, 256, 1.0).save(ROOT / "assets/icon/emblema_256.png", optimize=True)

    web = ROOT / "web"
    place(em, 64, 1.0).save(web / "favicon.png", optimize=True)
    for s in (192, 512):
        place(em, s, 0.92, BG).save(web / f"icons/Icon-{s}.png", optimize=True)
        # «maskable»: el sistema puede recortar hasta el 80% central.
        place(em, s, 0.72, BG).save(web / f"icons/Icon-maskable-{s}.png", optimize=True)
    print("Iconos generados.")


if __name__ == "__main__":
    main()
