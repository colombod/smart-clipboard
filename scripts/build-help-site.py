#!/usr/bin/env python3
"""Build the static GitHub Pages help bundle. Requires Pandoc; never publishes.

Example:
  uv run --no-project python scripts/build-help-site.py --ref v0.4.0-preview.15 \
      --output /private/tmp/smart-clipboard-deploy/help-site

README.md, docs/USER-GUIDE.md and their docs/locales translations are the content
sources. Other repository links are pinned to --ref, which must exist when the
site is published.
"""

import argparse
import hashlib
import html
import json
import posixpath
import re
import shutil
import subprocess
import tempfile
from html.parser import HTMLParser
from pathlib import Path
from urllib.parse import quote, unquote, urlsplit

ROOT = Path(__file__).resolve().parent.parent
REPOSITORY = "https://github.com/colombod/smart-clipboard"
ICON = ROOT / "docs/app-icon.png"
PAGES = {ROOT / "README.md": "index.html", ROOT / "docs/USER-GUIDE.md": "guide.html"}
LANGUAGE_NAMES = {"en": "English", "es": "Español", "it": "Italiano", "fr": "Français", "de": "Deutsch"}
for language in LANGUAGE_NAMES:
    if language != "en":
        PAGES[ROOT / "docs/locales" / language / "README.md"] = language + "/index.html"
        PAGES[ROOT / "docs/locales" / language / "USER-GUIDE.md"] = language + "/guide.html"
CHROME = {
    "en": {"home_title": "Smart Clipboard — Capture, convert, paste", "guide_title": "Setup and usage guide — Smart Clipboard",
           "description": "Set up Smart Clipboard on your Mac, choose local or cloud image processing, and capture directly to your clipboard.",
           "skip": "Skip to content", "main": "Main navigation", "start": "Get started", "guide": "Setup guide", "downloads": "Downloads",
           "toc": "On this page", "language": "Language", "product": "Smart Clipboard for Mac", "problem": "Report a problem", "source": "Source and development"},
    "es": {"home_title": "Smart Clipboard — Captura, convierte y pega", "guide_title": "Guía de configuración y uso — Smart Clipboard",
           "description": "Configura Smart Clipboard en tu Mac, elige el procesamiento local o en la nube y envía las capturas directamente al portapapeles.",
           "skip": "Ir al contenido", "main": "Navegación principal", "start": "Primeros pasos", "guide": "Guía de uso", "downloads": "Descargas",
           "toc": "En esta página", "language": "Idioma", "product": "Smart Clipboard para Mac", "problem": "Informar de un problema", "source": "Código y desarrollo"},
    "it": {"home_title": "Smart Clipboard — Acquisisci, converti e incolla", "guide_title": "Guida alla configurazione e all’uso — Smart Clipboard",
           "description": "Configura Smart Clipboard sul Mac, scegli l’elaborazione locale o nel cloud e copia le acquisizioni direttamente negli appunti.",
           "skip": "Vai al contenuto", "main": "Navigazione principale", "start": "Per iniziare", "guide": "Guida all’uso", "downloads": "Download",
           "toc": "In questa pagina", "language": "Lingua", "product": "Smart Clipboard per Mac", "problem": "Segnala un problema", "source": "Codice sorgente e sviluppo"},
    "fr": {"home_title": "Smart Clipboard — Capturez, convertissez, collez", "guide_title": "Guide de configuration et d’utilisation — Smart Clipboard",
           "description": "Configurez Smart Clipboard sur votre Mac, choisissez le traitement local ou dans le cloud et envoyez vos captures directement dans le presse-papiers.",
           "skip": "Aller au contenu", "main": "Navigation principale", "start": "Premiers pas", "guide": "Guide d’utilisation", "downloads": "Téléchargements",
           "toc": "Sur cette page", "language": "Langue", "product": "Smart Clipboard pour Mac", "problem": "Signaler un problème", "source": "Code source et développement"},
    "de": {"home_title": "Smart Clipboard — Erfassen, umwandeln, einfügen", "guide_title": "Anleitung zur Einrichtung und Verwendung — Smart Clipboard",
           "description": "Richte Smart Clipboard auf deinem Mac ein, wähle die lokale Verarbeitung oder einen Cloud-Dienst und kopiere Aufnahmen direkt in die Zwischenablage.",
           "skip": "Zum Inhalt", "main": "Hauptnavigation", "start": "Erste Schritte", "guide": "Anleitung", "downloads": "Downloads",
           "toc": "Auf dieser Seite", "language": "Sprache", "product": "Smart Clipboard für Mac", "problem": "Problem melden", "source": "Quellcode und Entwicklung"},
}
SCREENSHOT_NAMES = {"capture-settings.png", "local-connection.png", "svg-tracing.png", "history.png", "result.png"}
DEMO_LINKS = {"https://colombod.github.io/smart-clipboard/demo.gif": "demo.gif",
              "https://colombod.github.io/smart-clipboard/demo.mp4": "demo.mp4"}

CSS = """
:root { color-scheme: light dark; --background:#f3f7f4; --surface:#ffffff; --text:#17261c;
  --muted:#506358; --line:#cbd9ce; --accent:#146436; --button:#17663a; --button-text:#ffffff;
  --code:#edf3ef; --shadow:0 14px 48px #1833230a; }
@media (prefers-color-scheme:dark) { :root { --background:#101a13; --surface:#18251c;
  --text:#e8f3eb; --muted:#b6c9bc; --line:#395443; --accent:#8cdfaa; --button:#8cdfaa;
  --button-text:#102218; --code:#21352a; --shadow:none; } }
* { box-sizing:border-box; }
html { scroll-padding-top:2rem; }
body { margin:0; color:var(--text); background:var(--background);
  font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif; line-height:1.7; font-size:17px; }
a { color:var(--accent); text-underline-offset:.2em; text-decoration-thickness:.08em; }
a:hover { text-decoration-thickness:.15em; }
a:focus-visible,summary:focus-visible { outline:3px solid var(--accent); outline-offset:5px; border-radius:3px; }
.skip { position:absolute; left:1rem; top:-10rem; padding:.7rem 1rem; z-index:2; background:var(--surface); }
.skip:focus { top:1rem; }
.site-header { max-width:1240px; margin:auto; padding:1.6rem 2rem; display:flex;
  align-items:center; gap:1.4rem; flex-wrap:wrap; }
.brand { display:flex; align-items:center; gap:.65rem; font-weight:750; font-size:1.05rem;
  color:var(--text); text-decoration:none; margin-right:auto; }
.brand img { width:42px; height:42px; border-radius:11px; }
.site-header nav { display:flex; gap:1.4rem; flex-wrap:wrap; font-size:.93rem; }
.site-header .language-nav { flex-basis:100%; gap:.5rem 1rem; font-size:.85rem; }
.language-nav span { color:var(--muted); }
[aria-current=page] { font-weight:750; color:var(--text); }
.layout { display:grid; grid-template-columns:230px minmax(0,1fr); gap:2rem;
  max-width:1240px; margin:1rem auto 4rem; padding:0 2rem; align-items:start; }
.toc { position:sticky; top:2rem; font-size:.88rem; max-height:calc(100vh - 4rem); overflow:auto; }
.toc summary { font-weight:700; margin-bottom:.7rem; cursor:pointer; color:var(--text); }
.toc ul { margin:0; padding:0 0 0 1rem; list-style:none; }
.toc li { margin:.55rem 0; }
.toc a { color:var(--muted); text-decoration:none; }
.toc a:hover { color:var(--accent); text-decoration:underline; }
main { min-width:0; background:var(--surface); border:1px solid var(--line); border-radius:22px;
  box-shadow:var(--shadow); padding:clamp(1.5rem,4vw,3.5rem); }
h1,h2,h3 { line-height:1.2; letter-spacing:-.025em; scroll-margin-top:2rem; }
h1 { font-size:clamp(2.3rem,5vw,3.8rem); margin:0 0 1.5rem; }
h2 { font-size:1.7rem; margin:2.7rem 0 1rem; padding-top:1rem; border-top:1px solid var(--line); }
h3 { font-size:1.25rem; margin:1.8rem 0 .8rem; }
p { margin:1rem 0; }
main > p:first-of-type { color:var(--muted); font-size:1.1rem; }
main img { max-width:100%; height:auto; }
figure.screenshot { margin:1.5rem 0 2rem; }
main img[src*="assets/screenshots/"] { display:block; width:auto; max-width:100%; max-height:660px;
  margin:auto; border:1px solid var(--line); border-radius:12px; box-shadow:var(--shadow); }
figure.screenshot > a { display:block; border-radius:12px; }
figure.screenshot figcaption { color:var(--muted); font-size:.9rem; line-height:1.5; margin:.65rem 0 0; }
figure.screenshot figcaption p { margin:0; }
.home main img[src$="assets/app-icon.png"] { width:100px; border-radius:24px; }
.home main img[src$="demo-poster.png"] { width:100%; border:1px solid var(--line); border-radius:12px; }
.download { display:inline-block; padding:.4rem .8rem; background:var(--button);
  color:var(--button-text); text-decoration:none; border-radius:8px; font-weight:700; }
.download:hover { text-decoration:underline; }
ul,ol { padding-left:1.4rem; }
li { margin:.45rem 0; }
table { display:block; overflow-x:auto; width:100%; border-collapse:collapse; margin:1.4rem 0;
  font-size:.91rem; }
th,td { text-align:left; vertical-align:top; padding:.85rem .9rem; border:1px solid var(--line); }
th { background:var(--code); font-weight:700; }
code { background:var(--code); border-radius:4px; padding:.1em .3em; font-size:.86em;
  overflow-wrap:anywhere; font-family:ui-monospace,SFMono-Regular,Menlo,monospace; }
pre { background:var(--code); padding:1rem; border-radius:9px; overflow:auto; }
pre code { padding:0; overflow-wrap:normal; }
blockquote { border-left:4px solid var(--accent); padding:.2rem 1rem; margin:1.5rem 0; color:var(--muted); }
hr { border:0; border-top:1px solid var(--line); margin:2rem 0; }
.site-footer { max-width:1240px; margin:auto; padding:0 2rem 2.5rem; color:var(--muted); font-size:.87rem; }
@media (max-width:920px) { .layout { grid-template-columns:1fr; gap:1.2rem; }
  .toc { position:static; max-height:none; } .toc ul { columns:2; column-gap:1.4rem; }
  .toc li { break-inside:avoid; } }
@media (max-width:560px) { body { font-size:16px; } .site-header { padding:1rem; gap:.9rem; }
  .site-header nav { gap:1rem; } .layout { padding:0 .8rem; margin-top:.5rem; }
  main { border-radius:15px; padding:1.35rem; } .toc { padding:.4rem .6rem; }
  .toc ul { columns:1; } th,td { padding:.65rem; } .site-footer { padding:0 1.2rem 2rem; } }
@media print { body,main { background:white; color:black; } .site-header,.toc,.site-footer,.skip { display:none; }
  .layout { display:block; padding:0; margin:0; } main { border:0; padding:0; box-shadow:none; } }
"""


def page_language(filename):
    return filename.split("/", 1)[0] if "/" in filename else "en"


def translated_page(language, filename):
    return filename if language == "en" else language + "/" + filename


def relative_link(filename, target):
    return posixpath.relpath(target, posixpath.dirname(filename) or ".")


class PageHTML(HTMLParser):
    def __init__(self, source, revision, media, screenshots):
        super().__init__(convert_charrefs=False)
        self.source, self.revision = source, revision
        self.parts, self.headings = [], []
        self.heading = None
        self.media = media
        self.screenshots = screenshots
        self.filename = PAGES[source]
        self.language = page_language(self.filename)

    def target(self, value, resource=False):
        if value in DEMO_LINKS:
            filename = DEMO_LINKS[value]
            if filename not in self.media:
                raise ValueError(f"Missing recorded media: {filename}; supply --demo-directory or explicit media paths")
            # A static frame makes motion opt-in for everyone, including reduced-motion users.
            target = "demo-poster.png" if resource and filename == "demo.gif" else filename
            return relative_link(self.filename, target)
        url = urlsplit(value)
        if url.scheme or url.netloc:
            if resource:
                raise ValueError("External runtime resources are not permitted")
            if url.scheme not in {"https", "http", "mailto"}:
                raise ValueError(f"Unsupported link scheme: {url.scheme}")
            return value
        if not url.path:
            return value
        path = (self.source.parent / unquote(url.path)).resolve()
        if not path.is_relative_to(ROOT) or not path.is_file():
            raise ValueError(f"Missing or unsafe local reference in {self.source.name}: {value}")
        suffix = ("?" + url.query if url.query else "") + ("#" + url.fragment if url.fragment else "")
        if path == ICON:
            return relative_link(self.filename, "assets/app-icon.png") + suffix
        if path.parent == ROOT / "docs/images" and path.name in SCREENSHOT_NAMES:
            with path.open("rb") as stream:
                if stream.read(8) != b"\x89PNG\r\n\x1a\n":
                    raise ValueError(f"Screenshot has an unexpected file signature: {path.name}")
            asset = "assets/screenshots/" + path.name
            self.screenshots[asset] = path
            return relative_link(self.filename, asset) + suffix
        if resource:
            raise ValueError("Only the local app icon and approved docs/images PNG screenshots are permitted page resources")
        if path in PAGES:
            target = PAGES[path]
            # Links to the English source pages stay in the reader's language.
            # Explicit links to another translation keep that chosen language.
            if page_language(target) == "en":
                equivalent = translated_page(self.language, target)
                if equivalent in PAGES.values():
                    target = equivalent
            return relative_link(self.filename, target) + suffix
        return REPOSITORY + "/blob/" + quote(self.revision, safe="") + "/" + quote(str(path.relative_to(ROOT)), safe="/") + suffix

    def handle_starttag(self, tag, attrs):
        if tag in {"script", "iframe", "object", "embed", "style", "link", "base"}:
            raise ValueError(f"Unsupported active content in source Markdown: {tag}")
        rewritten = []
        for key, value in attrs:
            if key.startswith("on") or key in {"srcset", "style"}:
                raise ValueError(f"Unsupported active attribute: {key}")
            if key == "href":
                value = self.target(value)
            elif key == "src":
                value = self.target(value, resource=True)
            rewritten.append((key, value))
        if tag == "a" and dict(rewritten).get("href") == REPOSITORY + "/releases":
            rewritten.append(("class", "download"))
        attributes = "".join(" " + key + ("=\"" + html.escape(value, quote=True) + "\"" if value is not None else "") for key, value in rewritten)
        self.parts.append("<" + tag + attributes + ">")
        if tag == "h2":
            self.heading = [dict(rewritten).get("id", ""), []]

    def handle_startendtag(self, tag, attrs):
        self.handle_starttag(tag, attrs)

    def handle_endtag(self, tag):
        self.parts.append("</" + tag + ">")
        if tag == "h2" and self.heading is not None:
            self.headings.append((self.heading[0], "".join(self.heading[1])))
            self.heading = None

    def handle_data(self, data):
        self.parts.append(data)
        if self.heading is not None:
            self.heading[1].append(data)

    def handle_entityref(self, name):
        self.parts.append("&" + name + ";")
        if self.heading is not None:
            self.heading[1].append(html.unescape("&" + name + ";"))

    def handle_charref(self, name):
        self.parts.append("&#" + name + ";")
        if self.heading is not None:
            self.heading[1].append(html.unescape("&#" + name + ";"))

    def handle_comment(self, data):
        self.parts.append("<!--" + data + "-->")


def has_demo_link(value):
    if isinstance(value, dict):
        if value.get("t") in {"Link", "Image"} and value["c"][-1][0] in DEMO_LINKS:
            return True
        return any(has_demo_link(v) for v in value.values())
    return isinstance(value, list) and any(has_demo_link(v) for v in value)


def screenshot_figures(blocks):
    """Give GitHub-compatible linked screenshots native figure/caption markup."""
    rendered = []
    index = 0
    while index < len(blocks):
        block = blocks[index]
        inlines = block.get("c", []) if block.get("t") == "Para" else []
        image = inlines[0] if len(inlines) == 1 else None
        if image and image.get("t") == "Link":
            children = image["c"][1]
            child = children[0] if len(children) == 1 else None
            image = child if child and child.get("t") == "Image" and child["c"][-1][0] == image["c"][-1][0] else None
        if image and image.get("t") == "Image" and Path(unquote(urlsplit(image["c"][-1][0]).path)).name in SCREENSHOT_NAMES:
            caption = image["c"][1]
            if index + 1 < len(blocks):
                following = blocks[index + 1]
                if following.get("t") == "Para" and len(following["c"]) == 1 and following["c"][0].get("t") == "Emph":
                    caption = following["c"][0]["c"]
                    index += 1
            rendered.append({"t": "Figure", "c": [["", ["screenshot"], []],
                             [None, [{"t": "Plain", "c": caption}]], [{"t": "Plain", "c": inlines}]]})
        else:
            rendered.append(block)
        index += 1
    return rendered


def page(source, filename, revision, pandoc, media, omit_demo, screenshots):
    ast = json.loads(subprocess.run([pandoc, "--from=gfm", "--to=json", str(source)],
                                  check=True, capture_output=True, text=True).stdout)
    if omit_demo:
        ast["blocks"] = [block for block in ast["blocks"] if not has_demo_link(block)]
    ast["blocks"] = screenshot_figures(ast["blocks"])
    rendered = subprocess.run([pandoc, "--from=json", "--to=html5", "--wrap=none"],
                              input=json.dumps(ast), check=True, capture_output=True, text=True).stdout
    parsed = PageHTML(source, revision, media, screenshots)
    parsed.feed(rendered)
    parsed.close()
    home = posixpath.basename(filename) == "index.html"
    language = page_language(filename)
    chrome = {key: html.escape(value, quote=True) for key, value in CHROME[language].items()}
    title = chrome["home_title" if home else "guide_title"]
    icon = relative_link(filename, "assets/app-icon.png")
    stylesheet = relative_link(filename, "assets/style.css")
    start = relative_link(filename, translated_page(language, "index.html"))
    guide = relative_link(filename, translated_page(language, "guide.html"))
    language_links = []
    for code, name in LANGUAGE_NAMES.items():
        target = translated_page(code, posixpath.basename(filename))
        if target in PAGES.values():
            current = ' aria-current="page"' if code == language else ''
            language_links.append(f'<a href="{relative_link(filename, target)}" lang="{code}" hreflang="{code}"{current}>{name}</a>')
    languages = f'<nav class="language-nav" aria-label="{chrome["language"]}"><span>{chrome["language"]}:</span>{"".join(language_links)}</nav>' if len(language_links) > 1 else ""
    toc = "".join(f'<li><a href="#{html.escape(anchor, quote=True)}">{html.escape(label)}</a></li>' for anchor, label in parsed.headings if anchor)
    body = "".join(parsed.parts)
    return f'''<!doctype html>
<html lang="{language}"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<meta name="color-scheme" content="light dark">
<meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'self'; img-src 'self'; media-src 'self'; base-uri 'none'; form-action 'none'">
<meta name="description" content="{chrome['description']}">
<title>{title}</title><link rel="icon" type="image/png" href="{icon}"><link rel="stylesheet" href="{stylesheet}"></head>
<body class="{'home' if home else 'guide'}"><a class="skip" href="#main">{chrome['skip']}</a>
<header class="site-header"><a class="brand" href="{start}"><img src="{icon}" alt="" width="42" height="42">Smart Clipboard</a>
<nav aria-label="{chrome['main']}"><a href="{start}"{' aria-current="page"' if home else ''}>{chrome['start']}</a><a href="{guide}"{' aria-current="page"' if not home else ''}>{chrome['guide']}</a><a href="{REPOSITORY}/releases">{chrome['downloads']}</a></nav>{languages}</header>
<div class="layout"><nav class="toc" aria-label="{chrome['toc']}"><details open><summary>{chrome['toc']}</summary><ul>{toc}</ul></details></nav>
<main id="main" tabindex="-1">{body}</main></div>
<footer class="site-footer">{chrome['product']} · <a href="{REPOSITORY}/issues/new">{chrome['problem']}</a> · <a href="{REPOSITORY}">{chrome['source']}</a></footer>
</body></html>
'''


class Links(HTMLParser):
    def __init__(self, content):
        super().__init__()
        self.ids, self.links, self.resources = set(), [], []
        self.feed(content)

    def handle_starttag(self, tag, attributes):
        attrs = dict(attributes)
        if "id" in attrs:
            self.ids.add(attrs["id"])
        if tag == "a" and "href" in attrs:
            self.links.append(attrs["href"])
        if "src" in attrs:
            self.resources.append(attrs["src"])
        if tag == "link" and "href" in attrs:
            self.resources.append(attrs["href"])


def local_target(filename, value):
    url = urlsplit(value)
    path = unquote(url.path)
    if url.scheme or url.netloc or path.startswith("/") or "\\" in path:
        raise ValueError(f"Unsafe local help reference from {filename}: {value}")
    target = posixpath.normpath(posixpath.join(posixpath.dirname(filename), path)) if path else filename
    if target == ".." or target.startswith("../"):
        raise ValueError(f"Help reference escapes the site from {filename}: {value}")
    return target, unquote(url.fragment)


def validate_local_links(documents, assets):
    inventory = {filename: Links(content) for filename, content in documents.items()}
    for filename, links in inventory.items():
        for target in links.links:
            url = urlsplit(target)
            if url.scheme or url.netloc:
                continue
            page_name, fragment = local_target(filename, target)
            if page_name in assets and not fragment:
                continue
            if page_name not in inventory or (fragment and fragment not in inventory[page_name].ids):
                raise ValueError(f"Broken help link from {filename}: {target}")
        for resource in links.resources:
            target, fragment = local_target(filename, resource)
            if target not in assets or fragment:
                raise ValueError(f"Missing or external runtime resource in {filename}: {resource}")


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--ref", required=True, help="Git tag or commit for linked repository documents")
    parser.add_argument("--output", required=True, type=Path, help="Staging directory; existing appcast files are preserved")
    parser.add_argument("--demo-directory", type=Path, help="Directory containing recorded demo.gif, demo.mp4 and optionally demo-poster.png")
    parser.add_argument("--demo-gif", type=Path, help="Existing recorded GIF; copied locally, never fetched")
    parser.add_argument("--demo-video", type=Path, help="Existing recorded MP4; copied locally, never fetched")
    parser.add_argument("--demo-poster", type=Path, help="Existing PNG frame from the recording; otherwise ffmpeg extracts its first video frame")
    parser.add_argument("--omit-demo", action="store_true", help="Draft only: omit Markdown demo paragraphs until recordings are available")
    args = parser.parse_args()
    if not re.fullmatch(r"[A-Za-z0-9._/-]+", args.ref) or ".." in args.ref:
        parser.error("--ref must be a tag, commit or simple branch name")
    pandoc = shutil.which("pandoc")
    if not pandoc:
        parser.error("Pandoc is required to render Markdown; no dependencies are installed automatically")
    output = args.output.resolve()
    if output == ROOT or output in [p.parent for p in PAGES]:
        parser.error("Choose a separate staging directory")
    media = {}
    if not args.omit_demo:
        for filename, explicit in [("demo.gif", args.demo_gif), ("demo.mp4", args.demo_video), ("demo-poster.png", args.demo_poster)]:
            candidate = explicit or (args.demo_directory / filename if args.demo_directory else None)
            if explicit and not explicit.is_file():
                parser.error(f"Recorded media does not exist: {explicit}")
            if candidate and candidate.is_file():
                with candidate.open("rb") as stream:
                    header = stream.read(16)
                valid = (header[:6] in {b"GIF87a", b"GIF89a"} if filename == "demo.gif" else
                         header[4:8] == b"ftyp" if filename == "demo.mp4" else
                         header.startswith(b"\x89PNG\r\n\x1a\n"))
                if not valid:
                    parser.error(f"Recorded media has an unexpected file signature: {candidate}")
                media[filename] = candidate.resolve()
        if media and "demo-poster.png" not in media:
            if "demo.mp4" not in media or not shutil.which("ffmpeg"):
                parser.error("Supply --demo-poster, or provide demo.mp4 with ffmpeg installed to extract a real frame")
            with tempfile.TemporaryDirectory(prefix="smart-clipboard-help-") as temp:
                poster = Path(temp) / "demo-poster.png"
                subprocess.run(["ffmpeg", "-loglevel", "error", "-i", str(media["demo.mp4"]), "-frames:v", "1", str(poster)], check=True)
                poster_bytes = poster.read_bytes()
        else:
            poster_bytes = media["demo-poster.png"].read_bytes() if "demo-poster.png" in media else None
        if media and poster_bytes:
            media.setdefault("demo-poster.png", None)
    else:
        poster_bytes = None
    screenshots = {}
    documents = {filename: page(source, filename, args.ref, pandoc, media, args.omit_demo, screenshots) for source, filename in PAGES.items()}
    validate_local_links(documents, {"assets/app-icon.png", "assets/style.css", *media, *screenshots})
    (output / "assets").mkdir(parents=True, exist_ok=True)
    for filename, content in documents.items():
        destination = output / filename
        destination.parent.mkdir(parents=True, exist_ok=True)
        destination.write_text(content)
    (output / "assets/style.css").write_text(CSS.strip() + "\n")
    shutil.copyfile(ICON, output / "assets/app-icon.png")
    for asset, source in screenshots.items():
        destination = output / asset
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(source, destination)
    for filename, path in media.items():
        if filename == "demo-poster.png":
            (output / filename).write_bytes(poster_bytes)
        elif path != (output / filename).resolve():
            shutil.copyfile(path, output / filename)
    (output / ".nojekyll").touch()
    manifest = {"sourceRef": args.ref, "sources": {str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest() for p in [*PAGES, ICON, *screenshots.values()]}}
    manifest["draftWithoutDemo"] = args.omit_demo
    manifest["languages"] = [code for code in LANGUAGE_NAMES if translated_page(code, "index.html") in PAGES.values()]
    if screenshots:
        manifest["screenshots"] = {asset: hashlib.sha256((output / asset).read_bytes()).hexdigest() for asset in screenshots}
    if media:
        manifest["media"] = {filename: hashlib.sha256((output / filename).read_bytes()).hexdigest() for filename in media}
    (output / "help-build.json").write_text(json.dumps(manifest, indent=2) + "\n")
    print(f"Built {len(documents)} help pages at {output}; no publication performed.")


if __name__ == "__main__":
    main()
