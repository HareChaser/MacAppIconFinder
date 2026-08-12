# AppIconFinder

A small macOS app for replacing the icon of an app.

https://github.com/user-attachments/assets/8343ef63-d460-4c0d-9206-ea0750798252

Pick the application first, then pick the icon — a `.ico`, `.png`/`.jpg`, an `.icns`,
or a Windows `.exe`/`.dll` whose icon you want to lift out. Both panes also accept
drag and drop.

You can also skip the second step entirely: choose an app, pick a style, and hit
**Apply Icon** to restyle the app's *own* icon in place. **Restore Original**
always puts the stock icon back.

## Build and run

```bash
./build.sh && open build/AppIconFinder.app
```

Requires macOS 13+ and a Swift toolchain (Xcode or the Command Line Tools).
The build produces `build/AppIconFinder.app`, which you can move to `/Applications`
like any other app.

## What it does

- **`.ico` / `.cur`** — parses the container and lists every image inside it
  (both PNG-compressed and classic DIB entries, AND mask included), so you can
  pick which size to use.
- **`.exe` / `.dll`** — walks the PE resource directory, reads `RT_GROUP_ICON`
  and `RT_ICON`, and rebuilds each icon group. Executables that only carry
  version info or a manifest genuinely have no icon, and are reported as such.
- **`.png` / `.jpg` / `.icns` / `.tiff` / `.heic` / `.bmp` / `.gif`** — used directly.

Whatever you pick is rendered onto a 1024×1024 square before it's applied, so
non-square art is centred rather than stretched.

## Styles

The segmented control under the previews picks how the art is dressed. It
applies both to an icon file you chose and to the app's own icon when you
haven't chosen one. The preview updates live, so you can flip between styles
before applying.

| Style | What it does |
| --- | --- |
| **Original** | The artwork exactly as it is, only squared onto the canvas. |
| **Rounded** | Inset and clipped to the macOS rounded square, with a soft contact shadow. |
| **Glass** | Rounded, plus a specular highlight and a rim that catches light along the top — the glossy, bevelled look. |
| **Flat** | Rounded and edge to edge, with no shadow and no gloss. |

Anything but **Original** is useful for a bare screenshot or a Windows icon that
would otherwise sit in the Dock as a hard-edged square.

Styled output matches the proportions macOS uses: the icon body fills 0.804 of
the canvas, the same as every system icon. The artwork's *opaque content* is what
gets fitted, so art that already carries a margin — an app's own icon, an `.icns` —
isn't nested inside a second margin and left looking small in the Dock.

Every treatment follows the artwork's real silhouette, not the bounding box:
the shadow traces the art's alpha, and the glass highlights are masked by it.
Art that already has its own rounded corners and transparent margin keeps them
instead of gaining a translucent square around it.

### Restyling an app's own icon

With no icon file chosen, pane 2 previews the selected app's icon in the current
style, and **Apply Icon** writes that back to the app. The source is the app's
*stock* icon, not the icon it happens to be showing, so applying Glass twice
doesn't stack two coats of gloss. When an app already has a custom icon, the
stock one is read from the `.icns` in its bundle; the rare app that keeps its
icon in an asset catalogue *and* already has a custom icon can't be restyled
safely, and says so — restore the original first.

Use **Clear** in pane 2 to drop a chosen icon file and go back to restyling the
app's own icon.

**Restore Original** removes the custom icon and gives the app its built-in one
back. The button appears whenever the selected app currently has a custom icon.

## Permissions

Apps you installed yourself are usually writable by your account and change
without any prompt. Apps owned by `root` (most App Store installs) are not — for
those, AppIconFinder asks first, then has macOS run the same write as an
administrator. macOS shows its own password dialog; the app never sees or
handles your password.

## Notes

- Custom icons are stored in an `Icon\r` file inside the bundle. This is the same
  mechanism Finder's own Get Info → paste uses. A handful of strictly validated
  apps may notice the change to their bundle; **Restore Original** undoes it.
- "Restart Dock after applying" quits the Dock so the new icon shows up
  immediately. The Dock relaunches itself instantly; leave it off if you'd
  rather wait for the icon cache to catch up on its own.

## The app's own icon

`Resources/AppIcon.icns` is checked in and drawn in code, not in an image
editor — `Tools/MakeAppIcon.swift` renders the artwork with Core Graphics.
If you change the artwork, regenerate the `.icns` (this also refreshes
`Resources/AppIcon.png`, the 1024×1024 master):

```bash
./Tools/make-icon.sh
```

## Troubleshooting

To see what AppIconFinder finds in a file without opening the UI:

```bash
build/AppIconFinder.app/Contents/MacOS/AppIconFinder --dump-icons /path/to/file.exe /tmp/out
```

It prints one line per icon found and writes each as a PNG into the output directory.

## Layout

| Path | What's in it |
| --- | --- |
| `Sources/AppIconFinder/ContentView.swift` | The two-pane UI and drop targets |
| `Sources/AppIconFinder/AppState.swift` | Selection, apply/restore flow, error surfacing |
| `Sources/AppIconFinder/ICODecoder.swift` | `.ico` container parsing and per-entry decoding |
| `Sources/AppIconFinder/PEIconExtractor.swift` | Windows PE resource walk |
| `Sources/AppIconFinder/IconRenderer.swift` | Squaring, insetting, and the four style treatments |
| `Sources/AppIconFinder/IconStyle.swift` | The style list and its labels |
| `Sources/AppIconFinder/IconApplier.swift` | `setIcon` write, admin escalation, Dock refresh |
| `Tools/MakeAppIcon.swift` | Draws the app's own icon |
