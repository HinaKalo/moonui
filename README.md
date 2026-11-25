# MoonUI (`moon-win32-modern`)

Part of the **Moon Zig Ecosystem**:
- **`moonui`** (`C:\moon-dev\moon-win32-modern`): 100% pure Zig 0.17.1 native Windows UI component library (**Win32 + Direct3D 11 + DXGI + DirectComposition + Direct2D 1.1 + DirectWrite**), zero Dear ImGui, zero C/C++ dependencies.
- **`moon-sdk`** (`C:\moon-dev\moon-sdk`): Independent, UI-agnostic Windows platform & IM SDK exporting **`mooncore`** (WinHTTP HTTPS/WS, DPAPI, SQLite/KV, CNG crypto, OS thread pool & dispatcher) and **`moonchat`** (typed LumenIM client).

## Install in Another Project

### Option A: Add to an existing Zig project

```powershell
# Install MoonUI (local path or git+https://...)
zig fetch --save=moonui C:\moon-dev\moon-win32-modern

# Optional: also install Moon SDK (mooncore + moonchat)
zig fetch --save=moon_sdk C:\moon-dev\moon-sdk
```

```zig
// build.zig
const moonui = b.dependency("moonui", .{ .target = target, .optimize = optimize });
exe.root_module.addImport("moonui", moonui.module("moonui"));
```

### Option B: Scaffold a ready-to-run app

```powershell
cd C:\moon-dev\moon-win32-modern
zig build new -- ..\my-app --name my-app
cd ..\my-app
zig build run
```

## Repository Commands

```powershell
zig build test                                  # Unit tests
zig build run                                   # 5-page Component Gallery
zig build run -- --page components --theme 1    # Specific page & theme (0..3)
zig build chat                                  # Native Direct2D IM demo (moonui + mooncore + moonchat)
zig build new -- ..\my-app --name my-app        # Scaffold a new app
```
