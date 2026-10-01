# Mac application artwork

`MeltoramaIcon.png` is the original 1254 × 1254 RGBA master for the Mac app.
It depicts an elastic photograph: the printed image and ivory frame stretch
together into one glossy berry curl. Its photo silhouette, cyan image, amber
sun, and berry tip remain distinct at small Dock sizes. There is no lettering
or separate badge.

The artwork was created on 1 October 2026 with the built-in imagegen tool,
using the prompt below and no reference images. No photograph or artwork from
the user's historical examples was copied. It is distributed with the project
under the Unlicense; see the repository's `LICENSE`.

`scripts/generate-macos-icon.swift` reads this checked-in master and produces
the ten standard PNG iconset slots, in sRGB, from 16 to 1024 pixels. A 1/16
canvas inset keeps the freeform object's Dock footprint comfortable. The build
then packages them with Apple's `iconutil`. This process needs no network or
image-generation service. The Android launcher artwork is unchanged.

## Final generation prompt

```text
Use case: stylized-concept.
Asset type: original macOS application icon artwork for Meltorama 2000, a playful real-time photo-warping editor with a tactile satin-metal and candy-gloss interface.
Primary request: create an exceptionally polished, memorable Delicious-generation Mac app icon: an ELASTIC PHOTOGRAPH. One thick ivory instant-photo print, with a subtle polished silver edge, occupies almost the whole square canvas. It floats at a slight counterclockwise angle in a shallow, nearly frontal three-quarter view. Its bottom-right corner is physically pulled, folded and stretched into ONE bold S-shaped glossy taffy curl. The photo border AND the printed image deform together. This is the key idea: a photograph itself becoming liquid, not a photograph with an unrelated blob sitting on it.
Photo content: a very simple vivid landscape with a luminous cyan sky, one large warm amber sun, teal and violet hills; the image bends and stretches with the photo, and blends into saturated raspberry/magenta glossy goo at the pulled corner. Keep the white photographic border clear and substantial. The curl is sculptural, smooth, rounded, juicy, slightly translucent, with highly controlled bright specular reflections. A single elegant silver highlight and upper-left light source tie the object together. Material finish has the crafted physical charm of great 2005–2015 Mac object icons, with today's rendering quality.
Composition: ONE large dominant object, crisp asymmetric bent silhouette, no outer tile or additional props. Square 1024x1024 composition, centered, object occupies about 85% of the canvas, generous enough transparent edge margin that no edge or shadow is cut off. The photograph must read as a photo first and liquid distortion second, even at 32px. Broad color masses and clean geometry; avoid intricate miniature scenery. High resolution, clean antialiased edges, premium restrained dimensionality, no noisy textures.
Background: genuinely transparent alpha, no background, no checkerboard pattern. Keep only a soft restrained contact shadow closely beneath the object.
Constraints: no text, no letters, no numbers, no watermark, no brand logos, no human faces, no camera, no paintbrush, no magic wand, no generic droplet emblem, no separate badges, no multiple drips, no outer rounded-square app tile, no mockup, no comparison sheet. Render the final icon artwork alone.
```

The tool returned a 1254-pixel square master rather than the requested
1024-pixel canvas. The packager validates and resamples it to exact native
icon sizes while preserving its alpha channel.
