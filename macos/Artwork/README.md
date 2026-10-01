# Mac application artwork

`MeltoramaIcon.png` is the 1254 × 1254 opaque square master for the Mac app.
It combines an invented, photographic-style happy Golden Retriever with a
sweeping bottom-right liquify curl. The face fills the picture; gold fur,
pink tongue tones, and green background stretch into the curl.

## Origin and license

The dog was generated from scratch with the built-in imagegen tool on
1 October 2026. No real dog photograph was supplied. The earlier generated
landscape master at `73160fe` served only as a reference for the melting
curl's composition. This project artwork is released under the Unlicense;
see the repository's `LICENSE`.

The previous real-photo dog icon and its CC0 source and attribution remain
in Git history at `6d6f2d3`; neither is used by the current application.
The earlier elastic landscape masters and prompts remain in Git history
at `9f0f268` and `73160fe`.

SHA-256:

```text
8ed3e3f372bb1a6385616c12bad7072cbcfeb85dfc69d945c1e6b2729a14f0dc  MeltoramaIcon.png
```

## Packaging

`scripts/generate-macos-icon.swift` reads the checked-in master and produces
the ten standard PNG iconset slots, in sRGB, from 16 to 1024 pixels. It draws
the image edge to edge without a canvas inset or a rounded-corner mask. The
build packages them with Apple's `iconutil`. This needs no network or image
service. The Android launcher artwork is unchanged.

## Exact generation prompt

Mode: built-in imagegen; the old landscape was a composition reference.

```text
Use case: photorealistic-natural with digital photo-liquify effect.
Asset: full-bleed square macOS app icon master for Meltorama, a playful photo-warping app.
Reference image role: the supplied older landscape icon is ONLY a reference for the sweeping bottom-right melting curl and its composition. Do not reproduce its landscape, sun, mountains, or illustrative style. No real dog photograph is an input.
Create an entirely invented happy golden retriever from scratch in convincing photographic style. A close-up friendly dog's face, soft floppy ears, broad black nose and pink tongue fills the picture. Natural fine fur and whiskers, believable eyes, real lens softness and warm outdoor sunlight, blurred fresh green garden background. Bold close portrait readable at tiny icon sizes. The dog must be artificial and must not reproduce a specific real pet. Slight playful liquify enlargement of the nose and one smiling cheek gives the face a mischievous expression, while retaining photographed fur texture.
Combine that photographic portrait with the older icon's distinctive bottom-right melting effect: the lower-right portion of the PHOTO is pulled down and right into one strong sweeping curled wave, taking the gold fur, pink tongue tones and green background pixels into smooth elastic ribbons. A vivid warm pink/magenta accent can appear in the curled image edge as in the reference. The curl occupies roughly the bottom-right quarter and is immediately readable, while both eyes and nose remain clear. This is a digital deformation of image pixels, not a physically melting animal. Preserve natural texture up to and into the stretched region; no plastic fur or painted dog.
Composition: happy dog's large face occupies most of upper-left and center; bottom-right unmistakable curled liquify sweep. Square opaque picture to all four edges and corners. No container, white background, white picture border, blank margins, rounded mask, paper frame, lettering, logos or watermark. Do not turn this into an illustration, fantasy scene, glossy 3D mascot or rainbow slime. Photographic dog plus one stylized photo-warp curl.
```
