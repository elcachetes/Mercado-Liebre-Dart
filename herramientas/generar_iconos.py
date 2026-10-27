"""Genera todos los iconos de la app a partir de cliente/assets/icono/liebre.svg.

Uso (desde la raíz del repositorio, en Windows con Microsoft Edge):

    pip install pillow
    python herramientas/generar_iconos.py

Edge (modo headless) convierte el SVG a PNG y Pillow produce cada tamaño:
web (favicon, PWA y maskable), Android (mipmaps), iOS (AppIcon),
Windows (app_icon.ico) y el logo dentro de la app (assets/icono/icono.png).

Para cambiar el dibujo edita liebre.svg; para cambiar el fondo, FONDO abajo.
"""
import json
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

from PIL import Image

RAIZ = Path(__file__).resolve().parent.parent
CLIENTE = RAIZ / "cliente"
FUENTE = CLIENTE / "assets" / "icono" / "liebre.svg"
EDGE = [
    Path(r"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe"),
    Path(r"C:\Program Files\Microsoft\Edge\Application\msedge.exe"),
]

# Degradado rojo institucional.
FONDO = """
<defs>
  <linearGradient id="fondo" x1="0" y1="0" x2="0" y2="1">
    <stop offset="0" stop-color="#D7263D"/>
    <stop offset="1" stop-color="#9B0E19"/>
  </linearGradient>
</defs>
"""


def svg(dibujo: str, *, redondeado: bool, escala: float) -> str:
    """Lienzo 1024×1024 con fondo rojo y el dibujo centrado a [escala]."""
    radio = 224 if redondeado else 0
    desplazamiento = 512 * (1 - escala)
    return f"""<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">
{FONDO}
<rect width="1024" height="1024" rx="{radio}" fill="url(#fondo)"/>
<g transform="translate({desplazamiento} {desplazamiento}) scale({escala})">{dibujo}</g>
</svg>"""


def renderizar(codigo_svg: str, destino: Path) -> Image.Image:
    """Dibuja el SVG con Edge y devuelve la imagen RGBA de 1024×1024."""
    edge = next((ruta for ruta in EDGE if ruta.exists()), None)
    if edge is None:
        sys.exit("No se encontró Microsoft Edge.")
    html = destino.with_suffix(".html")
    html.write_text(
        "<!doctype html><html><body style='margin:0;background:transparent'>" + codigo_svg + "</body></html>",
        encoding="utf-8",
    )
    png = destino.with_suffix(".png")
    # Ventana más alta que el lienzo: en modo headless parte de la altura se
    # pierde en la barra del navegador; luego se recorta a 1024×1024.
    subprocess.run(
        [str(edge), "--headless=new", "--disable-gpu", "--hide-scrollbars",
         "--default-background-color=00000000", "--window-size=1024,1300",
         f"--screenshot={png}", html.as_uri()],
        check=True, capture_output=True, timeout=60,
    )
    return Image.open(png).convert("RGBA").crop((0, 0, 1024, 1024))


def guardar(imagen: Image.Image, ruta: Path, lado: int, *, sin_alfa: bool = False) -> None:
    ruta.parent.mkdir(parents=True, exist_ok=True)
    copia = imagen.resize((lado, lado), Image.LANCZOS)
    if sin_alfa:
        fondo = Image.new("RGB", copia.size, (155, 14, 25))
        fondo.paste(copia, mask=copia.split()[3])
        copia = fondo
    copia.save(ruta, optimize=True)
    print(f"  {ruta.relative_to(RAIZ)}  {lado}px")


def main() -> None:
    texto = FUENTE.read_text(encoding="utf-8")
    dibujo = re.search(r"<g[^>]*id=\"dibujo\"[^>]*>.*</g>", texto, re.S).group(0)
    dibujo = dibujo.replace(' xmlns="http://www.w3.org/2000/svg"', "")

    temporal = Path(tempfile.mkdtemp(prefix="iconos_liebre_"))
    try:
        redondo = renderizar(svg(dibujo, redondeado=True, escala=0.92), temporal / "redondo")
        cuadrado = renderizar(svg(dibujo, redondeado=False, escala=0.92), temporal / "cuadrado")
        # Zona segura de "maskable": el contenido debe caber en el 80 % central.
        seguro = renderizar(svg(dibujo, redondeado=False, escala=0.74), temporal / "seguro")
    finally:
        shutil.rmtree(temporal, ignore_errors=True)

    print("App (logo interno):")
    guardar(redondo, CLIENTE / "assets" / "icono" / "icono.png", 512)

    print("Web:")
    guardar(redondo, CLIENTE / "web" / "favicon.png", 48)
    guardar(redondo, CLIENTE / "web" / "icons" / "Icon-192.png", 192)
    guardar(redondo, CLIENTE / "web" / "icons" / "Icon-512.png", 512)
    guardar(seguro, CLIENTE / "web" / "icons" / "Icon-maskable-192.png", 192)
    guardar(seguro, CLIENTE / "web" / "icons" / "Icon-maskable-512.png", 512)

    print("Android:")
    for carpeta, lado in {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}.items():
        guardar(redondo, CLIENTE / "android" / "app" / "src" / "main" / "res" / f"mipmap-{carpeta}" / "ic_launcher.png", lado)

    print("iOS (cuadrado: iOS aplica su propia máscara):")
    conjunto = CLIENTE / "ios" / "Runner" / "Assets.xcassets" / "AppIcon.appiconset"
    for imagen in json.loads((conjunto / "Contents.json").read_text())["images"]:
        lado = round(float(imagen["size"].split("x")[0]) * int(imagen["scale"].rstrip("x")))
        guardar(cuadrado, conjunto / imagen["filename"], lado, sin_alfa=True)

    print("Windows:")
    ico = CLIENTE / "windows" / "runner" / "resources" / "app_icon.ico"
    redondo.resize((256, 256), Image.LANCZOS).save(
        ico, sizes=[(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)])
    print(f"  {ico.relative_to(RAIZ)}  16–256px")


if __name__ == "__main__":
    main()
