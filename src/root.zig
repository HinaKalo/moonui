//! MoonWin Native GUI — Public flat API barrel.
//! Pure Zig + Win32 + Direct2D 1.1 + DirectComposition + DirectWrite.
const std = @import("std");

pub const math = @import("math.zig");
pub const color = @import("color.zig");
pub const theme_mod = @import("theme.zig");
pub const anim = @import("anim.zig");
pub const drawlist = @import("drawlist.zig");
pub const renderer = @import("renderer.zig");
pub const icons = @import("icons.zig");
pub const ui = @import("ui.zig");
pub const layout = @import("layout.zig");
pub const widgets = @import("widgets.zig");
pub const chat = @import("chat.zig");
pub const app = @import("app.zig");
pub const clipboard = @import("clipboard.zig");
pub const textedit = @import("textedit.zig");
pub const shell = @import("shell.zig");
pub const notification = @import("toast.zig");
pub const image = @import("image.zig");

// Core types
pub const Vec2 = math.Vec2;
pub const Rect = math.Rect;
pub const v2 = math.v2;
pub const Color = color.Color;
pub const Theme = theme_mod.Theme;
pub const Palette = theme_mod.Palette;
pub const Tone = theme_mod.Tone;
pub const themes = theme_mod.presets;
pub const Icon = icons.Icon;
pub const Stats = ui.Stats;

// App
pub const AppOptions = app.AppOptions;
pub const run = app.run;
pub const wake = app.wake;
pub const quit = app.quit;
pub const window = app.window;
pub const activate = app.activate;
pub const isForeground = app.isForeground;
pub const flash = app.flash;
pub const stopFlash = app.stopFlash;
pub const hide = app.hide;
pub const isVisible = app.isVisible;
pub const setOverlay = app.setOverlay;
pub const setTitle = app.setTitle;
pub const ScrollState = ui.ScrollState;

pub fn setTheme(t: Theme) void {
    const u = ui.get();
    u.theme = t;
    u.theme_changed = true;
}

pub fn currentTheme() *const Theme {
    return &ui.get().theme;
}

pub fn palette() *const Palette {
    return &ui.get().theme.palette;
}

pub fn stats() Stats {
    return ui.get().stats;
}

pub fn fmt(comptime format: []const u8, args: anytype) [:0]const u8 {
    return ui.get().fmt(format, args);
}

/// Files dropped on the window this frame (needs `AppOptions.accept_files`).
pub fn droppedFiles() []const []const u8 {
    const items = ui.get().dropped.items;
    return @ptrCast(items);
}

/// Where the files of this frame were dropped.
pub fn dropPos() Vec2 {
    return ui.get().drop_pos;
}

/// Uploads decoded pixels (`image.Pixels`) as a bitmap; 0 on failure. UI thread.
pub fn createImage(px: *const image.Pixels) u32 {
    return ui.get().renderer.createImage(px.w, px.h, px.data);
}

pub fn releaseImage(id: u32) void {
    if (ui.ctx) |u| u.renderer.releaseImage(id);
}

/// Draws an image (from `createImage`) stretched to `r`.
pub fn imageAt(r: Rect, id: u32, rounding: f32) void {
    ui.get().dl().image(r, id, rounding, 1.0);
}

/// Device pixels per DIP (decode images at `size * pixelScale()` for sharp output).
pub fn pixelScale() f32 {
    return ui.get().renderer.pixelScale();
}

/// One-line text shortened with "…" to fit `max_w` (see UiContext.ellipsize).
pub fn ellipsize(str: []const u8, style: ui.TextStyle, max_w: f32) []const u8 {
    return ui.get().ellipsize(str, style, max_w);
}

// Layout
pub const Gap = layout.Gap;
pub const CardOptions = layout.CardOptions;
pub const GridOptions = layout.GridOptions;
pub const SidebarOptions = layout.SidebarOptions;
pub const NavItemOptions = layout.NavItemOptions;
pub const MainOptions = layout.MainOptions;

pub const space = layout.space;
pub const sameLine = layout.sameLine;
pub const alignRight = layout.alignRight;
pub const beginRow = layout.beginRow;
pub const next = layout.next;
pub const endRow = layout.endRow;
pub const beginGroup = layout.beginGroup;
pub const endGroup = layout.endGroup;
pub const beginCard = layout.beginCard;
pub const endCard = layout.endCard;
pub const beginGrid = layout.beginGrid;
pub const gridNext = layout.gridNext;
pub const endGrid = layout.endGrid;
pub const beginSidebar = layout.beginSidebar;
pub const endSidebar = layout.endSidebar;
pub const sidebarFooter = layout.sidebarFooter;
pub const sidebarBrand = layout.sidebarBrand;
pub const navSection = layout.navSection;
pub const navItem = layout.navItem;
pub const beginMain = layout.beginMain;
pub const endMain = layout.endMain;
pub const pageHeader = layout.pageHeader;
pub const section = layout.section;
pub const field = layout.field;
pub const fieldHint = layout.fieldHint;
pub const ScrollOptions = layout.ScrollOptions;
pub const beginScroll = layout.beginScroll;
pub const endScroll = layout.endScroll;
pub const scrollToBottom = layout.scrollToBottom;
pub const keepScrollFromBottom = layout.keepScrollFromBottom;

// Widgets
pub const TextSize = widgets.TextSize;
pub const Weight = widgets.Weight;
pub const Ink = widgets.Ink;
pub const Width = widgets.Width;
pub const ControlSize = widgets.ControlSize;
pub const TextOptions = widgets.TextOptions;
pub const IconOptions = widgets.IconOptions;
pub const Variant = widgets.Variant;
pub const ButtonOptions = widgets.ButtonOptions;
pub const IconButtonOptions = widgets.IconButtonOptions;
pub const SliderOptions = widgets.SliderOptions;
pub const InputOptions = widgets.InputOptions;
pub const TextBuffer = widgets.TextBuffer;
pub const SegmentedOptions = widgets.SegmentedOptions;
pub const SelectOptions = widgets.SelectOptions;
pub const BadgeOptions = widgets.BadgeOptions;
pub const ProgressOptions = widgets.ProgressOptions;
pub const SpinnerOptions = widgets.SpinnerOptions;
pub const AvatarOptions = widgets.AvatarOptions;
pub const SparklineOptions = widgets.SparklineOptions;
pub const ToastOptions = widgets.ToastOptions;
pub const MenuItemOptions = widgets.MenuItemOptions;
pub const DialogOptions = widgets.DialogOptions;

pub const text = widgets.text;
pub const heading = widgets.heading;
pub const display = widgets.display;
pub const muted = widgets.muted;
pub const caption = widgets.caption;
pub const label = widgets.label;
pub const link = widgets.link;
pub const kbd = widgets.kbd;
pub const icon = widgets.icon;
pub const button = widgets.button;
pub const iconButton = widgets.iconButton;
pub const toggle = widgets.toggle;
pub const checkbox = widgets.checkbox;
pub const radio = widgets.radio;
pub const radioGroup = widgets.radioGroup;
pub const slider = widgets.slider;
pub const sliderInt = widgets.sliderInt;
pub const textField = widgets.textField;
pub const TextAreaOptions = widgets.TextAreaOptions;
pub const TextAreaResult = widgets.TextAreaResult;
pub const textArea = widgets.textArea;
pub const segmented = widgets.segmented;
pub const tabs = widgets.tabs;
pub const select = widgets.select;
pub const badge = widgets.badge;
pub const progress = widgets.progress;
pub const progressIndeterminate = widgets.progressIndeterminate;
pub const spinner = widgets.spinner;
pub const avatar = widgets.avatar;
pub const divider = widgets.divider;
pub const dividerText = widgets.dividerText;
pub const tooltip = widgets.tooltip;
pub const sparkline = widgets.sparkline;
pub const stat = widgets.stat;
pub const toast = widgets.toast;
pub const openMenu = widgets.openMenu;
pub const openMenuAt = widgets.openMenuAt;
pub const isMenuOpen = widgets.isMenuOpen;
pub const closeMenu = widgets.closeMenu;
pub const beginMenu = widgets.beginMenu;
pub const menuLabel = widgets.menuLabel;
pub const menuItem = widgets.menuItem;
pub const menuSeparator = widgets.menuSeparator;
pub const endMenu = widgets.endMenu;
pub const beginDialog = widgets.beginDialog;
pub const beginDialogActions = widgets.beginDialogActions;
pub const endDialogActions = widgets.endDialogActions;
pub const endDialog = widgets.endDialog;
pub const searchBox = chat.searchBox;

test {
    _ = color;
    _ = theme_mod;
    _ = anim;
    _ = clipboard;
    _ = textedit;
    _ = renderer;
    _ = shell;
    _ = notification;
    _ = image;
}
