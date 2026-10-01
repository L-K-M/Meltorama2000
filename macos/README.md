# Meltorama for macOS

A native document-based photo editor for macOS 13 and later. The app uses
SwiftUI inspectors and palettes, AppKit document windows and input, and the
existing displacement-field shaders in an isolated desktop GPU context.
There is no browser, embedded server, account, or network dependency.

## Build and install

Install Xcode or Apple's Command Line Tools with Swift 6 or later, then run
from the repository root:

```sh
scripts/build-macos.sh --launch
scripts/test-macos.sh --smoke
```

The build produces `dist/Meltorama.app` and a versioned zip with its SHA-256
sidecar. Drag the app to Applications to install it. The bundle contains the
shaders, sample images, icon, and notices and works without the repository.
Use `--debug` for a debug bundle and `--universal` for Apple silicon and Intel
in one app. The version comes from the existing Android release configuration.

The app icon is an elastic photograph with a glossy berry curl. Its original
master is checked in under `Artwork/`; the build generates native icon sizes
and packages them into the application without downloading resources.
Open `macos/Package.swift` in Xcode for development; the shell script packages
the executable into its document-aware application bundle.

Local builds use ad-hoc signing. Developer ID distribution requires setting
`MELTORAMA_SIGN_IDENTITY`, then notarizing with your own Apple credentials.
No credentials or third-party dependencies are required for local builds.

## Editing

Open photos with Command-O, drag them into the window, or start with a sample.
Each project has its own resizable window. Tools stay on the left; the photo
is central; contextual settings and whole-photo effects are on the right.
The toolbar contains document and view actions. Appearance follows macOS;
Settings also offers Light and Dark for this app. Standard text editing and
keyboard focus work in inspectors.

The editor has a tactile console finish: colored glossy brush domes, a satin
metal tool rack, recessed workspace and inspector panels, and a GOOvie
filmstrip. Inset mode controls stay distinct from raised action buttons.
Selection includes a checkmark, and effect enabling stays independent from
disclosure. The finish follows Light/Dark appearance while native numeric
entry, menus, shortcuts, and document commands keep their existing behavior.

The palette includes all twenty Android tools. Hold tools pump while pressed;
paint tools stamp along the path. Option-click chooses Echo's source or
replaces a Portal pair. Click to place a lens, select its center to drag it,
and change its type, size, and strength in the inspector. Taffy Pins hold up
to five landmarks while another point is pulled. Crop retains original bytes
and resets the coordinate-dependent edits with confirmation and undo.

Effects have independent checkboxes and disclosure buttons. Their settings
only occupy space when expanded. Animation depth and cycle counts appear
progressively within each effect. Capture GOOvie frames with Command-K; edit
the live photo and capture another frame. Selecting a frame previews its
immutable pin. Update replaces the selected pin with the live photo. The
strip supports curves, scrubbing, playback, reordering, deletion, and context
menus. Undo does not flatten existing pins.

| Command | Shortcut |
| --- | --- |
| New document / Open | Command-N / Command-O |
| Save / Save As | Command-S / Command-Option-Shift-S |
| Undo / Redo | Command-Z / Command-Shift-Z |
| Export | Command-Shift-E |
| Add Fusion photo | Command-Shift-O |
| Fit / Actual size | Command-0 / Command-1 |
| Zoom | Command-plus / Command-minus, or pinch |
| Pan | Hold Space and drag, Hand tool, or scroll |
| Rotate view | Two-finger rotation |
| Brush size | `[` / `]` on the canvas |
| Brush / Hand / Lenses / Crop | B / H / L / C on the canvas |
| Capture / Play-Pause | Command-K / Command-Option-P |
| Inspector / Timeline | Command-Option-I / Command-Option-T |
| Full screen | Control-Command-F |
| Cancel preview or crop | Escape |

## Documents and recovery

A `.meltorama` project is a Finder package containing the same `project.json`,
`source.img`, and optional `fusion.img` that Android stores. Original image
bytes are retained. The JSON uses the existing schema, wire enum names, and
normalized revision graph. Android project folders can be opened through
File > Open; package contents can be copied back to Android's project storage.
Android currently has no user-facing project transfer UI.

Named documents use AppKit autosave. Unnamed edits receive a durable recovery
package under `~/Library/Application Support/Meltorama/Recovery`; interrupted
work reopens on launch. No recovery drafts are evicted automatically. AppKit
provides normal Mac save/close decisions for unnamed documents, while recovery
keeps a separate safety copy. Invalid graphs, missing assets, and newer schema
versions are reported rather than partially restored.

PNG and JPEG export replays edits at source resolution. Explicit 4096/2048
caps are available for large photos. Movie export uses the same replay and
tween pipeline with H.264 MP4 or animated GIF. Speed changes the number of
frames while retaining the encoder's nominal clock. GIF uses Apple's ImageIO
encoder. Cancelled exports remove staging files and retain existing outputs.
Choose Share in the export sheet to send the selected photo or movie through
the native Mac sharing picker. Sharing uses the same format, quality, size,
and animation settings as export. Its temporary output stays available until
the selected service finishes, then the app removes it.

## Architecture and maintenance

`MeltoramaCore` ports the mature Kotlin document and input rules to plain
Foundation Swift: graph validation, immutable revision IDs, brush parameters,
resampling, symmetry, portals, pump math, pins, random recipes, easing, timing,
and bounded wobble. Its tests include a real Android serializer fixture.
`MeltoramaMac` contains the document adapter, observable editor session,
native views, shared preview/export renderer, and native encoders.

The shader algorithm stays in `GlShaders.kt`. Run
`python3 scripts/sync-macos-shaders.py` after a shader edit, or `--check` to
verify the committed desktop translations. Changes are limited to the GLSL
version and desktop syntax. OpenGL is deprecated by Apple but remains
available; a future Metal migration can replace the renderer without
changing documents or the native controls.

See [VERIFICATION.md](VERIFICATION.md) for checks and remaining limitations,
and [THIRD_PARTY_NOTICES.txt](THIRD_PARTY_NOTICES.txt) for notices.

The interface research used the official [Acorn workspace guide](https://secure.flyingmeat.com/acorn/docs/acorn_s_workspace.html),
[Pixelmator interface guide](https://support.apple.com/en-ca/guide/pixelmator-pro/pix96e754af4/mac),
[Affinity workspace guide](https://affinity.help/photo2/English.lproj/pages/Workspace/interface.html),
[Photoshop workspace guide](https://helpx.adobe.com/au/photoshop/desktop/get-started/learn-the-basics/workspace-overview.html),
and [Apple document architecture](https://developer.apple.com/documentation/appkit/developing-a-document-based-app).
