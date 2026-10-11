# Night Shift app icon: drawing notes

Picked by Vinnie on 2026-10-11 to replace the ring icon, which looked too much like Firefox. The art is `icon.svg`, and `icon-1024.png` is a render of it. These notes are for porting it into `scripts/make-icon.swift` (CoreGraphics).

## Geometry
Everything is on a 1024 grid with y pointing down. In CG, map it onto the tile with `k = tile.width / 1024`, `x' = tile.minX + x*k` and `y' = tile.maxY - y*k`.

| Element | Geometry | Paint |
|---|---|---|
| Tile | full 1024, continuous corners as before | linear, top `#202126` to bottom `#09090B` |
| Glow (clipped to tile) | ellipse, center (512, 840), rx 400, ry 150 | radial `#F08A2A` at 55% alpha fading to 0 at the edge |
| Slab shadow | same shape as the slab | black at 70% alpha, offset 30 down, blur ~56 (SVG stdDev 28) |
| Slab | rect x 132, y 220, w 760, h 584, corner radius 150 | linear, top `#3A3B41` to bottom `#16171A` |
| Slab rim (large sizes only) | rect 2 px inside the slab, radius 148, stroke 5 | white at 30% alpha at the top, fading to 0 by 30% of the height |
| Chevron | polyline (282,318) to (398,404) to (282,490) | stroke 84, white, round caps and joins |
| Track | rect x 212, y 548, w 600, h 148, radius 74 | `#050506` |
| Fill (clipped to track) | x 212, w 436 (72.7% of the track) | linear, top `#FFB35E` to bottom `#F08A2A` |
| Gloss (clipped to fill) | top half of the fill (74 px) | white at 42% alpha at the top, fading to 0 at 55% of that height |

## Notes
- Orange is the only color, and it marks only the used amount and its glow. Everything else is grayscale.
- At 32 px and 16 px, drop the rim. The chevron and bar are bold enough to read without it.
- The old code's palette (`arcStops`, `arcColor`), `innerShadow` and ring drawing all go away. `shadowOnly` is still useful for the slab shadow.
