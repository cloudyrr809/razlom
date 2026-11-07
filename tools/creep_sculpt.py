"""Детальные меши крипа в Blender: лицо, трещины-разломы вглубь, неровности, текстура.

Запуск (Blender без окна):
  "A:/SteamLibrary/steamapps/common/Blender/blender.exe" -b --factory-startup --python tools/creep_sculpt.py
Результат — tools/meshes/:
  CreepStem.glb, CreepCap.glb         — ножка и шляпка с текстурой (серой: цвет даёт игра)
  CreepStemGlow.glb, CreepCapGlow.glb — светящиеся сердцевины трещин, рта (Neon в игре)
  creep_meshes.json                   — рамки мешей в единицах генератора (для Config)
  preview_front.png, preview_back.png — проверочные картинки

Форма (профиль ножки, купол, край) — из Config.luau через creep_meshes.py, лицо — FaceXxx там же.
Единицы генератора: ножка — радиус крипа = 1, высота ножки = 1; шляпка — радиус = 1, высота = 1.
"""

import json
import math
import os
import sys

import bmesh
import bpy
import numpy as np

TOOLS = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, TOOLS)
import creep_meshes as C  # noqa: E402

OUT = os.path.join(TOOLS, "meshes")
os.makedirs(OUT, exist_ok=True)
F = {k: C.nums(k)[0] for k in ("FaceEyeAngle", "FaceEyeU", "FaceEyeW", "FaceEyeH", "FaceSocketDepth", "FaceEyeSlant", "FaceMouthU", "FaceMouthW")}
ASPECT = C.nums("FaceAspect")[0]  # высота ножки к её радиусу: чтобы круглое на лице было круглым
RNG = np.random.default_rng(7)
TAU = math.tau

# ---------------------------------------------------------------- шум


def _hash(ix, iy, iz, seed):
    h = (ix * 73856093) ^ (iy * 19349663) ^ (iz * 83492791) ^ (seed * 2654435761)
    h = (h ^ (h >> 13)) * 1274126177
    return ((h ^ (h >> 16)) & 0xFFFFFF).astype(np.float64) / 0xFFFFFF


def vnoise(p, seed=0):
    """Плавный шум 0..1 для точек p (N, 3)."""
    fl = np.floor(p)
    f = p - fl
    i = fl.astype(np.int64)
    s = f * f * (3 - 2 * f)
    out = 0.0
    for dx in (0, 1):
        for dy in (0, 1):
            for dz in (0, 1):
                w = (s[:, 0] if dx else 1 - s[:, 0]) * (s[:, 1] if dy else 1 - s[:, 1]) * (s[:, 2] if dz else 1 - s[:, 2])
                out = out + w * _hash(i[:, 0] + dx, i[:, 1] + dy, i[:, 2] + dz, seed)
    return out


def fbm(p, octaves=4, seed=0):
    total, amp, norm = 0.0, 1.0, 0.0
    for o in range(octaves):
        total = total + amp * (vnoise(p * (2 ** o), seed + o) - 0.5)
        norm += amp
        amp *= 0.5
    return total / norm * 2  # примерно −1..1


def wrap(a):
    return (a + math.pi) % TAU - math.pi


def seg_dist(px, py, ax, ay, bx, by):
    """Расстояние от точек (px, py) до отрезка AB и доля вдоль него."""
    vx, vy = bx - ax, by - ay
    ll = vx * vx + vy * vy + 1e-12
    t = np.clip(((px - ax) * vx + (py - ay) * vy) / ll, 0, 1)
    dx, dy = px - (ax + t * vx), py - (ay + t * vy)
    return np.sqrt(dx * dx + dy * dy), t


# ---------------------------------------------------------------- трещины


def crack_paths(starts, steps, step_len, jitter, branch_every, rng):
    """Зигзаги в плоских координатах (x вбок, y вдоль): [(точки, ширина, глубина)]."""
    paths = []
    for (x0, y0, heading, width, depth) in starts:
        pts = [(x0, y0)]
        h = heading
        for i in range(steps):
            h += rng.uniform(-jitter, jitter)
            x, y = pts[-1]
            pts.append((x + math.sin(h) * step_len, y + math.cos(h) * step_len))
            if i % branch_every == branch_every - 1 and i < steps - 1:
                bh = h + rng.choice([-1, 1]) * rng.uniform(0.6, 1.0)
                bp = [pts[-1]]
                for _ in range(max(2, steps // 3)):
                    bh += rng.uniform(-jitter, jitter)
                    bx, by = bp[-1]
                    bp.append((bx + math.sin(bh) * step_len * 0.8, by + math.cos(bh) * step_len * 0.8))
                paths.append((bp, width * 0.6, depth * 0.7))
        paths.append((pts, width, depth))
    return paths


def carve(px, py, paths):
    """Борозды по путям: возвращает (смещение, близость к трещине 0..1 для текстуры)."""
    d = np.zeros_like(px)
    near = np.zeros_like(px)
    for pts, width, depth in paths:
        n = len(pts) - 1
        for i in range(n):
            (ax, ay), (bx, by) = pts[i], pts[i + 1]
            dist, t = seg_dist(px, py, ax, ay, bx, by)
            k = 1 - (i + t) / n * 0.6  # сужается к концу
            w = width * k
            inside = np.clip(1 - dist / w, 0, 1)
            d = np.minimum(d, -depth * k * inside ** 0.6)
            # Рваный приподнятый край у разлома.
            d = d + 0.005 * k * np.exp(-((dist - w * 1.15) / (w * 0.35)) ** 2) * (dist > w)
            near = np.maximum(near, np.clip(1 - dist / (w * 2.6), 0, 1))
    return d, near


# ---------------------------------------------------------------- ножка

STEM_R = 0.6  # средний радиус ножки: угол × STEM_R — дуга для трещин
STEM_CRACKS = crack_paths(
    # x — угол от лица (0..2π) × STEM_R, y — высота × ASPECT. Сзади и по бокам, не по лицу.
    [(math.pi * 0.95 * STEM_R, 0.10, 0.15, 0.06, 0.14), (math.pi * 0.6 * STEM_R, 0.25, -0.2, 0.045, 0.11),
     (math.pi * 1.4 * STEM_R, 0.2, 0.25, 0.05, 0.12)],
    steps=7, step_len=0.12, jitter=0.55, branch_every=3, rng=RNG,
)


def stem_field(a, u):
    """Смещение поверхности ножки (доля радиуса) и маски для текстуры."""
    R = np.array([C.stem_radius(x) for x in np.atleast_1d(u).ravel()]).reshape(np.shape(u))
    X0, Y = a * R, u * ASPECT  # дуга и высота в одних единицах
    p = np.stack([np.sin(a) * R, Y, -np.cos(a) * R], axis=-1).reshape(-1, 3)
    d = (0.028 * fbm(p * 2.2, 3, 1) + 0.009 * fbm(p * 9.0, 2, 5)).reshape(np.shape(a))
    dark = np.zeros_like(d)  # где темнее (глазницы, рот, низ)

    # Корни-наплывы у земли.
    for ang in (0.3, 1.5, 2.6, 3.7, 5.0):
        da = wrap(a - ang)
        d += 0.07 * np.exp(-((da / 0.32) ** 2) - ((u / 0.07) ** 2))

    eu, ea, ew, eh = F["FaceEyeU"], F["FaceEyeAngle"], F["FaceEyeW"], F["FaceEyeH"]
    for side in (-1, 1):
        X = (wrap(a) - side * ea) * R
        Yl = (u - eu) * ASPECT
        # Глазница наклонена: внутренний угол (к середине лица) ниже — злой взгляд.
        c, s = math.cos(side * F["FaceEyeSlant"]), math.sin(side * F["FaceEyeSlant"])
        xr, yr = X * c + Yl * s, -X * s + Yl * c
        q = (xr / ew) ** 2 + (yr / eh) ** 2
        bowl = np.clip(1 - q, 0, 1)
        d -= F["FaceSocketDepth"] * bowl ** 0.8
        dark = np.maximum(dark, bowl ** 0.5 * 0.85)
        # Бровь: нависающий валик над глазом, внутренний конец опущен.
        inner = (side * 0.1, eu + 0.05)
        outer = (side * (ea + ew * 1.25), eu + 0.135)
        dist, _ = seg_dist(wrap(a) * R, u * ASPECT, inner[0], inner[1] * ASPECT, outer[0], outer[1] * ASPECT)
        d += 0.11 * np.exp(-((dist / 0.055) ** 2))
        # Скула под глазом.
        d += 0.03 * np.exp(-(((X - side * 0.05) / 0.13) ** 2) - (((Yl + 0.13) / 0.06) ** 2))
    # Морщина-складка между бровями.
    Xc = wrap(a) * R
    d -= 0.03 * np.exp(-((Xc / 0.025) ** 2)) * np.clip(1 - np.abs((u - eu - 0.08) * ASPECT) / 0.07, 0, 1)

    # Рот: злой оскал — уголки вниз, рваные края-зубы.
    mu, mw = F["FaceMouthU"], F["FaceMouthW"]
    xm = Xc / mw
    yc = (mu + 0.02) * ASPECT - 0.07 * xm ** 2
    tooth = np.abs(((Xc * 26) % 2) - 1)  # 0..1 пилой
    half = (0.04 + 0.028 * tooth) * np.clip(1 - xm ** 4, 0, 1)
    dist = np.abs(u * ASPECT - yc)
    open_ = np.clip(1 - dist / (half + 1e-6), 0, 1) * (np.abs(xm) < 1)
    d -= 0.13 * open_ ** 0.5
    d += 0.022 * np.exp(-(((dist - half - 0.012) / 0.014) ** 2)) * (np.abs(xm) < 1.05)  # губы
    dark = np.maximum(dark, open_ ** 0.4)

    # Трещины.
    cd, near = carve(np.mod(a, TAU) * STEM_R, u * ASPECT, STEM_CRACKS)
    return R, d + cd, dark, near


def stem_glow():
    """Сердцевины трещин и рта ножки: трубки на дне борозд. [(точки xyz, радиусы)]."""
    tubes = []
    for pts, width, depth in STEM_CRACKS:
        ring, radii = [], []
        for i, (x, y) in enumerate(pts):
            u = y / ASPECT
            R = C.stem_radius(u)
            a = x / STEM_R
            k = 1 - i / (len(pts) - 1) * 0.6
            rr = R * (1 - depth * k * 0.5)
            ring.append((math.sin(a) * rr, u, -math.cos(a) * rr))
            radii.append(width * k * 0.45)
        tubes.append((ring, radii))
    # Рот — светящаяся щель внутри оскала.
    mu, mw = F["FaceMouthU"], F["FaceMouthW"]
    pts, radii = [], []
    for i in range(17):
        xm = -0.92 + 1.84 * i / 16
        X = xm * mw
        u = ((mu + 0.02) * ASPECT - 0.07 * xm ** 2) / ASPECT
        R = C.stem_radius(u)
        a = X / R
        rr = R * (1 - 0.1)
        pts.append((math.sin(a) * rr, u, -math.cos(a) * rr))
        radii.append(0.035 * (1 - xm ** 4) + 0.008)
    tubes.append((pts, radii))
    return tubes


# ---------------------------------------------------------------- шляпка

CAP_CRACKS = crack_paths(
    # Вид сверху: x = k·sin(угол), y = k·cos(угол). От макушки к краю, расходятся лучами.
    [(r0 * math.sin(ang), r0 * math.cos(ang), ang, 0.055, 0.075) for ang, r0 in ((0.3, 0.22), (2.4, 0.3), (4.4, 0.18))],
    steps=8, step_len=0.11, jitter=0.6, branch_every=3, rng=RNG,
)
WARTS = [(RNG.uniform(0, TAU), RNG.uniform(0.2, 0.75), RNG.uniform(0.05, 0.085)) for _ in range(9)]


def cap_profile():
    """Контур шляпки сверху вниз: (k, y, номер точки на контуре 0..1, верх ли)."""
    b2 = C.BRIM[1]
    top = [(b2 * k, C.cap_top(b2 * k)) for k in np.linspace(0, 1, 120) ** 0.85]
    bottom = [(b2 * k, C.cap_bottom(b2 * k)) for k in (np.linspace(1, 0, 60) ** 0.85)]
    prof = top + bottom[1:]
    tag = [True] * len(top) + [False] * (len(bottom) - 1)
    return prof, tag


def cap_field(a, k, is_top):
    """Смещение по нормали (единицы шляпки) и маски для текстуры."""
    p = np.stack([np.sin(a) * k, np.where(is_top, 1.0, -1.0) * 0.3, -np.cos(a) * k], axis=-1).reshape(-1, 3)
    d = (0.018 * fbm(p * 3.0, 3, 11) + 0.006 * fbm(p * 11.0, 2, 17)).reshape(np.shape(a))
    wart = np.zeros_like(d)
    for (wa, wk, wr) in WARTS:
        dx = wrap(a - wa) * k
        dy = k - wk
        q = (dx * dx + dy * dy) / (wr * wr)
        bump = np.exp(-q * 2.2) * is_top
        d += 0.045 * bump
        wart = np.maximum(wart, bump)
    # Пластинки снизу: тонкие радиальные рёбра.
    gill = np.clip(np.cos(a * 34), 0, 1) ** 10 * (~is_top) * np.clip((k - 0.22) / 0.1, 0, 1) * np.clip((0.97 - k) / 0.05, 0, 1)
    d += 0.035 * gill
    cd, near = carve(k * np.sin(a), k * np.cos(a), CAP_CRACKS)
    d += cd * is_top
    return d, wart, gill, near * is_top


def cap_glow():
    tubes = []
    for pts, width, depth in CAP_CRACKS:
        ring, radii = [], []
        for i, (x, y) in enumerate(pts):
            k = min(math.hypot(x, y), 0.97)
            s = k / max(math.hypot(x, y), 1e-6)
            kk = 1 - i / (len(pts) - 1) * 0.6
            yy = C.cap_top(C.BRIM[1] * k) - depth * kk * 0.45
            ring.append((x * s, yy, -y * s))
            radii.append(width * kk * 0.45)
        tubes.append((ring, radii))
    return tubes


# ---------------------------------------------------------------- сборка в Blender


def grid_mesh(name, pos, uv_u, uv_v, wrap_u=True):
    """pos (NV, NU, 3) в координатах игры (Y вверх, перёд −Z); кольца по NU, точки кольца по NV."""
    nu, nv = pos.shape[0], pos.shape[1]
    bm = bmesh.new()
    verts = []
    for row in pos:
        if np.allclose(row[:, [0, 2]], 0):  # полюс — одна вершина на оси
            v = bm.verts.new((0.0, 0.0, float(row[0, 1])))
            verts.append([v] * nv)
        else:
            verts.append([bm.verts.new((p[0], -p[2], p[1])) for p in row])  # в Blender Z вверх
    uvl = bm.loops.layers.uv.new("UVMap")
    for j in range(nu - 1):
        for i in range(nv if wrap_u else nv - 1):
            i2 = (i + 1) % nv
            ui2 = 1.0 if i2 == 0 else uv_u[i2]
            corners = [(verts[j][i], (uv_u[i], uv_v[j])), (verts[j][i2], (ui2, uv_v[j])),
                       (verts[j + 1][i2], (ui2, uv_v[j + 1])), (verts[j + 1][i], (uv_u[i], uv_v[j + 1]))]
            uniq = []
            for v, uv in corners:
                if all(v is not w for w, _ in uniq):
                    uniq.append((v, uv))
            if len(uniq) < 3:
                continue
            try:
                f = bm.faces.new([v for v, _ in uniq])
            except ValueError:
                continue
            for loop, (_, uv) in zip(f.loops, uniq):
                loop[uvl].uv = uv
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    obj = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(obj)
    for poly in me.polygons:
        poly.use_smooth = True
    return obj


def tube_mesh(name, tubes, sides=6):
    bm = bmesh.new()
    for pts, radii in tubes:
        pts = [np.array(p) for p in pts]
        rings = []
        for i, p in enumerate(pts):
            t = pts[min(i + 1, len(pts) - 1)] - pts[max(i - 1, 0)]
            t = t / (np.linalg.norm(t) + 1e-9)
            up = np.array([0.0, 1.0, 0.0]) if abs(t[1]) < 0.9 else np.array([1.0, 0.0, 0.0])
            n1 = np.cross(t, up)
            n1 /= np.linalg.norm(n1)
            n2 = np.cross(t, n1)
            r = radii[i] * (0.3 if i in (0, len(pts) - 1) else 1.0)
            ring = []
            for s in range(sides):
                ang = s / sides * TAU
                q = p + (n1 * math.cos(ang) + n2 * math.sin(ang)) * r
                ring.append(bm.verts.new((q[0], -q[2], q[1])))
            rings.append(ring)
        for j in range(len(rings) - 1):
            for s in range(sides):
                s2 = (s + 1) % sides
                bm.faces.new((rings[j][s], rings[j][s2], rings[j + 1][s2], rings[j + 1][s]))
        bm.faces.new(list(reversed(rings[0])))
        bm.faces.new(rings[-1])
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    obj = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(obj)
    for poly in me.polygons:
        poly.use_smooth = True
    return obj


def image(name, rgb):
    h, w, _ = rgb.shape
    img = bpy.data.images.new(name, width=w, height=h, alpha=False)
    rgba = np.concatenate([np.clip(rgb, 0, 1), np.ones((h, w, 1))], axis=2)
    img.pixels.foreach_set(rgba.astype(np.float32).ravel())
    img.filepath_raw = os.path.join(OUT, name + ".png")
    img.file_format = "PNG"
    img.save()
    return img


def textured(obj, img, emit=None):
    mat = bpy.data.materials.new(obj.name + "Mat")
    mat.use_nodes = True
    nodes = mat.node_tree.nodes
    bsdf = nodes.get("Principled BSDF")
    if img is not None:
        tex = nodes.new("ShaderNodeTexImage")
        tex.image = img
        mat.node_tree.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    if emit is not None:
        bsdf.inputs["Base Color"].default_value = (*emit, 1)
    bsdf.inputs["Roughness"].default_value = 0.85
    obj.data.materials.append(mat)


def decimate(obj, tris):
    now = sum(len(p.vertices) - 2 for p in obj.data.polygons)
    if now <= tris:
        return
    m = obj.modifiers.new("dec", "DECIMATE")
    m.ratio = tris / now
    m.use_collapse_triangulate = True
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.modifier_apply(modifier=m.name)


# Общие рамки (координаты игры): ножка и её свечение, шляпка и её свечение.
# Roblox ставит меш по центру его рамки — с якорями рамка известна заранее и одинакова у пары.
FRAMES = {"stem": ((-1.0, -0.02, -1.0), (1.0, 1.02, 1.0)), "cap": ((-1.1, -0.36, -1.1), (1.1, 0.75, 1.1))}


def anchor(obj, frame):
    """Две крошечные пирамидки в углах рамки: невидимы, но задают рамку меша."""
    lo, hi = FRAMES[frame]
    co = np.empty(len(obj.data.vertices) * 3)
    obj.data.vertices.foreach_get("co", co)
    co = co.reshape(-1, 3)
    g = np.stack([co[:, 0], co[:, 2], -co[:, 1]], 1)  # Blender -> игра
    assert (g.min(0) >= np.array(lo) - 1e-6).all() and (g.max(0) <= np.array(hi) + 1e-6).all(), (frame, g.min(0), g.max(0))
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    e = 0.002
    for corner, sign in ((lo, 1), (hi, -1)):
        x, y, z = corner
        pts = [(x, y, z), (x + sign * e, y, z), (x, y + sign * e, z), (x, y, z + sign * e)]
        vs = [bm.verts.new((p[0], -p[2], p[1])) for p in pts]
        for tri in ((0, 1, 2), (0, 1, 3), (0, 2, 3), (1, 2, 3)):
            bm.faces.new([vs[i] for i in tri])
    bm.to_mesh(obj.data)
    bm.free()
    return {"min": list(lo), "max": list(hi)}


def export(obj, name):
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.export_scene.gltf(filepath=os.path.join(OUT, name + ".glb"), use_selection=True, export_format="GLB",
                              export_yup=True, export_apply=True, export_texcoords=True, export_normals=True,
                              export_materials="EXPORT")
    tris = sum(len(p.vertices) - 2 for p in obj.data.polygons)
    print(f"{name}: {tris} треугольников")
    return tris


def shade(x):
    return np.clip(x, 0, 1.15)


def build():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    boxes = {}

    # Ножка: сетка (высота × угол), смещение радиуса.
    NA, NU = 256, 150
    a = np.linspace(-math.pi, math.pi, NA, endpoint=False)
    u = np.linspace(0, 1, NU)
    A, U = np.meshgrid(a, u)
    R, d, _, _ = stem_field(A, U)
    rr = R * (1 + d)
    pos = np.stack([np.sin(A) * rr, U, -np.cos(A) * rr], axis=-1)
    # Крышка сверху и дно — точками на оси.
    pos = np.concatenate([np.zeros((1, NA, 3)) + [0, 0, 0], pos, np.zeros((1, NA, 3)) + [0, 1, 0]], axis=0)
    uv_v = np.concatenate([[0.0], u, [1.0]])
    stem = grid_mesh("CreepStem", pos, (a + math.pi) / TAU, uv_v)

    # Текстура ножки: развёртка по углу (ширина) и высоте.
    TW, TH = 1024, 512
    ta = np.linspace(-math.pi, math.pi, TW, endpoint=False) + math.pi / TW
    tu = np.linspace(0, 1, TH)
    TA, TU = np.meshgrid(ta, tu)
    _, td, dark, near = stem_field(TA, TU)
    p = np.stack([np.sin(TA), TU * ASPECT * 4, -np.cos(TA)], axis=-1).reshape(-1, 3)
    fiber = fbm(p * np.array([6, 1.5, 6]), 3, 23).reshape(TA.shape)  # продольные волокна
    sp = np.stack([np.sin(TA) * 0.6, TU * ASPECT, -np.cos(TA) * 0.6], -1).reshape(-1, 3)
    speck = (0.6 * vnoise(sp * 22, 31) + 0.4 * vnoise(sp * 45, 37)).reshape(TA.shape)
    s = 0.93 + 0.06 * fiber
    s *= 1 - 0.2 * np.clip((speck - 0.62) / 0.08, 0, 1)
    s *= 1 + np.clip(td, -0.15, 0.08) * 2.2  # впадины темнее, бугры светлее
    s *= 1 - 0.55 * near  # края разломов закопчены
    s *= 1 - 0.75 * dark  # глазницы и рот тёмные
    s *= 0.72 + 0.28 * np.clip(TU / 0.16, 0, 1)  # у земли грязнее
    s *= 0.82 + 0.18 * np.clip((1 - TU) / 0.12, 0, 1)  # под шляпкой тень
    rgb = np.stack([shade(s), shade(s * 0.97), shade(s * 0.92)], axis=-1)
    stem_img = image("CreepStemTex", rgb)  # строка 0 — низ картинки = низ ножки (v = 0)
    textured(stem, stem_img)
    decimate(stem, 7000)
    boxes["Stem"] = anchor(stem, "stem")
    boxes["Stem"]["tris"] = export(stem, "CreepStem")

    glow = tube_mesh("CreepStemGlow", stem_glow())
    textured(glow, None, (0.6, 1, 1))
    boxes["StemGlow"] = anchor(glow, "stem")
    boxes["StemGlow"]["tris"] = export(glow, "CreepStemGlow")

    # Шляпка: контур × угол, смещение по нормали контура.
    prof, tag = cap_profile()
    ks = np.array([p[0] for p in prof])
    ys = np.array([p[1] for p in prof])
    tops = np.array(tag)
    # Нормаль контура (наружу): поворот касательной.
    tk = np.gradient(ks)
    ty = np.gradient(ys)
    nk, ny = -ty, tk  # наружу: на верху — вверх, на низу — вниз
    ln = np.sqrt(nk * nk + ny * ny) + 1e-9
    nk, ny = nk / ln, ny / ln
    NA2 = 300
    a2 = np.linspace(-math.pi, math.pi, NA2, endpoint=False)
    A2, K = np.meshgrid(a2, ks)
    TOP = np.repeat(tops[:, None], NA2, axis=1)
    cd, _, _, _ = cap_field(A2, K, TOP)
    wave = 1 + C.WAVE_AMP * np.sin(C.WAVE_COUNT * A2) * (K / C.BRIM[1]) ** 4
    kk = (K + nk[:, None] * cd) * wave
    yy = ys[:, None] + ny[:, None] * cd
    cpos = np.stack([np.sin(A2) * kk, yy, -np.cos(A2) * kk], axis=-1)
    # Полюса: макушка и низ у ножки.
    cpos[0, :, 0] = 0
    cpos[0, :, 2] = 0
    cpos[-1, :, 0] = 0
    cpos[-1, :, 2] = 0
    tv = np.linspace(0, 1, len(prof))
    cap = grid_mesh("CreepCap", cpos, (a2 + math.pi) / TAU, tv)

    TW2, TH2 = 1024, 512
    ta2 = np.linspace(-math.pi, math.pi, TW2, endpoint=False) + math.pi / TW2
    tvv = np.linspace(0, 1, TH2)
    TA2 = np.repeat(ta2[None, :], TH2, axis=0)
    TK = np.interp(tvv, tv, ks)[:, None].repeat(TW2, 1)  # плавно по контуру, без ступенек
    TT = (np.interp(tvv, tv, tops.astype(float)) > 0.5)[:, None].repeat(TW2, 1)
    ccd, wart, gill, cnear = cap_field(TA2, TK, TT)
    p = np.stack([np.sin(TA2) * TK * 5, TT * 3.0, -np.cos(TA2) * TK * 5], -1).reshape(-1, 3)
    mott = fbm(p, 4, 41).reshape(TA2.shape)  # пятнистость
    sp2 = np.stack([np.sin(TA2) * TK, TT * 3.0, -np.cos(TA2) * TK], -1).reshape(-1, 3)
    speck = (0.6 * vnoise(sp2 * 26, 43) + 0.4 * vnoise(sp2 * 55, 47)).reshape(TA2.shape)
    s = np.where(TT, 1.0 - 0.28 * np.clip((TK - 0.25) / 0.75, 0, 1), 0.55 - 0.25 * gill)
    s *= 0.94 + 0.08 * mott
    s *= 1 - 0.18 * np.clip((speck - 0.64) / 0.08, 0, 1)
    s = s + 0.22 * wart  # бугры-бородавки светлее
    s *= 1 + np.clip(ccd, -0.12, 0) * 2.5
    s *= 1 - 0.6 * cnear
    rgb2 = np.stack([shade(s), shade(s * 0.96), shade(s * 0.9)], axis=-1)
    cap_img = image("CreepCapTex", rgb2)
    textured(cap, cap_img)
    decimate(cap, 8000)
    boxes["Cap"] = anchor(cap, "cap")
    boxes["Cap"]["tris"] = export(cap, "CreepCap")

    cglow = tube_mesh("CreepCapGlow", cap_glow())
    textured(cglow, None, (0.6, 1, 1))
    boxes["CapGlow"] = anchor(cglow, "cap")
    boxes["CapGlow"]["tris"] = export(cglow, "CreepCapGlow")

    with open(os.path.join(OUT, "creep_meshes.json"), "w", encoding="utf-8") as f:
        json.dump(boxes, f, indent=1)
    return boxes


# ---------------------------------------------------------------- проверочный рендер


def preview(boxes):
    """Собирает крипа как в игре (средний размер) и рендерит спереди и сзади."""
    scene = bpy.context.scene
    sw, stem_h, y0 = 1.0, 1.19, -0.05  # средний крип в радиусах
    cap_r, cap_h, cap_y = 1.1, 0.85, 1.15

    def place(name, unit, origin):
        # Вершины уже в координатах генератора: масштаб и сдвиг начала, как в игре.
        obj = bpy.data.objects[name]
        obj.scale = (unit[0], unit[2], unit[1])
        obj.location = (origin[0], -origin[2], origin[1])

    place("CreepStem", (sw, stem_h, sw), (0, y0, 0))
    place("CreepStemGlow", (sw, stem_h, sw), (0, y0, 0))
    place("CreepCap", (cap_r, cap_h, cap_r), (0, cap_y, 0))
    place("CreepCapGlow", (cap_r, cap_h, cap_r), (0, cap_y, 0))
    for name in ("CreepStem", "CreepCap"):
        mat = bpy.data.objects[name].data.materials[0]
        tint = (0.86, 0.8, 0.68, 1) if name == "CreepStem" else (0.75, 0.52, 0.34, 1)
        nodes = mat.node_tree.nodes
        # Цвет как в игре: серая текстура × цвет крипа.
        mul = nodes.new("ShaderNodeVectorMath")
        mul.operation = "MULTIPLY"
        mul.inputs[1].default_value = tint[:3]
        tex = [n for n in nodes if n.type == "TEX_IMAGE"][0]
        mat.node_tree.links.new(tex.outputs["Color"], mul.inputs[0])
        mat.node_tree.links.new(mul.outputs[0], nodes["Principled BSDF"].inputs["Base Color"])
    for name in ("CreepStemGlow", "CreepCapGlow"):
        bsdf = bpy.data.objects[name].data.materials[0].node_tree.nodes["Principled BSDF"]
        bsdf.inputs["Emission Color"].default_value = (0.4, 1, 1, 1)
        bsdf.inputs["Emission Strength"].default_value = 6

    # Глаза в глазницах — как их ставит игра (светящаяся капля и тёмный зрачок-щель).
    for side in (-1, 1):
        a = side * F["FaceEyeAngle"]
        u = F["FaceEyeU"]
        R = C.stem_radius(u) * (1 - F["FaceSocketDepth"] * 0.55)
        loc = (math.sin(a) * R * sw, math.cos(a) * R * sw, y0 + u * stem_h)
        for nm, sc, col, push in (("Eye", (F["FaceEyeW"] * 0.85, 0.06, F["FaceEyeH"] * 1.2), (0.4, 1, 1), 0.0),
                                  ("Pupil", (0.025, 0.05, F["FaceEyeH"] * 1.0), (0.02, 0.03, 0.04), 0.035)):
            bpy.ops.mesh.primitive_uv_sphere_add(radius=1, location=(loc[0] + math.sin(a) * push, loc[1] + math.cos(a) * push, loc[2]))
            o = bpy.context.active_object
            o.scale = sc
            o.rotation_euler = (0, side * F["FaceEyeSlant"] * 0.6, -a)
            m = bpy.data.materials.new(nm)
            m.use_nodes = True
            b = m.node_tree.nodes["Principled BSDF"]
            b.inputs["Base Color"].default_value = (*col, 1)
            if nm == "Eye":
                b.inputs["Emission Color"].default_value = (*col, 1)
                b.inputs["Emission Strength"].default_value = 4
            o.data.materials.append(m)

    world = bpy.data.worlds.new("W")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.55, 0.7, 0.9, 1)
    world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.6
    scene.world = world
    sun = bpy.data.objects.new("Sun", bpy.data.lights.new("Sun", "SUN"))
    sun.data.energy = 3.5
    sun.rotation_euler = (math.radians(50), 0, math.radians(30))
    scene.collection.objects.link(sun)
    cam = bpy.data.objects.new("Cam", bpy.data.cameras.new("Cam"))
    scene.collection.objects.link(cam)
    scene.camera = cam
    scene.render.engine = "BLENDER_EEVEE_NEXT" if "BLENDER_EEVEE_NEXT" in {e.identifier for e in bpy.types.RenderSettings.bl_rna.properties["engine"].enum_items} else "BLENDER_EEVEE"
    scene.render.resolution_x, scene.render.resolution_y = 900, 900
    for tag, ang in (("front", 0.35), ("back", math.pi + 0.5)):
        # Перёд крипа смотрит в −Z игры = +Y Blender.
        d = 4.2
        cam.location = (math.sin(ang) * d, math.cos(ang) * d, 1.6)
        target = np.array([0, 0, 0.95])
        direction = target - np.array(cam.location)
        cam.rotation_euler = direction_to_euler(direction)
        scene.render.filepath = os.path.join(OUT, f"preview_{tag}.png")
        bpy.ops.render.render(write_still=True)


def direction_to_euler(v):
    from mathutils import Vector
    return Vector(v).to_track_quat("-Z", "Y").to_euler()


if __name__ == "__main__":
    b = build()
    print(json.dumps(b))
    preview(b)
