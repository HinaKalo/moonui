# MoonWin Native (`moon-win32-modern`)

A **100% pure Zig 0.17.1** native Windows UI component library replicating the visual design system and skin of `moon-win-gui` using **Win32 + Direct3D 11 + DXGI + DirectComposition + Direct2D 1.1 + DirectWrite** — with **zero Dear ImGui** and **zero C/C++ dependencies**.

## Architecture

- **Pure Zig COM & Win32 Bindings (`src/win32/`)**: Direct vtable bindings for `ID3D11Device`, `IDXGISwapChain1` (`CreateSwapChainForComposition` with `DXGI_ALPHA_MODE_PREMULTIPLIED` and `DXGI_SWAP_EFFECT_FLIP_SEQUENTIAL`), `IDCompositionDevice`/`Target`/`Visual`, `ID2D1Factory1`/`Device`/`DeviceContext`, and `IDWriteFactory`/`TextFormat`/`TextLayout`.
- **Event-Driven 0% Idle CPU Loop (`src/app.zig`)**: Blocks in `MsgWaitForMultipleObjectsEx` when animations converge; renders vsync-smooth frames via DirectComposition when hovering, scrolling, or animating.
- **MoonWin Design System (`src/theme.zig`, `src/color.zig`, `src/anim.zig`)**: Exact color palettes (Midnight, Daylight, Ember, Aurora), radii, spacing, typography scale, exponential smoothing, and critically-damped springs.
- **56 Crisp Vector Icons (`src/icons.zig`)**: Drawn as Direct2D path geometries with round stroke caps & joins at native DPI.
- **Component Suite (`src/layout.zig`, `src/widgets.zig`)**: Sidebar, cards with soft shadows & glass top highlight, grids, buttons (6 variants, 3 sizes, loading/disabled), icon buttons, spring switches, animated checkboxes, radio groups, gradient sliders, native UTF-8/CJK text fields with focus glow, segmented controls, tabs, select dropdowns, badges, avatars, progress bars, spinners, sparklines, KPI stats, tooltips, menus, dialogs, and toast notifications.

## Build & Run

```powershell
# Run unit tests
zig build test

# Run interactive component gallery
zig build run

# Open a specific page and theme (0=Midnight, 1=Daylight, 2=Ember, 3=Aurora)
zig build run -- --page components --theme 1

# Headless BMP screenshot capture
zig-out\bin\moonwin-native-gallery.exe --page overview --theme 0 --capture overview.bmp
```
