#!/usr/bin/env python3
"""
FlightPathPrint — turn a GPS flight log into a 3D-printable memento.

Generates a shadow-box style model of a flight: a stepped topographic
terrain map with flat water, the flight path (position + altitude) swept
as a tube above it, a picture frame around everything, and a raised-text
plaque on the front bezel (title / date / route).

Outputs one binary STL per color so the model can be printed
multi-material (or the parts printed separately and assembled):

    frame.stl        black
    water.stl        blue
    terrain.stl      olive green
    flight_path.stl  neon yellow
    text.stl         white
    all_in_one.stl   every part merged (single-color reference)
    preview.png      top-down render for a quick sanity check

Usage:
    python3 flightpath_print.py --demo
    python3 flightpath_print.py --gpx myflight.gpx \
        --title "Discovery Flight" --route "HWD - Bay Tour - HWD"

Real terrain comes from the free AWS Terrain Tiles dataset (terrarium
encoding) and needs network access; --demo generates a synthetic bay so
everything can be tested offline.

Dependencies: numpy, pillow (and requests for --gpx terrain download).
"""

import argparse
import math
import os
import struct
import sys
from datetime import datetime

import numpy as np
from PIL import Image, ImageDraw, ImageFont

# ---------------------------------------------------------------------------
# Mesh primitives.  All meshes are float arrays of shape (n, 3, 3):
# n triangles, 3 vertices, xyz in millimetres.  Winding is CCW viewed
# from outside the solid.
# ---------------------------------------------------------------------------


def _stack(x, y, z):
    """Broadcast x, y, z into an (n, 3) vertex array."""
    x, y, z = np.broadcast_arrays(x, y, z)
    return np.stack([x, y, z], axis=-1).astype(float)


def _quads(p0, p1, p2, p3):
    """Two triangles per quad; quad vertices given CCW from outside."""
    p0, p1, p2, p3 = (np.atleast_2d(p) for p in (p0, p1, p2, p3))
    t1 = np.stack([p0, p1, p2], axis=1)
    t2 = np.stack([p0, p2, p3], axis=1)
    return np.concatenate([t1, t2], axis=0)


def box_mesh(x0, x1, y0, y1, z0, z1):
    """Axis-aligned solid box."""
    tris = [
        _quads((x0, y0, z1), (x1, y0, z1), (x1, y1, z1), (x0, y1, z1)),  # top
        _quads((x0, y0, z0), (x0, y1, z0), (x1, y1, z0), (x1, y0, z0)),  # bottom
        _quads((x1, y0, z0), (x1, y1, z0), (x1, y1, z1), (x1, y0, z1)),  # +x
        _quads((x0, y1, z0), (x0, y0, z0), (x0, y0, z1), (x0, y1, z1)),  # -x
        _quads((x1, y1, z0), (x0, y1, z0), (x0, y1, z1), (x1, y1, z1)),  # +y
        _quads((x0, y0, z0), (x1, y0, z0), (x1, y0, z1), (x0, y0, z1)),  # -y
    ]
    return np.concatenate(tris, axis=0)


def heightfield_columns(top_z, z0, x0, y0, dx):
    """
    Solid square columns for every finite cell of top_z (NaN = empty),
    rising from z0 to top_z[i, j].  Cell (i, j) occupies
    x ∈ [x0 + j*dx, x0 + (j+1)*dx], y ∈ [y0 + i*dx, y0 + (i+1)*dx].
    Shared interior walls are skipped, so the result is a clean stepped
    surface rather than 40k separate cubes.
    """
    top_z = np.asarray(top_z, float)
    ny, nx = top_z.shape
    occ = np.isfinite(top_z)
    if not occ.any():
        return np.zeros((0, 3, 3))

    out = []
    iy, ix = np.nonzero(occ)
    xa = x0 + ix * dx
    ya = y0 + iy * dx
    zt = top_z[iy, ix]
    zb = np.full_like(zt, z0)

    out.append(_quads(_stack(xa, ya, zt), _stack(xa + dx, ya, zt),
                      _stack(xa + dx, ya + dx, zt), _stack(xa, ya + dx, zt)))
    out.append(_quads(_stack(xa, ya, zb), _stack(xa, ya + dx, zb),
                      _stack(xa + dx, ya + dx, zb), _stack(xa + dx, ya, zb)))

    pad = np.full((ny + 2, nx + 2), np.nan)
    pad[1:-1, 1:-1] = top_z

    for dyy, dxx in ((0, 1), (0, -1), (1, 0), (-1, 0)):
        nbr = pad[1 + dyy:ny + 1 + dyy, 1 + dxx:nx + 1 + dxx]
        nbr_eff = np.where(np.isfinite(nbr), nbr, z0)
        m = occ & (top_z > nbr_eff + 1e-9)
        if not m.any():
            continue
        jy, jx = np.nonzero(m)
        zlo = nbr_eff[jy, jx]
        zhi = top_z[jy, jx]
        X = x0 + jx * dx
        Y = y0 + jy * dx
        if (dyy, dxx) == (0, 1):      # east wall, normal +x
            q = (_stack(X + dx, Y, zlo), _stack(X + dx, Y + dx, zlo),
                 _stack(X + dx, Y + dx, zhi), _stack(X + dx, Y, zhi))
        elif (dyy, dxx) == (0, -1):   # west wall, normal -x
            q = (_stack(X, Y + dx, zlo), _stack(X, Y, zlo),
                 _stack(X, Y, zhi), _stack(X, Y + dx, zhi))
        elif (dyy, dxx) == (1, 0):    # north wall, normal +y
            q = (_stack(X + dx, Y + dx, zlo), _stack(X, Y + dx, zlo),
                 _stack(X, Y + dx, zhi), _stack(X + dx, Y + dx, zhi))
        else:                         # south wall, normal -y
            q = (_stack(X, Y, zlo), _stack(X + dx, Y, zlo),
                 _stack(X + dx, Y, zhi), _stack(X, Y, zhi))
        out.append(_quads(*q))

    return np.concatenate(out, axis=0)


def tube_mesh(points, radius, sides=14):
    """Sweep a circle along a polyline using parallel-transport frames."""
    P = np.asarray(points, float)
    seg = np.linalg.norm(np.diff(P, axis=0), axis=1)
    P = P[np.concatenate([[True], seg > 1e-6])]
    m = len(P)
    if m < 2:
        return np.zeros((0, 3, 3))

    T = np.empty_like(P)
    T[1:-1] = P[2:] - P[:-2]
    T[0] = P[1] - P[0]
    T[-1] = P[-1] - P[-2]
    T /= np.linalg.norm(T, axis=1, keepdims=True)

    ref = np.array([0.0, 0.0, 1.0])
    if abs(T[0] @ ref) > 0.9:
        ref = np.array([1.0, 0.0, 0.0])
    N = np.empty_like(P)
    n0 = np.cross(T[0], ref)
    N[0] = n0 / np.linalg.norm(n0)
    for i in range(1, m):
        n = N[i - 1] - T[i] * (T[i] @ N[i - 1])
        ln = np.linalg.norm(n)
        if ln < 1e-9:
            n = np.cross(T[i], ref)
            ln = np.linalg.norm(n)
        N[i] = n / ln
    B = np.cross(T, N)

    ang = np.linspace(0.0, 2.0 * math.pi, sides, endpoint=False)
    rings = (P[:, None, :]
             + radius * np.cos(ang)[None, :, None] * N[:, None, :]
             + radius * np.sin(ang)[None, :, None] * B[:, None, :])

    a, b = rings[:-1], rings[1:]
    a2 = np.roll(a, -1, axis=1)
    b2 = np.roll(b, -1, axis=1)
    side_tris = np.concatenate([
        np.stack([a, a2, b2], axis=2).reshape(-1, 3, 3),
        np.stack([a, b2, b], axis=2).reshape(-1, 3, 3),
    ])

    caps = []
    r0, r1 = rings[0], rings[-1]
    c0 = np.repeat(P[0][None], sides, axis=0)
    c1 = np.repeat(P[-1][None], sides, axis=0)
    caps.append(np.stack([c0, np.roll(r0, -1, axis=0), r0], axis=1))
    caps.append(np.stack([c1, r1, np.roll(r1, -1, axis=0)], axis=1))
    return np.concatenate([side_tris] + caps, axis=0)


def write_stl(path, tris, name=b"FlightPathPrint"):
    tris = np.ascontiguousarray(tris, dtype=np.float32)
    n = len(tris)
    e1 = tris[:, 1] - tris[:, 0]
    e2 = tris[:, 2] - tris[:, 0]
    nrm = np.cross(e1, e2)
    ln = np.linalg.norm(nrm, axis=1, keepdims=True)
    ln[ln == 0] = 1.0
    nrm = (nrm / ln).astype(np.float32)
    rec = np.zeros(n, dtype=[("n", "<f4", 3), ("v", "<f4", (3, 3)), ("a", "<u2")])
    rec["n"] = nrm
    rec["v"] = tris
    with open(path, "wb") as f:
        f.write(name.ljust(80, b" ")[:80])
        f.write(struct.pack("<I", n))
        f.write(rec.tobytes())
    return n


# ---------------------------------------------------------------------------
# Track input: GPX parsing and the synthetic demo flight.
# ---------------------------------------------------------------------------


def parse_gpx(path):
    """Return (lat, lon, ele arrays, duration_minutes or None, date or None)."""
    import xml.etree.ElementTree as ET

    root = ET.parse(path).getroot()
    lats, lons, eles, times = [], [], [], []
    for el in root.iter():
        if el.tag.endswith("trkpt") or el.tag.endswith("rtept"):
            lats.append(float(el.get("lat")))
            lons.append(float(el.get("lon")))
            ele, t = 0.0, None
            for c in el:
                if c.tag.endswith("ele") and c.text:
                    ele = float(c.text)
                elif c.tag.endswith("time") and c.text:
                    t = c.text
            eles.append(ele)
            times.append(t)
    if len(lats) < 2:
        sys.exit(f"error: no track points found in {path}")

    duration = date = None
    stamps = [t for t in times if t]
    if len(stamps) >= 2:
        try:
            t0 = datetime.fromisoformat(stamps[0].replace("Z", "+00:00"))
            t1 = datetime.fromisoformat(stamps[-1].replace("Z", "+00:00"))
            duration = max(1, round((t1 - t0).total_seconds() / 60))
            date = t0.strftime("%-d %B %Y").upper()
        except ValueError:
            pass
    if not any(eles):
        print("warning: GPX has no <ele> data; flight path will hug the terrain")
    return np.array(lats), np.array(lons), np.array(eles), duration, date


def _fbm(ny, nx, octaves=5, seed=7):
    """Cheap fractal noise: stacked random grids upsampled bicubically."""
    rng = np.random.default_rng(seed)
    out = np.zeros((ny, nx))
    amp, total = 1.0, 0.0
    for o in range(octaves):
        n = 2 ** (o + 2)
        g = rng.standard_normal((n, n)).astype(np.float32)
        img = Image.fromarray(g, "F").resize((nx, ny), Image.BICUBIC)
        out += amp * np.asarray(img)
        total += amp
        amp *= 0.55
    return out / total


def demo_terrain(ny, nx):
    """Synthetic coastal terrain: a diagonal bay between two hilly shores."""
    v, u = np.meshgrid(np.linspace(0, 1, ny), np.linspace(0, 1, nx), indexing="ij")
    # Bay centerline drifts west as it goes north, widening toward the south.
    uc = 0.50 - 0.22 * v + 0.06 * np.sin(3.0 * v)
    half_w = 0.11 + 0.07 * (1.0 - v)
    d = np.abs(u - uc) - half_w
    elev = d * 2600.0 * (0.55 + 0.45 * _fbm(ny, nx, seed=11))
    elev += 130.0 * _fbm(ny, nx, seed=7)
    # A western shore strip so the bay reads as a channel, not open ocean.
    elev = np.maximum(elev, (0.10 - u) * 3000.0 + 90.0 * _fbm(ny, nx, seed=23))
    # Small inlet notch at the top-left, Golden-Gate style.
    gate = (np.abs(v - 0.90) < 0.045) & (u < uc + 0.05)
    elev[gate] = -30.0
    return elev


def demo_track():
    """A plausible 'bay tour' in normalized map coords: (u, v, ele_m)."""
    pts = []

    def leg(p0, p1, n):
        for t in np.linspace(0, 1, n, endpoint=False):
            pts.append((p0[0] + (p1[0] - p0[0]) * t, p0[1] + (p1[1] - p0[1]) * t))

    def arc(c, r, a0, a1, n):
        for a in np.linspace(a0, a1, n, endpoint=False):
            pts.append((c[0] + r * math.cos(a), c[1] + r * math.sin(a)))

    apt = (0.82, 0.14)                       # home airport, SE shore
    leg(apt, (0.70, 0.28), 12)               # takeoff, turn out toward the bay
    leg((0.70, 0.28), (0.40, 0.68), 40)      # cruise NW up the bay
    arc((0.33, 0.78), 0.105, -0.7, 2.6, 30)  # sweep around the north end
    arc((0.26, 0.86), 0.055, 2.6, 8.9, 34)   # tight sightseeing circle
    leg((0.30, 0.79), (0.58, 0.40), 36)      # cruise back SE
    arc((0.665, 0.305), 0.075, 2.3, -3.6, 26)  # 360 over the shoreline
    leg((0.71, 0.24), apt, 14)               # final approach
    pts.append(apt)

    P = np.array(pts)
    # Altitude profile: climb, cruise at ~1500 ft, descend, land.
    s = np.concatenate([[0], np.cumsum(np.linalg.norm(np.diff(P, axis=0), axis=1))])
    s /= s[-1]
    climb = np.clip(s / 0.14, 0, 1)
    descend = np.clip((1 - s) / 0.12, 0, 1)
    ele = 12.0 + 445.0 * np.minimum(climb, descend) ** 1.5
    ele += 55.0 * np.sin(9.0 * math.pi * s) * (s > 0.3) * (s < 0.75)
    return P[:, 0], P[:, 1], ele


# ---------------------------------------------------------------------------
# Real terrain: AWS Terrain Tiles (terrarium PNG encoding, no API key).
# ---------------------------------------------------------------------------

TILE_URL = "https://s3.amazonaws.com/elevation-tiles-prod/terrarium/{z}/{x}/{y}.png"


def _merc(lat, lon, z):
    n = 2.0 ** z
    x = (lon + 180.0) / 360.0 * n
    lat_r = np.radians(lat)
    y = (1.0 - np.arcsinh(np.tan(lat_r)) / math.pi) / 2.0 * n
    return x, y


def fetch_terrain(lat0, lat1, lon0, lon1, ny, nx, zoom=None, cache_dir=None):
    """Sample real-world elevation (m) on an (ny, nx) grid over the bbox."""
    import requests

    lat_c = (lat0 + lat1) / 2.0
    cell_m = (lon1 - lon0) * 111320.0 * math.cos(math.radians(lat_c)) / nx
    if zoom is None:
        zoom = int(math.log2(156543.0 * math.cos(math.radians(lat_c)) / max(cell_m, 1.0)))
        zoom = max(6, min(13, zoom))

    x0f, y1f = _merc(lat0, lon0, zoom)  # south-west corner (larger tile y)
    x1f, y0f = _merc(lat1, lon1, zoom)
    tx0, tx1 = int(x0f), int(x1f)
    ty0, ty1 = int(y0f), int(y1f)

    cache_dir = cache_dir or os.path.join(
        os.path.expanduser("~"), ".cache", "flightpath_tiles")
    os.makedirs(cache_dir, exist_ok=True)

    mosaic = np.zeros(((ty1 - ty0 + 1) * 256, (tx1 - tx0 + 1) * 256))
    sess = requests.Session()
    sess.headers["User-Agent"] = "FlightPathPrint/1.0"
    n_tiles = (tx1 - tx0 + 1) * (ty1 - ty0 + 1)
    print(f"terrain: zoom {zoom}, downloading {n_tiles} tile(s)...")
    for ty in range(ty0, ty1 + 1):
        for tx in range(tx0, tx1 + 1):
            cpath = os.path.join(cache_dir, f"{zoom}_{tx}_{ty}.png")
            if not os.path.exists(cpath):
                r = sess.get(TILE_URL.format(z=zoom, x=tx, y=ty), timeout=30)
                r.raise_for_status()
                with open(cpath, "wb") as f:
                    f.write(r.content)
            rgb = np.asarray(Image.open(cpath).convert("RGB"), float)
            elev = rgb[:, :, 0] * 256.0 + rgb[:, :, 1] + rgb[:, :, 2] / 256.0 - 32768.0
            mosaic[(ty - ty0) * 256:(ty - ty0 + 1) * 256,
                   (tx - tx0) * 256:(tx - tx0 + 1) * 256] = elev

    lats = np.linspace(lat0, lat1, ny)
    lons = np.linspace(lon0, lon1, nx)
    glon, glat = np.meshgrid(lons, lats)
    px, py = _merc(glat, glon, zoom)
    px = (px - tx0) * 256.0
    py = (py - ty0) * 256.0
    px = np.clip(px, 0, mosaic.shape[1] - 1.001)
    py = np.clip(py, 0, mosaic.shape[0] - 1.001)
    ix, iy = px.astype(int), py.astype(int)
    fx, fy = px - ix, py - iy
    elev = (mosaic[iy, ix] * (1 - fx) * (1 - fy)
            + mosaic[iy, ix + 1] * fx * (1 - fy)
            + mosaic[iy + 1, ix] * (1 - fx) * fy
            + mosaic[iy + 1, ix + 1] * fx * fy)
    return elev  # row 0 = south edge (lat0)


# ---------------------------------------------------------------------------
# Text plaque.
# ---------------------------------------------------------------------------

FONT_CANDIDATES = [
    "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
    "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
    "/System/Library/Fonts/Supplemental/Arial Bold.ttf",
    "C:/Windows/Fonts/arialbd.ttf",
]


def _load_font(px):
    for path in FONT_CANDIDATES:
        if os.path.exists(path):
            return ImageFont.truetype(path, px)
    return ImageFont.load_default(px)


def render_plaque_mask(lines, width_mm, height_mm, ppm=6):
    """Rasterize centered text lines; returns bool mask (row 0 = top)."""
    W, H = int(width_mm * ppm), int(height_mm * ppm)
    img = Image.new("L", (W, H), 0)
    draw = ImageDraw.Draw(img)
    sizes_mm = [6.2, 4.3, 4.3][:len(lines)]
    gap = 1.6 * ppm
    heights = [s * ppm * 1.25 for s in sizes_mm]
    total = sum(heights) + gap * (len(lines) - 1)
    y = (H - total) / 2.0
    for text, size_mm, h in zip(lines, sizes_mm, heights):
        if text:
            font = _load_font(int(size_mm * ppm / 0.72))
            draw.text((W / 2.0, y + h / 2.0), text, fill=255,
                      font=font, anchor="mm")
        y += h + gap
    return np.asarray(img) > 96


# ---------------------------------------------------------------------------
# Preview render.
# ---------------------------------------------------------------------------


def render_preview(path, W_out, H_out, cavity, terrain_q, land, water_rgb,
                   track_xy, text_mask, bezel_mm, ppm=5):
    x0, y0, map_w, map_h = cavity
    img = Image.new("RGB", (int(W_out * ppm), int(H_out * ppm)), (38, 40, 46))
    draw = ImageDraw.Draw(img)

    def to_px(x, y):
        return x * ppm, (H_out - y) * ppm

    ny, nx = terrain_q.shape
    rel = np.where(land, terrain_q, 0.0)
    rel = rel / max(rel.max(), 1e-6)
    r = np.where(land, 92 + 70 * rel, water_rgb[0]).astype(np.uint8)
    g = np.where(land, 106 + 62 * rel, water_rgb[1]).astype(np.uint8)
    b = np.where(land, 66 + 52 * rel, water_rgb[2]).astype(np.uint8)
    tile = Image.fromarray(np.flipud(np.dstack([r, g, b])), "RGB")
    tile = tile.resize((int(map_w * ppm), int(map_h * ppm)), Image.NEAREST)
    img.paste(tile, (int(x0 * ppm), int((H_out - y0 - map_h) * ppm)))

    pts = [to_px(x, y) for x, y in track_xy]
    draw.line(pts, fill=(20, 24, 12), width=int(1.2 * ppm), joint="curve")
    draw.line(pts, fill=(214, 232, 60), width=int(0.9 * ppm), joint="curve")

    tm = Image.fromarray((text_mask * 255).astype(np.uint8), "L")
    tm = tm.resize((int(W_out * ppm), int(bezel_mm * ppm)))
    white = Image.new("RGB", tm.size, (235, 235, 235))
    img.paste(white, (0, int((H_out - bezel_mm) * ppm)), tm)
    img.save(path)


# ---------------------------------------------------------------------------
# Main build.
# ---------------------------------------------------------------------------


def build(args):
    os.makedirs(args.out, exist_ok=True)

    # ---- 1. Track + elevation grid -------------------------------------
    duration = date = None
    if args.demo:
        map_w = args.map_width_mm
        map_h = map_w  # square demo map
        nx = args.grid
        dx = map_w / nx
        ny = int(round(map_h / dx))
        map_h = ny * dx
        elev = demo_terrain(ny, nx)
        u, v, track_ele = demo_track()
        track_x = u * map_w
        track_y = v * map_h
        duration, date = 36, "1 JULY 2026"
    else:
        lats, lons, track_ele, duration, date = parse_gpx(args.gpx)
        lat_c = (lats.min() + lats.max()) / 2.0
        kx = 111320.0 * math.cos(math.radians(lat_c))  # m per deg lon
        ky = 110540.0                                  # m per deg lat
        mx = (lons.max() - lons.min()) * args.margin + 1e-9
        my = (lats.max() - lats.min()) * args.margin + 1e-9
        lon0, lon1 = lons.min() - mx, lons.max() + mx
        lat0, lat1 = lats.min() - my, lats.max() + my
        # Clamp the aspect ratio by growing the short side of the bbox.
        w_m = (lon1 - lon0) * kx
        h_m = (lat1 - lat0) * ky
        aspect = np.clip(h_m / w_m, 0.6, 1.35)
        if h_m / w_m < aspect:      # too wide -> grow north/south
            grow = (w_m * aspect - h_m) / ky / 2.0
            lat0, lat1 = lat0 - grow, lat1 + grow
        elif h_m / w_m > aspect:    # too tall -> grow east/west
            grow = (h_m / aspect - w_m) / kx / 2.0
            lon0, lon1 = lon0 - grow, lon1 + grow

        map_w = args.map_width_mm
        nx = args.grid
        dx = map_w / nx
        map_h = map_w * aspect
        ny = int(round(map_h / dx))
        map_h = ny * dx
        elev = fetch_terrain(lat0, lat1, lon0, lon1, ny, nx,
                             zoom=args.zoom)
        track_x = (lons - lon0) / (lon1 - lon0) * map_w
        track_y = (lats - lat0) / (lat1 - lat0) * map_h

    # ---- 2. Vertical layout (mm) ---------------------------------------
    t = args.border_mm
    bezel = args.bezel_mm
    base_t = args.base_mm
    water_t = args.water_mm
    W_out = map_w + 2 * t
    H_out = map_h + t + bezel
    cav_x, cav_y = t, bezel  # cavity origin

    land = elev > args.sea_level_m + 0.25
    elev_q = np.ceil(np.maximum(elev - args.sea_level_m, 0.0)
                     / args.contour_m) * args.contour_m
    q_max = float(elev_q[land].max()) if land.any() else args.contour_m
    zscale = args.relief_mm / max(q_max, args.contour_m)

    water_top = base_t + water_t
    rim_h = water_top + args.relief_mm + 4.0

    # ---- 3. Frame -------------------------------------------------------
    frame = [
        box_mesh(0, W_out, 0, H_out, 0, base_t),                     # base plate
        box_mesh(0, t, 0, H_out, base_t, rim_h),                     # left rim
        box_mesh(W_out - t, W_out, 0, H_out, base_t, rim_h),         # right rim
        box_mesh(t, W_out - t, H_out - t, H_out, base_t, rim_h),     # top rim
        box_mesh(t, W_out - t, 0, bezel, base_t, rim_h),             # front bezel
    ]
    frame = np.concatenate(frame, axis=0)

    # ---- 4. Water + terrain ---------------------------------------------
    water = box_mesh(cav_x, cav_x + map_w, cav_y, cav_y + map_h,
                     base_t, water_top)

    terrain_top = np.where(land, water_top + elev_q * zscale, np.nan)
    terrain = heightfield_columns(terrain_top, water_top - 0.2,
                                  cav_x, cav_y, dx)

    # ---- 5. Flight path tube --------------------------------------------
    P = np.stack([track_x + cav_x, track_y + cav_y,
                  water_top + np.maximum(track_ele - args.sea_level_m, 0.0)
                  * zscale * args.alt_exaggeration], axis=1)
    # Resample to even ~1.5 mm spacing, then smooth.
    seg = np.linalg.norm(np.diff(P[:, :2], axis=0), axis=1)
    s = np.concatenate([[0.0], np.cumsum(seg)])
    n_samp = max(64, int(s[-1] / 1.5))
    si = np.linspace(0, s[-1], n_samp)
    P = np.stack([np.interp(si, s, P[:, k]) for k in range(3)], axis=1)
    k = 7
    ker = np.ones(k) / k
    pad = np.vstack([np.repeat(P[:1], k // 2, 0), P, np.repeat(P[-1:], k // 2, 0)])
    P = np.stack([np.convolve(pad[:, c], ker, "valid") for c in range(3)], axis=1)

    # Keep the tube out of the terrain, but let it merge at takeoff/landing.
    r_tube = args.tube_mm / 2.0
    gx = np.clip(((P[:, 0] - cav_x) / dx).astype(int), 0, nx - 1)
    gy = np.clip(((P[:, 1] - cav_y) / dx).astype(int), 0, ny - 1)
    ground = np.where(np.isfinite(terrain_top[gy, gx]),
                      np.nan_to_num(terrain_top[gy, gx]), water_top)
    P[:, 2] = np.maximum(P[:, 2], ground + 0.55 * r_tube)
    P[:, 0] = np.clip(P[:, 0], cav_x + r_tube, cav_x + map_w - r_tube)
    P[:, 1] = np.clip(P[:, 1], cav_y + r_tube, cav_y + map_h - r_tube)
    flight = tube_mesh(P, r_tube)

    # ---- 6. Plaque text --------------------------------------------------
    lines = [args.title]
    date_line = args.date_line or (
        f"{date} · {duration}min" if date and duration else date or "")
    if date_line:
        lines.append(date_line)
    if args.route:
        lines.append(args.route)
    ppm = 6
    mask = render_plaque_mask(lines, W_out, bezel, ppm)
    text_top = np.where(np.flipud(mask), rim_h + args.text_mm, np.nan)
    text = heightfield_columns(text_top, rim_h - 0.2, 0.0, 0.0, 1.0 / ppm)

    # ---- 7. Output -------------------------------------------------------
    parts = {
        "frame.stl": frame,
        "water.stl": water,
        "terrain.stl": terrain,
        "flight_path.stl": flight,
        "text.stl": text,
    }
    total = 0
    for fname, tris in parts.items():
        n = write_stl(os.path.join(args.out, fname), tris)
        total += n
        print(f"  {fname:16s} {n:>8,} triangles")
    write_stl(os.path.join(args.out, "all_in_one.stl"),
              np.concatenate(list(parts.values()), axis=0))
    print(f"  all_in_one.stl   {total:>8,} triangles (merged)")

    if not args.no_preview:
        render_preview(os.path.join(args.out, "preview.png"),
                       W_out, H_out, (cav_x, cav_y, map_w, map_h),
                       elev_q, land, (26, 103, 201),
                       P[:, :2], mask, bezel)
        print(f"  preview.png      top-down render")

    print(f"\nmodel footprint: {W_out:.0f} × {H_out:.0f} mm, "
          f"{rim_h:.1f} mm tall (path peaks at {P[:, 2].max():.1f} mm)")
    print(f"vertical scale:  1 mm ≈ {1 / zscale:.0f} m of elevation"
          + (f", path ×{args.alt_exaggeration:g} exaggerated"
             if args.alt_exaggeration != 1.0 else ""))
    print(f"output:          {os.path.abspath(args.out)}/")


def main():
    ap = argparse.ArgumentParser(
        description="3D-print your flight: terrain map + flight path memento.",
        formatter_class=argparse.ArgumentDefaultsHelpFormatter)
    src = ap.add_mutually_exclusive_group(required=True)
    src.add_argument("--gpx", help="GPX track log of the flight")
    src.add_argument("--demo", action="store_true",
                     help="generate a synthetic bay-tour demo (offline)")
    ap.add_argument("--out", default="output", help="output directory")
    ap.add_argument("--title", default="Discovery Flight", help="plaque line 1")
    ap.add_argument("--date-line", default=None,
                    help="plaque line 2 (default: date · duration from GPX)")
    ap.add_argument("--route", default="HWD - Bay Tour - HWD",
                    help="plaque line 3, e.g. departure - route - arrival")
    ap.add_argument("--map-width-mm", type=float, default=160.0,
                    help="width of the map area")
    ap.add_argument("--border-mm", type=float, default=8.0,
                    help="frame border width (left/right/top)")
    ap.add_argument("--bezel-mm", type=float, default=26.0,
                    help="front bezel height (where the text goes)")
    ap.add_argument("--base-mm", type=float, default=3.0, help="base thickness")
    ap.add_argument("--water-mm", type=float, default=2.0,
                    help="water plate thickness")
    ap.add_argument("--relief-mm", type=float, default=14.0,
                    help="height of the tallest terrain above the water")
    ap.add_argument("--contour-m", type=float, default=40.0,
                    help="contour step in metres (stepped-topo look)")
    ap.add_argument("--grid", type=int, default=200,
                    help="terrain grid cells across the map width")
    ap.add_argument("--tube-mm", type=float, default=3.2,
                    help="flight path tube diameter")
    ap.add_argument("--alt-exaggeration", type=float, default=1.0,
                    help="extra vertical scale applied to the flight path only")
    ap.add_argument("--text-mm", type=float, default=1.0,
                    help="raised height of the plaque text")
    ap.add_argument("--margin", type=float, default=0.18,
                    help="map margin around the track bbox (fraction)")
    ap.add_argument("--sea-level-m", type=float, default=0.5,
                    help="elevations at/below this are water")
    ap.add_argument("--zoom", type=int, default=None,
                    help="override terrain tile zoom level (real mode)")
    ap.add_argument("--no-preview", action="store_true")
    args = ap.parse_args()
    build(args)


if __name__ == "__main__":
    main()
