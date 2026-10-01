# Mac application artwork

`MeltoramaIcon.png` is the 1254 × 1254 opaque square master for the Mac app.
A sunny cyan landscape and large yellow sun fill the icon, with turquoise
water and purple hills stretching into a glossy raspberry curl at the lower
right. A thin ivory edge preserves the elastic photograph idea without a broad
white mat or empty surrounding tile. There is no lettering or separate badge.

The artwork was created on 1 October 2026 with the built-in imagegen tool. The
first elastic photograph was generated without reference images; this version
was edited from that original using the prompt below. No photograph or artwork
from the user's historical examples was copied. The original master and prompt
remain in Git history: [master](https://github.com/L-K-M/Meltorama2000/blob/9f0f268/macos/Artwork/MeltoramaIcon.png)
and [prompt](https://github.com/L-K-M/Meltorama2000/blob/9f0f268/macos/Artwork/README.md).
The artwork is distributed with the project under the Unlicense; see the
repository's `LICENSE`.

`scripts/generate-macos-icon.swift` reads this checked-in master and produces
the ten standard PNG iconset slots, in sRGB, from 16 to 1024 pixels. It draws
the picture edge to edge, with no canvas inset or transparent margin. The build
packages them with Apple's `iconutil`. This process needs no network or
image-generation service. The Android launcher artwork is unchanged.

The system-rendered icon was inspected on macOS 26. Corner treatment on older
supported macOS versions has not been visually verified. The mask sentence in
the edit prompt records the current-system composition intent, not a guarantee
that every supported OS changes the classic ICNS outline.

## Final edit prompt

```text
Use case: precise-object-edit.
Asset type: final macOS application icon for Meltorama 2000.
Edit target: the attached original elastic-photograph icon.
Preserve: the beautiful sunny landscape, large warm yellow sun, luminous cyan sky, purple hills, turquoise water, and glossy raspberry melting curl. Preserve the idea of a photograph itself becoming liquid.
Change composition: the colorful melting picture must FILL the app icon. Make a bold close-up square composition, much more upright and nearly frontal. The landscape and liquid fold together occupy almost the entire square. Keep only a very thin warm ivory photo edge where it helps read the curl; eliminate the broad white photo mat. Bring the glossy magenta curl right to the lower-right edge; make it substantial and clearly part of the image.
Background: FULL-BLEED OPAQUE color from edge to edge. Continue the luminous turquoise/cyan and raspberry color around any remaining corners so there is no empty white or gray tile and no transparency. Deliver square artwork with square outer corners: the operating system will apply its native app-icon mask.
Mood: colorful, sunny, cheerful, juicy, happy. High-quality dimensional highlights, clear broad shapes at small Dock sizes. Let the picture be the icon, not a tiny object sitting on a background.
Avoid: white/gray surrounding tile, blank margins, floating centered miniature, thick white border, separate drop emblem, multiple props, dark gloomy color, text, lettering, mockup, comparison sheet. Final single square icon artwork alone, at least 1024 pixels.
```

The tool returned a 1254-pixel square master. The packager validates and
resamples it to exact native icon sizes.
