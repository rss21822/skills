#!/usr/bin/env python3
"""Lint a motif skin spec and render it as a style board before any Luau is written.

  python skin_preview.py spec.json --html board.html [--png board.png] [--luau MotifSpec.luau] [--strict]

* Lint: generic-navy dashboard colours, contrast of type on every fill, fonts that Roblox does not
  ship, Latin-only display fonts, palette variety. Errors make --strict exit 1.
* --html: a style board (palette + contrast, buttons, panel with ribbon, dock tiles, mode card,
  banner, mascot) drawn with the Google Fonts equivalents of the Roblox families.
* --png: screenshot of the board through headless Chrome / Edge (when one is installed).
* --luau: the spec as a Luau module for assets/MotifSkinKit.luau (one source of truth).

The spec format is documented in references/spec-format.md (example: assets/skin-spec.example.json).
"""
import argparse
import colorsys
import html
import json
import os
import shutil
import subprocess
import sys
from pathlib import Path

# Families verified in Roblox Studio (2026-09, TextService probe). Everything else silently falls
# back to the default face, so a typo or a web-only font ("Lobster", "Poppins") is an error.
ROBLOX_FAMILIES = {
    "AccanthisADFStd", "AmaticSC", "Arial", "Arimo", "Balthazar", "Bangers", "BuilderSans",
    "ComicNeueAngular", "Creepster", "DenkOne", "Fondamento", "FredokaOne", "GothamSSm",
    "GrenzeGotisch", "Guru", "HighwayGothic", "Inconsolata", "IndieFlower", "JosefinSans", "Jura",
    "Kalam", "LegacyArial", "LuckiestGuy", "Merriweather", "Michroma", "Montserrat", "Nunito",
    "Oswald", "PatrickHand", "PermanentMarker", "PressStart2P", "Roboto", "RobotoCondensed",
    "RobotoMono", "RomanAntique", "Sarpanch", "SourceSansPro", "SpecialElite", "TitilliumWeb",
    "Ubuntu", "Zekton",
}
# Chunky/decorative display faces: fine for Latin callouts, but Japanese in them falls back to the
# plain system font next to the stylised Latin, which looks broken. Mark their roles latinOnly.
DISPLAY_ONLY = {"LuckiestGuy", "Bangers", "Creepster", "PermanentMarker", "AmaticSC", "PressStart2P",
                "GrenzeGotisch", "Fondamento", "Michroma", "Sarpanch", "Zekton", "SpecialElite"}
WEIGHTS = {"Thin", "ExtraLight", "Light", "Regular", "Medium", "SemiBold", "Bold", "ExtraBold", "Heavy"}
CSS_WEIGHT = {"Thin": 100, "ExtraLight": 200, "Light": 300, "Regular": 400, "Medium": 500,
              "SemiBold": 600, "Bold": 700, "ExtraBold": 800, "Heavy": 900}
# Closest Google Fonts face for the board (preview only).
CSS_FAMILY = {
    "LuckiestGuy": "Luckiest Guy", "FredokaOne": "Fredoka One", "Nunito": "Nunito", "Bangers": "Bangers",
    "Creepster": "Creepster", "DenkOne": "Denk One", "Fondamento": "Fondamento", "GrenzeGotisch": "Grenze Gotisch",
    "IndieFlower": "Indie Flower", "JosefinSans": "Josefin Sans", "Jura": "Jura", "Kalam": "Kalam",
    "Merriweather": "Merriweather", "Michroma": "Michroma", "Oswald": "Oswald", "PatrickHand": "Patrick Hand",
    "PermanentMarker": "Permanent Marker", "Roboto": "Roboto", "RobotoCondensed": "Roboto Condensed",
    "RobotoMono": "Roboto Mono", "Sarpanch": "Sarpanch", "SpecialElite": "Special Elite",
    "TitilliumWeb": "Titillium Web", "Ubuntu": "Ubuntu", "Montserrat": "Montserrat", "AmaticSC": "Amatic SC",
    "PressStart2P": "Press Start 2P", "Arimo": "Arimo", "Inconsolata": "Inconsolata", "Balthazar": "Balthazar",
    "ComicNeueAngular": "Comic Neue", "SourceSansPro": "Source Sans 3", "GothamSSm": "Montserrat",
    "BuilderSans": "Inter", "Zekton": "Orbitron", "HighwayGothic": "Overpass", "Guru": "EB Garamond",
    "AccanthisADFStd": "Libre Bodoni", "RomanAntique": "Cinzel", "Arial": "Arimo", "LegacyArial": "Arimo",
}
CJK_CSS = '"M PLUS Rounded 1c","Noto Sans JP","Yu Gothic UI",sans-serif' 


# Roblox's colour emoji font stops at Unicode 12: newer emoji render as a tofu box (verified in Studio
# 2026-09: coin, magic wand, bubbles, jellyfish, folding fan, bubble tea, coral were boxes; kite (12) drew).
_UNICODE12_IN_EXT_A = set(range(0x1FA70, 0x1FA74)) | set(range(0x1FA78, 0x1FA7B)) | set(range(0x1FA80, 0x1FA83)) | set(range(0x1FA90, 0x1FA96))
_NEWER_ELSEWHERE = {0x1F972, 0x1F977, 0x1F978, 0x1F979, 0x1F90C, 0x1F9A3, 0x1F9A4, 0x1F9AB, 0x1F9AC, 0x1F9AD, 0x1F9CB,
                    0x1F9CC, 0x1F6D6, 0x1F6D7, 0x1F6DC, 0x1F6DD, 0x1F6DE, 0x1F6DF, 0x1F6FB, 0x1F6FC, 0x1F7F0}


def emoji_too_new(text):
    """Codepoints (or ZWJ sequences) Roblox's emoji font cannot draw."""
    bad = [ch for ch in text if (0x1FA70 <= ord(ch) <= 0x1FAFF and ord(ch) not in _UNICODE12_IN_EXT_A) or ord(ch) in _NEWER_ELSEWHERE]
    return bad, "‍" in text


def rgb(value):
    if isinstance(value, (list, tuple)):
        return tuple(int(v) for v in value[:3])
    text = str(value).strip().lstrip("#")
    if len(text) != 6:
        raise ValueError(f"bad colour {value!r}")
    return tuple(int(text[i:i + 2], 16) for i in (0, 2, 4))


def hexc(c):
    return "#%02X%02X%02X" % c


def rel_lum(c):
    def ch(v):
        v = v / 255
        return v / 12.92 if v <= 0.03928 else ((v + 0.055) / 1.055) ** 2.4
    r, g, b = (ch(v) for v in c)
    return 0.2126 * r + 0.7152 * g + 0.0722 * b


def contrast(a, b):
    la, lb = sorted((rel_lum(a), rel_lum(b)), reverse=True)
    return (la + 0.05) / (lb + 0.05)


def kit_lum(c):  # same formula as MotifSkinKit.luminance (gamma-encoded)
    return (0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2]) / 255


def hls(c):
    h, l, s = colorsys.rgb_to_hls(*(v / 255 for v in c))
    return h * 360, l, s


def is_navy(c):
    """Dark, mid/low-saturation blue-slate: the colour of generic admin dashboards."""
    h, l, s = hls(c)
    return 205 <= h <= 250 and l < 0.34 and s < 0.85


def mix(a, b, t):
    return tuple(round(a[i] + (b[i] - a[i]) * t) for i in range(3))


def mul(a, b):
    return tuple(round(a[i] * b[i] / 255) for i in range(3))


def text_rule(fill, size, on_light, white):
    """Same rule as MotifSkinKit:textOn: dark type on light/bright fills, else outlined white."""
    lum = kit_lum(fill)
    if lum > 0.82 or (lum > 0.65 and size < 24):
        return on_light, None
    return white, max(1.5, min(4, size / 8.5))


def load(path):
    spec = json.loads(Path(path).read_text(encoding="utf-8"))
    pal = spec["palette"]
    colours = {k: rgb(v) for k, v in pal.items() if k != "candies"}
    colours.setdefault("white", (255, 255, 255))
    colours.setdefault("outline", colours["ink"])
    colours.setdefault("onLight", colours["ink"] if kit_lum(colours["ink"]) < 0.5 else colours["outline"])
    candies = [(name, rgb(v)) for name, v in pal.get("candies", [])]
    pastels = [rgb(v) for v in spec.get("pastels", [])] or [mix(c, colours["paper"], 0.75) for _, c in candies]
    return spec, colours, candies, pastels


def lint(spec, P, candies, pastels):
    errors, warnings, notes = [], [], []
    for key in ("ink", "paper", "panel", "primary", "danger", "success", "muted", "disabled", "dim"):
        if key not in P:
            errors.append(f"palette.{key} missing")
    if errors:
        return errors, warnings, notes
    if len(candies) < 3:
        warnings.append("fewer than 3 candy colours: screens will read monotone")
    large = {k: P[k] for k in ("paper", "panel", "dim", "quiet") if k in P}
    for key, c in list(large.items()) + [("primary", P["primary"])] + candies:
        if is_navy(c):
            errors.append(f"{key} {hexc(c)} is generic navy/slate (dashboard look). Pick a motif-specific hue or lift it.")
    dark_theme = kit_lum(P["paper"]) < 0.5
    if dark_theme and kit_lum(P["outline"]) > 0.5:
        errors.append("dark paper with a light outline: set palette.outline (and onLight) to a dark tint so sticker edges and type on bright fills stay readable")
    if is_navy(P["ink"]) and not dark_theme:
        warnings.append(f"ink {hexc(P['ink'])} is navy: outlines will read as a stock dark theme. Tint ink toward the motif (plum, cocoa, forest, oxblood...).")
    if P["outline"] == (0, 0, 0) or P["ink"] == (0, 0, 0):
        warnings.append("pure black ink/outline: harsh. Tint it (e.g. mix 20% of a motif hue).")
    if P["paper"] == (255, 255, 255) and P["panel"] == (255, 255, 255):
        warnings.append("paper and panel are both pure white: tint paper toward the motif (cream, mint-white, bone...).")
    hues = sorted(hls(c)[0] for _, c in candies if hls(c)[2] > 0.25)
    if len(hues) >= 3 and max(hues) - min(hues) < 50:
        warnings.append("candies sit within 50 deg of hue: fine for a mono-motif, but distinct actions will look alike.")
    body = contrast(P["ink"], P["paper"])
    (errors if body < 4.5 else notes).append(f"body text ink on paper contrast {body:.1f}:1 (need >= 4.5, aim >= 7)")
    muted = contrast(P["muted"], P["paper"])
    if muted < 4.5:
        warnings.append(f"muted on paper {muted:.1f}:1 < 4.5: secondary text will be hard to read")
    if contrast(P["muted"], P["disabled"]) < 2.5:
        warnings.append("muted text on disabled face < 2.5:1: disabled labels vanish")
    fills = [("primary", P["primary"]), ("danger", P["danger"]), ("success", P["success"])] + candies
    for name, c in fills:
        for size in (18, 30):
            color, stroke = text_rule(c, size, P["onLight"], P["white"])
            if stroke is None:
                ratio = contrast(color, c)
                if ratio < 4.5:
                    warnings.append(f"{name} {hexc(c)}: dark type at {size}pt only {ratio:.1f}:1")
            else:
                # Outlined white reads if either the white glyph or the dark outline stands off the fill.
                glyph, edge = contrast(P["white"], c), contrast(P["outline"], c)
                if max(glyph, edge) < 3:
                    warnings.append(f"{name} {hexc(c)}: outlined white type at {size}pt, white {glyph:.1f}:1 and outline {edge:.1f}:1 both < 3")
    for p in pastels:
        type_colour = text_rule(p, 18, P["onLight"], P["white"])[0]
        if type_colour != P["white"] and contrast(type_colour, p) < 7:
            warnings.append(f"pastel {hexc(p)} vs its type {contrast(type_colour, p):.1f}:1 < 7 (pastels hold body text)")
    fonts = spec.get("fonts", {})
    latin_only = set(spec.get("latinOnly", ["display"]))
    for role in ("display", "title", "button", "body"):
        if role not in fonts:
            warnings.append(f"fonts.{role} missing (kit falls back to body)")
    for role, value in fonts.items():
        family, weight = value[0], value[1] if len(value) > 1 else "Regular"
        if family not in ROBLOX_FAMILIES:
            errors.append(f"fonts.{role}: '{family}' is not a Roblox family (silently renders as the default face)")
        if weight not in WEIGHTS:
            errors.append(f"fonts.{role}: weight '{weight}' is not an Enum.FontWeight")
        if family in DISPLAY_ONLY and role not in latin_only:
            warnings.append(f"fonts.{role}: {family} is Latin-only decorative; add '{role}' to latinOnly or pick a plainer face")
        if role in ("body", "strong", "button", "title") and CSS_WEIGHT.get(weight, 400) < 600:
            warnings.append(f"fonts.{role}: weight {weight} renders Japanese thin (CJK falls back at the requested weight); use Bold+")
    if not spec.get("icons"):
        notes.append("no icons map: consider emoji per action (sized at 0.56 of the box)")
    for key, emoji in spec.get("icons", {}).items():
        bad, zwj = emoji_too_new(emoji)
        if bad:
            errors.append(f"icons.{key} {emoji}: Unicode 13+ emoji render as a tofu box in Roblox; pick an older one")
        elif zwj:
            warnings.append(f"icons.{key} {emoji}: ZWJ sequence; check it draws as one glyph in Studio")
    return errors, warnings, notes


def css_font(spec, role):
    value = spec.get("fonts", {}).get(role) or spec.get("fonts", {}).get("body") or ["Nunito", "Bold"]
    family = CSS_FAMILY.get(value[0], "sans-serif")
    weight = CSS_WEIGHT.get(value[1] if len(value) > 1 else "Regular", 400)
    return f'font-family:"{family}",{CJK_CSS};font-weight:{weight};'  # double quotes: lives inside style='...' 


def stroke_css(width, colour):
    return f"-webkit-text-stroke:{width * 2:.1f}px {hexc(colour)};paint-order:stroke fill;"


def button_html(spec, P, face, label, size=20, height=56, width=240, emoji=None, tilt=0, pill=False, disabled=False):
    shade = P.get("shade") or mix(P["white"], P["outline"], 0.22)
    if disabled:
        face, colour, stroke = P["disabled"], P["muted"], None
    else:
        colour, stroke = text_rule(face, size, P["onLight"], P["white"])
    lip = 8 if height >= 64 else 6
    dark = mul(face, shade)
    radius = "999px" if pill else f"{spec.get('shape', {}).get('corner', 16)}px"
    edge = spec.get("shape", {}).get("stroke", 3)
    gloss = "" if kit_lum(face) > 0.82 or disabled else (
        f"<span style='position:absolute;left:5px;right:5px;top:4px;height:36%;border-radius:10px;background:rgba(255,255,255,.2)'></span>")
    icon = f"<span style='position:absolute;left:12px;top:50%;transform:translateY(-55%);font-size:22px'>{emoji}</span>" if emoji and width >= 220 else ""
    text_style = f"color:{hexc(colour)};font-size:{size}px;" + (stroke_css(stroke, P['outline']) if stroke else "")
    return (f"<div style='position:relative;display:inline-flex;align-items:center;justify-content:center;width:{width}px;height:{height}px;"
            f"margin:8px;border:{edge}px solid {hexc(P['outline'])};border-radius:{radius};transform:rotate({tilt}deg);"
            f"background:linear-gradient(to bottom,{hexc(face)} calc(100% - {lip}px),{hexc(dark)} calc(100% - {lip}px));{css_font(spec, 'button')}'>"
            f"{gloss}{icon}<span style='position:relative;{text_style}'>{html.escape(label)}</span></div>")


def mascot_html(spec, P, candies, size=120):
    m = spec.get("mascot")
    if not m:
        return "<p style='opacity:.6'>no mascot in spec</p>"
    named = dict(candies)
    h = size * m.get("aspect", 1.12)
    out, frames = [], {}

    def colour(v):
        if isinstance(v, str) and not v.startswith("#"):
            return P.get(v) or named.get(v) or (128, 128, 128)
        return rgb(v)

    for part in m["parts"]:
        name, x, y, w, hh, col = part[:6]
        opts = part[6] if len(part) > 6 else {}
        parent = opts.get("parent")
        pw, ph = (frames[parent][2], frames[parent][3]) if parent in frames else (size, h)
        px, py = (frames[parent][0], frames[parent][1]) if parent in frames else (0, 0)
        fw, fh = w * pw, hh * ph
        left, top = px + x * pw - fw / 2, py + y * ph - fh / 2
        frames[name] = (left, top, fw, fh)
        radius = f"{opts.get('corner', 1) * 50 if opts.get('corner', 1) <= 1 else 50}%"
        border = f"border:{max(1.5, size / 26):.1f}px solid {hexc(P['ink'])};" if opts.get("stroke") else ""
        out.append(f"<div title='{html.escape(name)}' style='position:absolute;left:{left:.1f}px;top:{top:.1f}px;width:{fw:.1f}px;height:{fh:.1f}px;"
                   f"box-sizing:border-box;background:{hexc(colour(col))};opacity:{1 - opts.get('transparency', 0)};border-radius:{radius};{border}"
                   f"transform:rotate({opts.get('rotation', 0)}deg)'></div>")
    return f"<div style='position:relative;width:{size}px;height:{h:.0f}px;display:inline-block;margin:8px'>{''.join(out)}</div>"


def board(spec, P, candies, pastels, lint_result):
    errors, warnings, notes = lint_result
    ink, paper, white, edge = P["ink"], P["paper"], P["white"], P["outline"]
    families = sorted({CSS_FAMILY.get(v[0], "Nunito") for v in spec.get("fonts", {}).values()})
    font_link = "https://fonts.googleapis.com/css2?" + "&".join(
        "family=" + f.replace(" ", "+") + ":wght@400;700;800;900" if f in ("Nunito", "Montserrat", "Roboto", "Ubuntu", "Merriweather", "Josefin Sans", "Titillium Web", "Inter", "Source Sans 3", "Oswald", "Arimo")
        else "family=" + f.replace(" ", "+") for f in families) + "&family=M+PLUS+Rounded+1c:wght@700;800&display=swap"
    icons = spec.get("icons", {})
    shape = spec.get("shape", {})
    sw = []
    for name, c in [("ink", ink), ("paper", paper), ("panel", P["panel"]), ("primary", P["primary"])] + candies + \
            [("danger", P["danger"]), ("success", P["success"]), ("muted", P["muted"]), ("disabled", P["disabled"]), ("dim", P["dim"])]:
        col, stroke = text_rule(c, 18, P["onLight"], white)
        badge = f"ink {contrast(ink, c):.1f} · white {contrast(white, c):.1f}"
        sw.append(f"<div style='width:132px;margin:6px;border:3px solid {hexc(edge)};border-radius:14px;overflow:hidden;background:{hexc(paper)}'>"
                  f"<div style='height:62px;background:{hexc(c)};display:flex;align-items:center;justify-content:center;"
                  f"color:{hexc(col)};{stroke_css(stroke, edge) if stroke else ''}{css_font(spec, 'button')}font-size:18px'>{html.escape(name)}</div>"
                  f"<div style='padding:4px 6px;font:12px monospace;color:{hexc(ink)}'>{hexc(c)}<br>{badge}</div></div>")
    past = "".join(button_html(spec, P, p, f"リスト {i + 1}", size=18, height=52, width=240, emoji=list(icons.values())[i % len(icons)] if icons else None) for i, p in enumerate(pastels[:5]))
    candy_btns = "".join(button_html(spec, P, c, n.upper(), size=22, height=56, width=200) for n, c in candies)
    cta = button_html(spec, P, P["primary"], "PLAY", size=48, height=84, width=270, tilt=shape.get("tilt", -2), pill=True)
    if spec.get("fonts", {}).get("display"):
        cta = cta.replace(css_font(spec, "button"), css_font(spec, "display"))
    tiles = []
    tile_colours = [c for _, c in candies] or [P["primary"]]
    for i, (key, emoji) in enumerate(list(icons.items())[:6]):
        c = tile_colours[i % len(tile_colours)]
        col, stroke = white, 2  # tiles: white sticker type, like the pop dock
        tiles.append(f"<div style='width:92px;height:92px;margin:5px;border:3px solid {hexc(edge)};border-radius:20px;display:inline-flex;flex-direction:column;"
                     f"align-items:center;justify-content:center;background:linear-gradient(to bottom,{hexc(c)} 88%,{hexc(mul(c, mix(white, edge, .22)))} 88%)'>"
                     f"<span style='font-size:28px'>{emoji}</span><span style='{css_font(spec, 'title')}font-size:14px;color:{hexc(col)};{stroke_css(stroke, edge)}'>{html.escape(key)}</span></div>")
    ribbon = candies[0][1] if candies else P["primary"]
    stripe_a = P["primary"]
    stripe_b = mix(P["primary"], white, 0.55)
    card_face = candies[1][1] if len(candies) > 1 else P["primary"]
    lint_html = "".join(f"<li style='color:#B00020'>ERROR: {html.escape(e)}</li>" for e in errors) + \
        "".join(f"<li style='color:#9A5B00'>warn: {html.escape(w)}</li>" for w in warnings) + \
        "".join(f"<li style='color:#2F6B3A'>ok: {html.escape(n)}</li>" for n in notes)
    return f"""<!doctype html><html><head><meta charset='utf-8'><title>{html.escape(spec.get('name', 'skin'))} style board</title>
<link rel='stylesheet' href='{font_link}'>
<style>body{{margin:0;background:{hexc(mix(P['dim'], paper, .15))};color:{hexc(ink)};{css_font(spec, 'body')}}}
section{{background:{hexc(paper)};border:4px solid {hexc(edge)};border-radius:{shape.get('panelCorner', 20)}px;margin:18px;padding:14px 18px}}
h2{{{css_font(spec, 'title')}margin:4px 0 10px;font-size:26px}}</style></head><body>
<section style='background:{hexc(P['primary'])}'><div style='{css_font(spec, 'display')}font-size:46px;color:{hexc(white)};{stroke_css(4, edge)}'>{html.escape(spec.get('name', 'Motif skin'))}</div>
<div style='font-size:18px'>motif: {html.escape(spec.get('motif', ''))}<br>concept: {html.escape(spec.get('concept', ''))}</div></section>
<section style='background:#FFFFFF;color:#222'><h2>Lint</h2><ul>{lint_html or '<li>clean</li>'}</ul></section>
<section><h2>Palette (contrast vs ink / white)</h2><div style='display:flex;flex-wrap:wrap'>{''.join(sw)}</div></section>
<section><h2>Call to action + dock</h2><div style='display:flex;flex-direction:column;align-items:center'>{cta}<div>{''.join(tiles)}</div></div></section>
<section><h2>Buttons</h2><div>{candy_btns}</div><div>{past}</div><div>{button_html(spec, P, P['primary'], '無効ボタン', disabled=True)}{button_html(spec, P, P['danger'], 'キャンセル', size=20)}{button_html(spec, P, P['success'], 'OK!', size=26)}</div></section>
<section style='padding:0;overflow:hidden'><div style='background:{hexc(ribbon)};border-bottom:4px solid {hexc(edge)};height:62px;display:flex;align-items:center;padding-left:14px'>
<div style='width:52px;height:52px;border-radius:50%;background:{hexc(P['primary'])};border:3px solid {hexc(edge)};display:flex;align-items:center;justify-content:center;font-size:29px;transform:rotate(-8deg)'>{list(icons.values())[0] if icons else '★'}</div>
<span style='{css_font(spec, 'title')}font-size:32px;color:{hexc(white)};{stroke_css(3, edge)};margin-left:12px'>ショップ SHOP</span></div>
<div style='padding:16px 18px'><p style='font-size:17px;margin:0 0 10px'>本文テキスト: 今日のおすすめを選んでね。Body text reads in ink on paper.</p>
<p style='font-size:15px;color:{hexc(P['muted'])};margin:0 0 12px'>補足テキスト muted secondary line</p>
<div style='border:2.5px solid {hexc(edge)};border-radius:14px;background:{hexc(P.get('quiet', paper))};padding:12px;width:320px;font-size:17px;color:{hexc(P['muted'])}'>入力欄 placeholder…</div>
{mascot_html(spec, P, candies)}</div></section>
<section><h2>Mode card</h2><div style='display:flex;gap:16px'>
<div style='width:260px;height:300px;border:4px solid {hexc(edge)};border-radius:26px;background:{hexc(card_face)};position:relative;overflow:hidden'>
<div style='height:62%;background:repeating-linear-gradient(45deg,{hexc(mix(card_face, white, .35))} 0 18px,{hexc(mix(card_face, white, .55))} 18px 36px)'></div>
<div style='position:absolute;left:0;right:0;top:56%;text-align:center;{css_font(spec, 'display')}font-size:38px;color:{hexc(white)};{stroke_css(4, edge)};transform:rotate(-3deg)'>CLASSIC</div>
<div style='position:absolute;left:18px;right:18px;bottom:20px;background:{hexc(paper)};border:3px solid {hexc(edge)};border-radius:999px;text-align:center;font-size:14px;padding:6px'>ひとことの説明タグ</div></div>
<div style='width:260px;height:300px;border:4px solid {hexc(edge)};border-radius:26px;background:repeating-linear-gradient(45deg,{hexc(stripe_a)} 0 26px,{hexc(stripe_b)} 26px 52px);display:flex;align-items:center;justify-content:center;{css_font(spec, 'display')}font-size:34px;color:{hexc(white)};{stroke_css(4, edge)}'>COMING SOON</div></div></section>
<section style='background:{hexc(mix(candies[2][1] if len(candies) > 2 else P['primary'], paper, .8))}'><h2>Banner</h2>
<div style='display:flex;align-items:center;gap:12px;border:3px solid {hexc(edge)};border-radius:18px;background:{hexc(P['panel'])};padding:8px 12px;width:520px'>
<div style='width:40px;height:40px;border-radius:50%;background:{hexc(candies[2][1] if len(candies) > 2 else P['primary'])};border:3px solid {hexc(edge)};display:flex;align-items:center;justify-content:center;font-size:22px'>🔍</div>
<span style='{css_font(spec, 'strong')}font-size:16px'>対戦相手を検索中… 0:12</span>{button_html(spec, P, P['danger'], 'やめる', size=18, height=48, width=120)}</div></section>
</body></html>"""


def luau(spec, P, candies, pastels):
    def c3(c):
        return f"Color3.fromRGB({c[0]}, {c[1]}, {c[2]})"

    def lua_str(s):
        return json.dumps(s, ensure_ascii=False)

    lines = ["-- Generated by roblox-motif-ui/scripts/skin_preview.py from the skin spec. Edit the JSON, not this file.",
             f"-- {spec.get('name', '')}: {spec.get('concept', '')}", "return {", "\tpalette = {"]
    for key, c in P.items():
        lines.append(f"\t\t{key} = {c3(c)},")
    lines.append("\t\tcandies = {")
    for name, c in candies:
        lines.append(f"\t\t\t{{{lua_str(name)}, {c3(c)}}},")
    lines += ["\t\t},", "\t},", "\tpastels = {"]
    for p in pastels:
        lines.append(f"\t\t{c3(p)},")
    lines += ["\t},", "\tfonts = {"]
    for role, value in spec.get("fonts", {}).items():
        lines.append(f"\t\t{role} = {{{lua_str(value[0])}, {lua_str(value[1] if len(value) > 1 else 'Regular')}}},")
    lines += ["\t},", "\tlatinOnly = {" + ", ".join(f"{r} = true" for r in spec.get("latinOnly", ["display"])) + "},"]
    shape = spec.get("shape", {})
    lines.append("\tshape = {" + ", ".join(f"{k} = {v}" for k, v in shape.items()) + "},")
    lines.append("\ticons = {")
    for key, emoji in spec.get("icons", {}).items():
        lines.append(f"\t\t[{lua_str(key)}] = {lua_str(emoji)},")
    lines.append("\t},")
    m = spec.get("mascot")
    if m:
        lines.append("\tmascot = {")
        lines.append(f"\t\tname = {lua_str(m.get('name', 'Mascot'))}, aspect = {m.get('aspect', 1.12)},")
        lines.append("\t\tblink = {" + ", ".join(lua_str(b) for b in m.get("blink", [])) + "},")
        lines.append("\t\tparts = {")
        for part in m["parts"]:
            name, x, y, w, h, col = part[:6]
            opts = part[6] if len(part) > 6 else {}
            extra = "".join(f", {k} = {lua_str(v) if isinstance(v, str) else ('true' if v is True else 'false' if v is False else v)}" for k, v in opts.items())
            lines.append(f"\t\t\t{{{lua_str(name)}, {x}, {y}, {w}, {h}, {lua_str(col)}{extra}}},")
        lines += ["\t\t},", "\t},"]
    lines.append("}")
    return "\n".join(lines) + "\n"


def screenshot(html_path, png_path):
    candidates = [shutil.which(n) for n in ("chrome", "google-chrome", "chromium", "msedge")]
    candidates += [r"C:\Program Files\Google\Chrome\Application\chrome.exe",
                   r"C:\Program Files (x86)\Google\Chrome\Application\chrome.exe",
                   r"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe",
                   r"C:\Program Files\Microsoft\Edge\Application\msedge.exe",
                   "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"]
    exe = next((c for c in candidates if c and os.path.exists(c)), None)
    if not exe:
        print("png: no Chrome/Edge found, skipped")
        return False
    url = Path(html_path).resolve().as_uri()
    cmd = [exe, "--headless=new", "--disable-gpu", "--hide-scrollbars", "--virtual-time-budget=6000",
           f"--screenshot={Path(png_path).resolve()}", "--window-size=1200,2600", url]
    try:
        subprocess.run(cmd, check=True, timeout=90, capture_output=True)
    except Exception as exc:  # noqa: BLE001
        print(f"png: screenshot failed: {exc}")
        return False
    print(f"png: {png_path}")
    return True


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("spec")
    ap.add_argument("--html")
    ap.add_argument("--png")
    ap.add_argument("--luau")
    ap.add_argument("--strict", action="store_true")
    args = ap.parse_args()
    spec, P, candies, pastels = load(args.spec)
    result = lint(spec, P, candies, pastels)
    errors, warnings, notes = result
    for e in errors:
        print("ERROR", e)
    for w in warnings:
        print("warn ", w)
    for n in notes:
        print("ok   ", n)
    if args.html or args.png:
        html_path = args.html or str(Path(args.png).with_suffix(".html"))
        Path(html_path).write_text(board(spec, P, candies, pastels, result), encoding="utf-8")
        print(f"html: {html_path}")
        if args.png:
            screenshot(html_path, args.png)
    if args.luau:
        Path(args.luau).write_text(luau(spec, P, candies, pastels), encoding="utf-8")
        print(f"luau: {args.luau}")
    print(f"RESULT: {len(errors)} error(s), {len(warnings)} warning(s)")
    sys.exit(1 if (args.strict and errors) else 0)


if __name__ == "__main__":
    main()
