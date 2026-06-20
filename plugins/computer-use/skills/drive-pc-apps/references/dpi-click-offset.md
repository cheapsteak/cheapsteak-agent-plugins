# DPI click-offset: root cause & upstream bug

## Symptom
On a fractional-scaled Windows display (e.g. 150%), pixel clicks via cua-driver against a
**DPI-unaware** target app land at `1/scale` of the intended position (≈0.667 undershoot at 150%),
so they miss small targets and appear to do nothing. UIA `element_index` clicks are unaffected.

## Tell-tale
The `get_window_state` screenshot shows the app content occupying only the top-left `~1/scale`
of the image, with **black bands on the right and bottom**.

## Root cause (code-verified against trycua/cua, v0.5.x)
cua-driver captures the window with `PrintWindow(hwnd, ..., PW_RENDERFULLCONTENT)` into a buffer
sized to the **physical** `GetWindowRect`. A DPI-unaware window is painted by `PrintWindow` at its
**own un-stretched logical scale**, so the content fills only `1/scale` of that physical-sized
buffer (hence the black margin). The click path then maps window-local → screen with only the
resize-ratio undo and **no stretch compensation**:

```
screen_x = dwm_frame.left + 1 + (input_x * resize_ratio)   // bitmap_to_screen — never × (dpi/96)
```

So a feature you see at content-pixel `N` is on screen at physical `scale·N`, but the driver
sends the cursor to `N` → uniform `1/scale` undershoot. The driver never queries the **target
window's** DPI awareness anywhere on the capture/click path.

`resize_ratio` itself is correct (physical-buffer-width / resized-png-width). The error is purely
that the content inside the physical buffer is sub-scaled and nothing re-stretches it — which is
why `max_image_dimension=0` (native, no resize) does **not** help.

Source: `libs/cua-driver/rust/crates/platform-windows/src/{capture.rs,tools/impl_.rs}`.

## Related upstream issues
- PR #1883 (shipped v0.5.5) — fixed the driver's **own** process DPI awareness (manifest type 24,
  removed double `/96`). This is why `get_screen_size` correctly returns physical `3840×2160` +
  `scale_factor 1.5` rather than virtualized `2560×1440 @ 1.0`. It does **not** address a
  DPI-unaware *target*.
- Issue #1879 — the earlier manifest was declared wrong and ignored (precursor to #1883).
- Issue #1882 (open) — `get_window_state` doesn't expose `resize_ratio`/original dims; coordinate-
  space docs have gaps.
- The DPI-unaware-target stretch bug (this doc) appears **unreported** as of v0.5.7.

## Fixes, in order of preference
1. **UIA `element_index` clicks** — coordinate-free, unaffected. Use whenever the target is a
   standard control.
2. **`× scale_factor` compensation** on pixel coords — see SKILL.md. Calibrate against UIA element
   rects for pixel-perfect on tiny targets.
3. **Force the target exe DPI-aware** — its `.exe` → Properties → Compatibility → "Change high DPI
   settings" → "Override high DPI scaling behavior: Application." Then capture == screen and clicks
   are 1:1. Tradeoff: a truly unaware app forced to "Application" renders physically small on 4K.
4. **Report upstream** — proper driver fix: detect the target HWND's DPI awareness
   (`GetWindowDpiAwarenessContext`/`GetDpiForWindow` vs monitor DPI) and either upscale the
   `PrintWindow` bitmap to the physical frame, or apply `physical_frame_w / content_w` (≈ scale)
   inside `bitmap_to_screen`.

## Windows coordinate background
- `SendInput` + `MOUSEEVENTF_ABSOLUTE | MOUSEEVENTF_VIRTUALDESK`: `0..65535` maps over the virtual
  desktop in **physical** pixels; `dx = round((px - SM_XVIRTUALSCREEN) * 65535 / (SM_CXVIRTUALSCREEN - 1))`.
- `GetWindowRect`/`GetCursorPos` return physical values only for a Per-Monitor-V2-aware caller;
  a system-aware/unaware caller gets virtualized (logical) values — the classic source of the drift.
- Robust: `SetProcessDpiAwarenessContext(PER_MONITOR_AWARE_V2)` at startup, or convert per-window
  with `LogicalToPhysicalPointForPerMonitorDPI` / `GetDpiForWindow(hwnd)/96`.
- Delphi/VCL got real HiDPI only in 10.3 (2018); older apps are DWM bitmap-stretched.
