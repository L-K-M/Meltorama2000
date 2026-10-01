# Mac application artwork

`MeltoramaIcon.png` is the 1254 × 1254 opaque square master for the Mac app.
It shows a cheerful Golden Retriever photograph with an enlarged nose, one
slightly enlarged eye, and a smiling cheek pulled sideways. The close portrait
fills the square and retains the source photograph's fur, tongue, and green
background. It was edited with the built-in imagegen tool on 1 October 2026.

## Source and license

The real photograph is Karen Arnold's `Golden-retriever-dog.jpg`, preserved as
`Sources/GoldenRetriever.jpg` (1920 × 1440 JPEG). It is available under
[CC0 1.0 Universal](https://creativecommons.org/publicdomain/zero/1.0/), as
recorded by [Wikimedia Commons](https://commons.wikimedia.org/wiki/File:Golden-retriever-dog.jpg)
and the [original Public Domain Pictures page](https://www.publicdomainpictures.net/en/view-image.php?image=31188&picture=golden-retriever-dog).
The Commons license record was checked on 1 October 2026; its stable revision is
[1275143223](https://commons.wikimedia.org/w/index.php?title=File:Golden-retriever-dog.jpg&oldid=1275143223).
The project's edits are released under the Unlicense; see the repository's
`LICENSE`. The source photograph remains CC0.

SHA-256:

```text
96bd803ee7b525075b2ff147493b8eb1e23942b5fa6fc07494d6dd162950e0d3  Sources/GoldenRetriever.jpg
7b7ec25169fbc13101186279bce63060b06d0766cf901ad32f7006c0bfb4e9e8  MeltoramaIcon.png
```

## Packaging

`scripts/generate-macos-icon.swift` reads the checked-in master and produces
the ten standard PNG iconset slots, in sRGB, from 16 to 1024 pixels. It draws
the image edge to edge without a canvas inset or a rounded-corner mask. The
build packages them with Apple's `iconutil`. This needs no network or image
service. The Android launcher artwork is unchanged.

The earlier elastic landscape masters and prompts remain in Git history at
`9f0f268` and `73160fe`.

## Exact edit prompt

```text
Use case: precise-object-edit.
Asset type: full-bleed macOS icon master, square PNG.
Input image: a real CC0 photograph by Karen Arnold; this is the edit target, not a style reference.
Primary request: make a cheerful photographic icon for Meltorama, a photo-liquify app. Crop this exact golden retriever photograph tightly into a square so the happy dog's face, floppy ears, black nose and pink tongue fill nearly the entire picture. Preserve the actual photographic fur, whiskers, lighting, natural eyes, tongue texture, lens softness and background from the source. Then apply a clearly visible but friendly digital liquify distortion: enlarge the nose, balloon one eye slightly, and smoothly pull one smiling cheek sideways into a small sweeping curve. It should look like someone had fun warping a real photograph with a brush. Keep the original dog's identity and natural photographic appearance; no replacement dog, no painted fur, no cosmetic smoothing or synthetic studio rendering.
Composition: a simple bold close portrait legible at tiny icon sizes, face mostly central, both eyes and nose visible, natural blurred green background at edges. Square picture all the way to every edge, opaque corners, no rounded-corner mask or outside margin.
Avoid: illustration, cartoon styling, 3D rendering, glossy plastic, fantasy landscapes, rainbow fluids, melted paper, white backplate, icon containers, physical drips, extra features, extra eyes, text, logos, watermark. The deformation is of photograph pixels, not a new creature.
```
