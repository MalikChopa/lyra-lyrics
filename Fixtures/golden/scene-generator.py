#!/usr/bin/env python3
# W6a : génère scene-math.json, scene-screen.json et scene-layout.json (valeurs attendues de la Scène).
# Ce script est une 3e implémentation INDÉPENDANTE (Python) des formules de Sources/AppSupport/Features110.swift et de
# Sources/LyraLyrics/SceneView.swift / SceneController.swift / SceneExtras.swift : les deux suites (Swift, C#) doivent retrouver ses valeurs.
# Usage : python3 -I Fixtures/golden/scene-generator.py   (écrit à côté de lui ; aucun accès réseau ni disque hors de ce dossier)
import json, math, os

HERE = os.path.dirname(os.path.abspath(__file__))

def write(name, obj):
    with open(os.path.join(HERE, name), "w", encoding="utf-8") as f:
        json.dump(obj, f, ensure_ascii=False, indent=1)
        f.write("\n")

# ---------- scene-screen.json
def pick(setting, names, main_i, win_i):
    if not names: return 0
    w = min(max(win_i, 0), len(names) - 1)
    if setting == "main": return min(max(main_i, 0), len(names) - 1)
    if setting.startswith("name:"):
        want = setting[5:]
        return names.index(want) if want in names else w
    return w

screen_cases = []
def sc(label, setting, names, main_i, win_i):
    screen_cases.append({"label": label, "setting": setting, "names": names, "mainIndex": main_i, "windowIndex": win_i,
                         "expected": pick(setting, names, main_i, win_i)})
three = ["Écran intégré", "Dell U2720Q", "LG HDR 4K"]
sc("fenêtre : écran 0", "window", three, 0, 0)
sc("fenêtre : écran 2", "window", three, 0, 2)
sc("fenêtre : indice trop grand", "window", three, 0, 9)
sc("fenêtre : indice négatif", "window", three, 0, -3)
sc("principal : 0", "main", three, 0, 2)
sc("principal : autre indice", "main", three, 1, 2)
sc("principal : indice trop grand", "main", three, 7, 0)
sc("nom : deuxième", "name:Dell U2720Q", three, 0, 2)
sc("nom : accent", "name:Écran intégré", three, 2, 1)
sc("nom : débranché", "name:Débranché", three, 0, 2)
sc("nom : casse différente (sensible à la casse)", "name:dell u2720q", three, 0, 1)
sc("nom : vide", "name:", three, 0, 1)
sc("nom : deux écrans de même nom (le premier)", "name:Generic PnP Monitor", ["Generic PnP Monitor", "Generic PnP Monitor"], 0, 1)
sc("réglage inconnu = fenêtre", "n'importe quoi", three, 0, 1)
sc("réglage vide = fenêtre", "", three, 0, 2)
sc("un seul écran", "name:Autre", ["Seul"], 0, 0)
sc("aucun écran : 0", "window", [], 0, 0)
sc("aucun écran, nom : 0", "name:X", [], 0, 0)
write("scene-screen.json", {"description": "S10 : choix de l'écran de la Scène (SceneScreenChoice.pick). Lu par Swift (Tests/AppSupportTests/SceneFixtureTests.swift) et C# (W6ParityTests). Les noms d'écran sont comparés exactement.", "cases": screen_cases})

# ---------- scene-math.json
def L(t, text): return {"time": t, "text": text}
def fill_duration(lines, i):
    if i < 0 or i >= len(lines): return 0.8
    gap = lines[i + 1]["time"] - lines[i]["time"] if i + 1 < len(lines) else 4.0
    return min(7.0, max(0.8, gap * 0.92))
def fill_fraction(pos, start, dur):
    if not dur > 0: return 1.0
    return min(1.0, max(0.0, (pos - start) / dur))
def sung(n): return min(6.0, 1.2 + 0.06 * n)
def gaps_of(lines, ph, duration, count):
    out = []
    if not lines: return out
    if lines[0]["time"] > 6.0 and lines[0]["text"] != ph: out.append([0.0, lines[0]["time"]])
    for i, l in enumerate(lines):
        end = lines[i + 1]["time"] if i + 1 < len(lines) else duration
        if end is None: continue
        if l["text"] == ph:
            if end - l["time"] >= 3: out.append([l["time"], end])
        else:
            until = l["time"] + sung(count(l["text"]))
            if end - until > 6.0: out.append([until, end])
    return out

song = [L(0, "Une"), L(2.8, "Deux"), L(30, "Trois"), L(31, "Quatre ligne"), L(31.5, "Cinq")]
fill = {"songs": {"song": song, "single": [L(5, "Seule")], "same": [L(1, "a"), L(1, "b")], "backwards": [L(10, "a"), L(8, "b")]},
        "durations": [], "fractions": []}
for name, lines in fill["songs"].items():
    for i in list(range(-1, len(lines) + 1)):
        fill["durations"].append({"song": name, "index": i, "expected": fill_duration(lines, i)})
for pos, start, dur in [(1, 0, 2), (-1, 0, 2), (9, 0, 2), (0, 0, 2), (2, 0, 2), (3.3, 3, 0.8), (5, 5, 0), (5, 5, -1), (12.5, 10, 7), (0.5, 1, 4), (100, 1, 7)]:
    fill["fractions"].append({"position": pos, "start": start, "duration": dur, "expected": fill_fraction(pos, start, dur)})

sung_cases = []
for text, n in [("", 0), ("a", 1), ("Bonjour", 7), ("Il était une fois", 17), ("é", 1), ("é", 1), ("👍🏽", 1), ("🇫🇷🇯🇵", 2),
                ("A" * 80, 80), ("Ça va très bien, merci beaucoup pour tout", 41), ("日本語の歌詞", 6), ("🎵 ♪ 🎶", 5)]:
    sung_cases.append({"text": text, "characters": n, "expected": sung(n)})

PH = "♪"
gap_sets = {
    "intro 12 s": ([L(12, "Après l'introduction")], None),
    "intro 6 s pile": ([L(6, "Tout juste")], None),
    "intro, placeholder": ([L(20, PH), L(40, "Texte")], 60.0),
    "pas de trou": ([L(0, "Court"), L(4, "Court")], 8.0),
    "trou entre deux lignes": ([L(0, "Bonjour"), L(1.6, "Suite"), L(33, "Après"), L(40, "Fin")], 60.0),
    "après la dernière": ([L(1, "Une seule ligne"), L(2, "Deux")], 60.0),
    "durée inconnue": ([L(1, "Une"), L(2, "Deux")], None),
    "♪ de 3 s": ([L(0, "Début"), L(5, PH), L(8, "Retour")], 20.0),
    "♪ de 2,9 s": ([L(0, "Début"), L(5, PH), L(7.9, "Retour")], 20.0),
    "ligne longue (plafond 6 s)": ([L(0, "x" * 200), L(12.1, "Suite"), L(12.5, "Fin")], 13.0),
    "accents et emoji": ([L(0, "ééé"), L(10, "👍🏽👍🏽"), L(30, "Fin")], 40.0),
    "vide": ([], 60.0),
}
def count_chars(text):
    # Compteur de caractères du générateur : mêmes cas que les fixtures (texte « x » ASCII, accents composés, emoji à modificateur).
    table = {"ééé": 3, "👍🏽👍🏽": 2}
    return table.get(text, len(text))
gap_cases = []
for name, (lines, dur) in gap_sets.items():
    g = gaps_of(lines, PH, dur, count_chars)
    gap_cases.append({"label": name, "lines": lines, "placeholder": PH, "duration": dur,
                      "expected": [{"start": a, "end": b, "fadeOutAt": max(a, b - 1.0)} for a, b in g]})
gap_at = []
g1 = [[3.0, 10.0], [20.0, 25.0]]
for pos in [0, 3, 3.0001, 9.999, 10, 15, 20, 24.9, 25, 99, -1]:
    idx = next((i for i, (a, b) in enumerate(g1) if a <= pos < b), -1)
    gap_at.append({"position": pos, "gaps": [{"start": a, "end": b} for a, b in g1], "expectedIndex": idx})

def fake_measure(text, size, width):
    per = max(1, math.floor(width / (size * 0.5)))
    return math.ceil(len(text) / per) * size * 1.2
def fit(text, width, max_h, max_size, min_size=28):
    size = float(max_size)
    while size > min_size and fake_measure(text, size, width) > max_h:
        size = max(float(min_size), math.floor(size * 0.94))
    return size
fit_cases = []
for label, text, width, mh, ms, mn in [
    ("court, tient", "Court", 1000, 300, 110, 28), ("long, réduit", "mot " * 30, 1000, 300, 110, 28),
    ("très long, plancher", "x" * 4000, 600, 100, 124, 28), ("plancher personnalisé", "x" * 4000, 600, 100, 124, 40),
    ("juste à la limite", "a" * 20, 500, 132, 100, 28), ("largeur étroite", "Une phrase de taille moyenne pour la ligne", 300, 200, 90, 28),
    ("taille max sous le plancher", "Court", 1000, 300, 20, 28), ("texte vide", "", 800, 200, 120, 28),
    ("écran 1080p, ligne courante", "Je marche seul dans la nuit, le vent dans les cheveux", 1100, 291.6, 91.8, 28),
    ("écran 1080p, suivante (rôle 1)", "Je marche seul dans la nuit, le vent dans les cheveux", 2200, 583.2, 91.8, 28),
]:
    fit_cases.append({"label": label, "text": text, "width": width, "maxHeight": mh, "maxSize": ms, "minSize": mn, "expected": fit(text, width, mh, ms, mn)})

def max_bg(t, ratio=4.5): return max(0.0, (t + 0.05) / ratio - 0.05)
def contrast(t, bg, scrim):
    b = bg * (1 - scrim)
    return (max(t, b) + 0.05) / (min(t, b) + 0.05)
def scrim_alpha(bg, t, minimum=0.30):
    allowed = max_bg(t)
    if not bg > 0: return minimum
    return min(0.92, max(minimum, 1 - allowed / bg))
def background(art, grad, text):
    def eff(a, s): return (art * a + grad * (1 - a)) * (1 - s)
    def ratio(a, s): return contrast(text, eff(a, s), 0)
    scrim = 0.30
    while scrim <= 0.95:
        a = 0.92
        while a >= 0:
            if ratio(a, scrim) >= 4.5: return a, scrim, ratio(a, scrim)
            a -= 0.04
        scrim += 0.05
    return 0.0, 0.95, ratio(0, 0.95)

lums = [0.0, 0.01, 0.02, 0.05, 0.1, 0.2, 0.35, 0.5, 0.7, 0.85, 1.0]
contrast_cases = {
    "maxBackground": [{"text": t, "expected": max_bg(t)} for t in [0, 0.05, 0.2, 0.5, 0.7, 1.0]],
    "scrim": [{"background": b, "text": t, "expected": scrim_alpha(b, t)} for b in lums for t in [0.3, 0.7, 1.0]],
    "contrast": [{"text": t, "background": b, "scrim": s, "expected": contrast(t, b, s)} for t, b, s in
                 [(1.0, 0.0, 0.0), (1.0, 1.0, 0.0), (0.5, 0.1, 0.3), (0.7, 0.9, 0.5), (0.2, 0.2, 0.0), (1.0, 0.5, 0.92)]],
    "background": [],
}
for art in [0.0, 0.01, 0.2, 0.6, 1.0]:
    for grad in [0.02, 0.1, 0.4]:
        for text in [0.3, 0.7, 1.0]:
            a, s, r = background(art, grad, text)
            contrast_cases["background"].append({"art": art, "gradient": grad, "text": text, "artOpacity": a, "scrim": s, "contrast": r})

# Dégradé de fond (S1) : la teinte vient de ArtworkPalette ; elle est recopiée ici (valeurs de golden/palette.json) et vérifiée par les deux suites.
def lin(v): return v / 12.92 if v <= 0.03928 else ((v + 0.055) / 1.055) ** 2.4
def lum(c): return 0.2126 * lin(c[0]) + 0.7152 * lin(c[1]) + 0.0722 * lin(c[2])
def hsb(c):
    r, g, b = c; mx = max(c); mn = min(c); d = mx - mn; h = 0.0
    if d > 0:
        if mx == r: h = ((g - b) / d) % 6
        elif mx == g: h = (b - r) / d + 2
        else: h = (r - g) / d + 4
        h /= 6
        if h < 0: h += 1
    return h, (0 if mx == 0 else d / mx), mx
def from_hsb(h, s, v):
    hh = (h - math.floor(h)) * 6; c = v * s; x = c * (1 - abs(hh % 2 - 1)); m = v - c
    r, g, b = [(c, x, 0), (x, c, 0), (0, c, x), (0, x, c), (x, 0, c), (c, 0, x)][int(hh)]
    return [r + m, g + m, b + m]
def tint_of(dom):
    h, s, v = hsb(dom)
    return from_hsb(h, min(s, 0.75), min(max(v * 0.5, 0.14), 0.30))
gradient_cases = []
for label, dom, sec in [("rouge vif", [0.85, 0.12, 0.10], [0.95, 0.75, 0.20]), ("bleu nuit", [0.10, 0.18, 0.55], [0.40, 0.75, 0.95]),
                        ("pastel clair", [0.92, 0.85, 0.80], [0.70, 0.80, 0.95]), ("presque noir", [0.04, 0.04, 0.06], [0.20, 0.10, 0.30]),
                        ("vert", [0.15, 0.60, 0.30], [0.90, 0.90, 0.20])]:
    tint = tint_of(dom)
    cols = [[x * 0.62 for x in dom], tint, [x * 0.45 for x in sec]]
    gl = max(lum(dom) * 0.4, lum(sec) * 0.25, lum(tint))
    gradient_cases.append({"label": label, "dominant": dom, "secondary": sec, "tint": tint, "colors": cols, "luminance": gl})
gradient = {"neutral": {"colors": [[0.10, 0.13, 0.24], [0.05, 0.06, 0.12], [0.14, 0.08, 0.20]], "luminance": 0.02}, "palettes": gradient_cases}

write("scene-math.json", {
    "description": "Calculs purs de la Scène (SceneMath de Sources/AppSupport/Features110.swift) : S5 remplissage, S6 passages sans paroles, S4 taille du texte, contraste du fond, dégradé S1. Valeurs produites par scene-generator.py (Python, indépendant). Lu par Swift (SceneFixtureTests) et C# (W6ParityTests). Mesure factice de fitSize : lignes = ceil(nbCaractères / max(1, floor(largeur / (taille × 0,5)))), hauteur = lignes × taille × 1,2. « characters » = nombre de caractères au sens de Swift (grappes de graphèmes).",
    "tolerance": 1e-9,
    "fill": fill, "sungDuration": sung_cases, "gaps": gap_cases, "gapAt": gap_at, "fitSize": fit_cases,
    "contrast": contrast_cases, "gradient": gradient})

# ---------- scene-layout.json (ordonnées vers le BAS : y = H − y_Mac)
def frame(W, H, with_art):
    side = min(W * 0.34, H * 0.56); left = W * 0.05; col = left + side + W * 0.04
    tw = (W * 0.95 - col) * 0.96 if with_art else W * 0.70
    cx = (col + W * 0.95) / 2 if with_art else W / 2
    # Mac (ordonnées vers le haut) : centre des lignes et de la pochette = 0,56 H ; bas de la pochette = 0,56 H − côté/2
    cy_mac = H * 0.56
    tile_min_mac = cy_mac - side / 2
    ts = max(18, H * 0.028); ss = max(14, H * 0.02)
    its = max(30, H * 0.06); iss = max(16, H * 0.03)
    title_top = H - (tile_min_mac - ts * 1.7 + ts * 1.4)
    artist_top = H - (tile_min_mac - ts * 1.7 - ss * 1.5 + ss * 1.4)
    return {"artSide": side, "artLeft": left, "columnLeft": col, "textWidth": tw, "textCenterX": cx,
            "centerY": H - cy_mac, "artTop": H - (cy_mac + side / 2), "artCorner": side * 0.045,
            "titleSize": ts, "artistSize": ss, "titleTop": title_top, "artistTop": artist_top,
            "maxLineSize": min(max(H * 0.085, 44), 124), "infoTitleSize": its, "infoSubSize": iss,
            "infoTitleTop": H - (H * 0.40 + its * 2.4), "infoSubTop": H - (H * 0.30 + iss * 2.6)}
sizes = [(1920, 1080), (2560, 1440), (3840, 2160), (1366, 768), (1280, 720), (2560, 1080), (1080, 1920), (800, 600), (5120, 1440)]
frames = []
for W, H in sizes:
    for with_art in (True, False):
        f = frame(W, H, with_art)
        scale_widths = {str(r): f["textWidth"] / sc_ for r, sc_ in ((0, 1), (1, 0.5), (2, 0.42))}
        fit_h = {str(r): H * 0.27 / sc_ for r, sc_ in ((0, 1), (1, 0.5), (2, 0.42))}
        frames.append({"width": W, "height": H, "withArtwork": with_art, "frame": f, "layoutWidth": scale_widths, "fitMaxHeight": fit_h})

def target(offset, H, h_cur, h_next, h_self, fill_enabled):
    y_cur = H * 0.56
    if offset == 0: t = (y_cur, 1, 1, 0.78 if fill_enabled else 0, 0)
    elif offset == 1: t = (y_cur - h_cur / 2 - H * 0.05 - h_self * 0.5 / 2, 0.5, 0.76, 1, 0)
    elif offset == 2:
        h1 = h_next * 0.5
        t = (y_cur - h_cur / 2 - H * 0.05 - h1 - H * 0.035 - h_self * 0.42 / 2, 0.42, 0.72, 1, 0)
    elif offset == -1: t = (y_cur + h_cur / 2 + H * 0.13, 0.82, 0, 0.2, 0.7)
    else: t = (y_cur - H * 0.4, 0.4, 0, 1, 0)
    return {"y": H - t[0], "scale": t[1], "opacity": t[2], "sharp": t[3], "soft": t[4]}
targets = []
for H, hc, hn, hs in [(1080, 120, 110, 100), (1080, 240, 120, 60), (1440, 160, 160, 160), (768, 76.8, 50, 90), (2160, 216, 200, 180), (1080, 108, 0, 0)]:
    for off in (-2, -1, 0, 1, 2, 3):
        for fe in (False, True):
            if fe and off not in (0, 1): continue
            targets.append({"height": H, "hCur": hc, "hNext": hn, "hSelf": hs, "offset": off, "fillEnabled": fe, **target(off, H, hc, hn, hs, fe)})

def local_rect(small, screen):
    sx, sy, sw, sh = screen; x, y, w, h = small
    inter = x < sx + sw and sx < x + w and y < sy + sh and sy < y + h and w > 0 and h > 0 and sw > 0 and sh > 0
    if inter: return [x - sx, y - sy, w, h]
    ww = sw * 0.27; hh = ww * 0.42
    return [(sw - ww) / 2, (sh - hh) / 2, ww, hh]
zoom = []
for label, small, screen in [
    ("fenêtre dans l'écran", (1400, 800, 460, 190), (0, 0, 1920, 1080)),
    ("écran secondaire à droite, fenêtre sur le principal", (1400, 800, 460, 190), (1920, 0, 2560, 1440)),
    ("écran à gauche (coordonnées négatives)", (200, 300, 460, 190), (-1920, 0, 1920, 1080)),
    ("fenêtre à cheval", (1800, 900, 460, 190), (1920, 0, 2560, 1440)),
    ("bords qui se touchent seulement", (1460, 100, 460, 190), (1920, 0, 2560, 1440)),
    ("écran décalé en hauteur", (100, 1200, 460, 190), (0, 1080, 1920, 1080)),
    ("fenêtre plus grande que l'écran", (-100, -100, 2200, 1300), (0, 0, 1920, 1080)),
]:
    r = local_rect(small, screen)
    s = max(0.05, r[2] / max(1, screen[2]))
    zoom.append({"label": label, "small": list(small), "screen": list(screen), "expectedLocal": r, "expectedStartScale": s})

# Mouvements lents : valeurs de la Bézier (0,42 ; 0 ; 0,58 ; 1) calculées ici par Newton (le C# fait une dichotomie).
def bez_y(x):
    if x <= 0: return 0.0
    if x >= 1: return 1.0
    x1, y1, x2, y2 = 0.42, 0.0, 0.58, 1.0
    s = x
    for _ in range(40):
        bx = 3 * (1 - s) ** 2 * s * x1 + 3 * (1 - s) * s ** 2 * x2 + s ** 3 - x
        dbx = 3 * (1 - s) ** 2 * x1 + 6 * (1 - s) * s * (x2 - x1) + 3 * s ** 2 * (1 - x2)
        if abs(dbx) < 1e-12: break
        s -= bx / dbx
    return 3 * (1 - s) ** 2 * s * y1 + 3 * (1 - s) * s ** 2 * y2 + s ** 3
def pingpong(t, leg):
    if t <= 0: return 0.0
    ph = (t % (2 * leg)) / leg
    return ph if ph <= 1 else 2 - ph
motion = []
for t in [0, 1, 6, 12, 24, 36, 47.9, 48, 60, 72, 95.9, 96, 96.5, 130, 200, 1000.25]:
    p = bez_y(pingpong(t, 48))
    W, H = 1920, 1080
    drift = {"scale": 1 + 0.2 * p, "dx": -W * 0.055 + W * 0.11 * p, "dy": H * 0.035 + (-H * 0.04 - H * 0.035) * p}
    q = bez_y(pingpong(t, 26))
    motion.append({"t": t, "width": W, "height": H, "drift": drift, "breath": {"mid": 0.5 + (0.3 - 0.5) * q, "end": 1.0 + (0.76 - 1.0) * q}})

write("scene-layout.json", {
    "description": "Géométrie de la Scène (formules de SceneView.swift, SceneController.swift, SceneExtras.swift) produite par scene-generator.py. ORDONNÉES VERS LE BAS (haut de l'écran = 0 ; le Mac compte vers le haut : y = H − y_Mac). « frames » : mise en page selon la taille de l'écran ; « targets » : place des lignes ; « zoom » : rectangle de départ du zoom S25. « motion » (dérive et respiration du fond, Core Animation sur Mac) n'est lu que par C# : le Mac n'a pas de fonction pure à comparer. Lu par Swift (SceneFixtureTests, transcription des formules) et C# (W6ParityTests).",
    "tolerance": 1e-9, "motionTolerance": 1e-6,
    "frames": frames, "targets": targets, "zoom": zoom, "motion": motion})
print("scene-screen:", len(screen_cases), "cases ; scene-math: fill", len(fill["durations"]), "+", len(fill["fractions"]), ", sung", len(sung_cases), ", gaps", len(gap_cases),
      ", gapAt", len(gap_at), ", fit", len(fit_cases), ", scrim", len(contrast_cases["scrim"]), ", background", len(contrast_cases["background"]),
      ", gradient", len(gradient_cases), "; scene-layout: frames", len(frames), ", targets", len(targets), ", zoom", len(zoom), ", motion", len(motion))

# ---------- scene-extras.json : finitions de la Scène (karaoké, passages sans paroles, carte du titre, barre, sortie de ligne, repli d'écran)
# Formules de Sources/LyraLyrics/AppModel.swift (karaokeSpec), FillMask.swift, SceneView.swift (desiredGap, buildCard, leave), SceneExtras.swift (SceneControlsBar).
def lines_of(song_name): return fill["songs"][song_name]
karaoke = []
song_ph = [L(0, "Une"), L(3, PH), L(9, "Trois")]
for name, lines in [("song", song), ("single", [L(5, "Seule")]), ("avec ♪", song_ph)]:
    for idx in range(-1, len(lines) + 1):
        for pos, playing, enabled, reduce in [(1.0, True, True, False), (4.0, False, True, False), (4.0, True, False, False), (4.0, True, True, True)]:
            exp = None
            if enabled and not reduce and 0 <= idx < len(lines) and lines[idx]["text"] != PH:
                d = fill_duration(lines, idx)
                exp = {"duration": d, "fraction": fill_fraction(pos, lines[idx]["time"], d), "playing": playing}
            karaoke.append({"song": name, "lines": lines, "index": idx, "position": pos, "playing": playing, "enabled": enabled, "reduceMotion": reduce, "expected": exp})

def cumulative(widths):
    total = max(1.0, sum(widths))
    cum, acc = [0.0], 0.0
    for w in widths:
        acc += w / total
        cum.append(min(1.0, acc))
    cum[-1] = 1.0
    return cum
def piece(cum, i, f0, d, playing, animated):
    f0 = min(1.0, max(0.0, f0))
    c0, c1 = cum[i], cum[i + 1]
    v = min(1.0, max(0.0, (f0 - c0) / (c1 - c0))) if c1 > c0 else 1.0
    if animated and playing and v < 1 and d > 0:
        return {"start": v, "begin": max(0.0, c0 - f0) * d, "duration": max(0.05, (c1 - max(c0, f0)) * d), "animated": True}
    return {"start": v, "begin": 0.0, "duration": 0.0, "animated": False}
pieces = []
for widths in [[300.0], [200.0, 100.0], [120.0, 360.0, 20.0], [0.5, 0.25], [50.0, 50.0, 50.0, 50.0]]:
    cum = cumulative(widths)
    for f0, d, playing, animated in [(0.0, 5.0, True, True), (0.4, 5.0, True, True), (0.4, 5.0, False, True), (0.9, 3.0, True, True), (1.0, 3.0, True, True), (0.0, 0.0, True, True), (0.25, 4.0, True, False), (-0.5, 2.0, True, True), (1.5, 2.0, True, True)]:
        pieces.append({"widths": widths, "cumulative": cum, "startFraction": f0, "duration": d, "playing": playing, "animated": animated,
                       "pieces": [piece(cum, i, f0, d, playing, animated) for i in range(len(widths))]})
resync = []
for cur, exp, want, wf in [(True, 0.5, True, 0.5), (True, 0.5, False, 0.5), (False, 0.5, True, 0.5), (True, 0.5, True, 0.69), (True, 0.5, True, 0.68), (True, 0.5, True, 0.31), (True, 0.5, True, 0.32), (False, 0.0, False, 1.0)]:
    resync.append({"currentPlaying": cur, "expected": exp, "wantPlaying": want, "wantFraction": wf, "expectedResync": cur != want or abs(exp - wf) > 0.18})

def fmt(sec):
    s = max(0, math.floor(sec))
    return "%d:%02d" % (s // 60, s % 60)
bar_format = [{"seconds": s, "expected": fmt(s)} for s in [0, 0.4, 0.999, 1, 59.9, 60, 61, 125.5, 599.99, 600, 3599, 3600, 7325.4, -3]]
bar_fraction = [{"position": p, "duration": d, "expected": (min(1.0, max(0.0, p / d)) if d is not None and d > 0 else 0.0)}
                for p, d in [(0, 200), (50, 200), (200, 200), (260, 200), (-5, 200), (30, None), (30, 0)]]
bar_layout = []
for W, H in [(1920, 1080), (3840, 2160), (1366, 768), (800, 600), (5120, 1440)]:
    w = min(W * 0.56, 720.0)
    bar_layout.append({"width": W, "height": H, "barWidth": w, "left": (W - w) / 2, "top": H - 46 - 96, "prevX": w / 2 - 74, "playX": w / 2, "nextX": w / 2 + 74, "exitX": w - 40,
                       "rowY": 96 - 66, "trackLeft": 84, "trackWidth": w - 168, "trackTop": 96 - 24, "elapsedLeft": 14, "totalLeft": w - 76, "timeTop": 96 - 30})
leave = []
for n in range(0, 14):
    step = min(0.040, 0.32 / (n - 1)) if n > 1 else 0.0
    wd = max(0.3, 0.6 - max(0, n - 1) * step)
    leave.append({"words": n, "step": step, "wordDuration": wd, "total": max(0, n - 1) * step + wd})
card = []
for W, H in [(1920, 1080), (3840, 2160), (1366, 768), (1080, 1920), (5120, 1440)]:
    side = min(H * 0.40, W * 0.30)
    ts, ss = max(30, H * 0.058), max(18, H * 0.031)
    card.append({"width": W, "height": H, "side": side, "artLeft": W / 2 - side / 2, "artTop": H * 0.5 - side, "artCorner": side * 0.04, "reflectionTop": H * 0.5 + 2, "reflectionHeight": side * 0.28,
                 "titleSize": ts, "artistSize": ss, "textLeft": W * 0.2, "textWidth": W * 0.6,
                 "titleTop": H - (H * 0.50 - side * 0.30 - ts * 2.0) - ts * 1.3, "titleHeight": ts * 1.3,
                 "artistTop": H - (H * 0.50 - side * 0.30 - ts * 2.0 - ss * 1.6) - ss * 1.3, "artistHeight": ss * 1.3})
card_timing = [{"reduce": r, "in": (0.3 if r else 0.9), "hold": 1.5, "out": (0.3 if r else 0.9), "total": (0.3 if r else 0.9) * 2 + 1.5} for r in (False, True)]
gap_wanted = []
gsets = [(g["label"], g["lines"], g["duration"]) for g in gap_cases]
for label, lines, dur in gsets:
    gl = gaps_of(lines, PH, dur, count_chars)
    probes = sorted({0.0, 3.0} | {x for g in gl for x in (g[0], g[1] - 1.0, g[1] - 1.5, g[1], (g[0] + g[1]) / 2)})
    for pos in probes:
        for mode, pp in [("synced", True), ("synced", False)]:
            hit = next((g for g in gl if g[0] <= pos < g[1]), None)
            want = bool(pp and hit is not None and pos < max(hit[0], hit[1] - 1.0))
            gap_wanted.append({"label": label, "mode": mode, "playingOrPaused": pp, "position": pos, "gaps": [{"start": a, "end": b} for a, b in gl], "expected": want})
for mode, exp in [("searching", False), ("offline", False), ("busy", False), ("other", True)]:
    gap_wanted.append({"label": "état " + mode, "mode": mode, "playingOrPaused": True, "position": 5.0, "gaps": [], "expected": exp})
sc_cases = []
A = ("Écran A", 0, 0, 1920, 1080); B = ("Écran B", 1920, 0, 2560, 1440); C = ("Écran C", -1280, 0, 1280, 1024)
for label, screens, main_i, cur, want in [
    ("rien ne change", [A, B], 0, B, 1),
    ("l'écran courant est débranché", [A], 0, B, 0),
    ("débranché, l'autre est le principal (indice 1)", [B], 0, A, 0),
    ("même nom, autre résolution", [A, ("Écran B", 1920, 0, 1920, 1080)], 0, B, 1),
    ("principal en deuxième", [B, A], 1, C, 1),
    ("aucun écran", [], 0, A, -1),
    ("indice principal hors limites (trop grand)", [A, B], 9, C, 1),
    ("indice principal négatif", [A, B], -3, C, 0),
    ("noms en double : le premier gagne", [("Écran A", 5, 5, 10, 10), ("Écran A", 0, 0, 1920, 1080)], 0, A, 1),
    ("même nom, rectangle différent, plusieurs", [("Écran B", 0, 0, 100, 100), ("Écran B", 1, 1, 100, 100)], 0, ("Écran B", 7, 7, 7, 7), 0),
]:
    sc_cases.append({"label": label, "screens": [list(s) for s in screens], "mainIndex": main_i, "current": list(cur), "expected": want})

write("scene-extras.json", {
    "description": "W6c+d : finitions de la Scène (karaokeSpec, FillMask, desiredGap, carte du titre, barre de commandes, sortie de ligne, repli d'écran) produites par scene-generator.py. ORDONNÉES VERS LE BAS. Lu par C# (W6cdParityTests) et par une transcription Swift (SceneFixtureTests) : ces formules vivent dans l'app Mac (AppModel, SceneView, SceneExtras, FillMask), hors de portée des tests. « particleBudget » : naissance 3,4/s × vie 8 s. Le repli d'écran (screenFallback) n'existe que côté Windows (le Mac n'a pas de cas équivalent) : lu par C# seulement.",
    "tolerance": 1e-9,
    "karaoke": karaoke, "fillPieces": pieces, "fillResync": resync, "barFormat": bar_format, "barFraction": bar_fraction, "barLayout": bar_layout,
    "lineExit": leave, "card": card, "cardTiming": card_timing, "gapWanted": gap_wanted,
    "particleBudget": {"birthRate": 3.4, "lifetime": 8.0, "budget": math.floor(3.4 * 8), "maximum": 30},
    "screenFallback": sc_cases})
print("scene-extras: karaoke", len(karaoke), ", pieces", len(pieces), ", resync", len(resync), ", barFormat", len(bar_format), ", barFraction", len(bar_fraction), ", barLayout", len(bar_layout),
      ", lineExit", len(leave), ", card", len(card), ", gapWanted", len(gap_wanted), ", screenFallback", len(sc_cases))
