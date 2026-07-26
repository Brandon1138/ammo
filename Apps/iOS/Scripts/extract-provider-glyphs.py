#!/usr/bin/env python3
"""Remove app-icon tiles while preserving the official provider glyph pixels."""

from collections import deque
from pathlib import Path

import numpy as np
from PIL import Image, ImageFilter


ROOT = Path(__file__).resolve().parents[1]
SOURCES = ROOT / "Assets" / "Official"
CATALOG = ROOT / "Shared" / "ProviderAssets.xcassets"


def largest_component(mask: np.ndarray) -> np.ndarray:
    height, width = mask.shape
    seen = np.zeros_like(mask, dtype=bool)
    largest: list[tuple[int, int]] = []

    for y, x in zip(*np.nonzero(mask)):
        if seen[y, x]:
            continue
        component: list[tuple[int, int]] = []
        queue = deque([(int(y), int(x))])
        seen[y, x] = True
        while queue:
            current_y, current_x = queue.popleft()
            component.append((current_y, current_x))
            for next_y, next_x in (
                (current_y - 1, current_x),
                (current_y + 1, current_x),
                (current_y, current_x - 1),
                (current_y, current_x + 1),
            ):
                if (
                    0 <= next_y < height
                    and 0 <= next_x < width
                    and mask[next_y, next_x]
                    and not seen[next_y, next_x]
                ):
                    seen[next_y, next_x] = True
                    queue.append((next_y, next_x))
        if len(component) > len(largest):
            largest = component

    result = np.zeros_like(mask, dtype=bool)
    if largest:
        ys, xs = zip(*largest)
        result[np.array(ys), np.array(xs)] = True
    return result


def fill_holes(mask: np.ndarray) -> np.ndarray:
    height, width = mask.shape
    exterior = np.zeros_like(mask, dtype=bool)
    queue: deque[tuple[int, int]] = deque()

    for x in range(width):
        queue.extend(((0, x), (height - 1, x)))
    for y in range(height):
        queue.extend(((y, 0), (y, width - 1)))

    while queue:
        y, x = queue.popleft()
        if exterior[y, x] or mask[y, x]:
            continue
        exterior[y, x] = True
        for next_y, next_x in ((y - 1, x), (y + 1, x), (y, x - 1), (y, x + 1)):
            if 0 <= next_y < height and 0 <= next_x < width:
                queue.append((next_y, next_x))

    return mask | ~exterior


def export_glyph(source_name: str, destination: Path, provider: str) -> None:
    source = Image.open(SOURCES / source_name).convert("RGBA")
    pixels = np.asarray(source)
    red = pixels[:, :, 0].astype(np.float32)
    green = pixels[:, :, 1].astype(np.float32)
    blue = pixels[:, :, 2].astype(np.float32)
    source_alpha = pixels[:, :, 3]

    if provider == "codex":
        maximum = np.maximum(np.maximum(red, green), blue)
        minimum = np.minimum(np.minimum(red, green), blue)
        saturation = (maximum - minimum) / np.maximum(maximum, 1)
        seed = (
            (blue > 100)
            & (blue > red * 1.04)
            & (blue > green * 1.01)
            & (saturation > 0.12)
            & (source_alpha > 0)
        )
        mask_image = Image.fromarray((largest_component(seed) * 255).astype(np.uint8))
        mask_image = mask_image.filter(ImageFilter.MaxFilter(9)).filter(ImageFilter.MinFilter(9))
        mask = fill_holes(np.asarray(mask_image) > 0)
    else:
        luminance = red * 0.2126 + green * 0.7152 + blue * 0.0722
        mask = largest_component((luminance > 45) & (source_alpha > 0))

    alpha = Image.fromarray((mask * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(1.2))
    result = source.copy()
    result.putalpha(Image.fromarray(np.minimum(np.asarray(alpha), source_alpha).astype(np.uint8)))

    bounds = result.getbbox()
    if bounds is None:
        raise RuntimeError(f"No glyph found in {source_name}")
    cropped = result.crop(bounds)
    scale = min(448 / cropped.width, 448 / cropped.height)
    cropped = cropped.resize(
        (round(cropped.width * scale), round(cropped.height * scale)),
        Image.Resampling.LANCZOS,
    )
    canvas = Image.new("RGBA", (512, 512))
    canvas.alpha_composite(cropped, ((512 - cropped.width) // 2, (512 - cropped.height) // 2))
    canvas.save(destination, optimize=True)


export_glyph(
    "codex-app-icon.png",
    CATALOG / "logo-codex.imageset" / "codex.png",
    "codex",
)
export_glyph(
    "cursor-app-icon.png",
    CATALOG / "logo-cursor.imageset" / "cursor.png",
    "cursor",
)
