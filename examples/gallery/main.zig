//! MoonWin Native Component Gallery (Direct2D 1.1 + DirectComposition + DirectWrite).
//! Replicates every page, theme, and widget skin from moon-win-gui using pure native Win32 APIs.
const std = @import("std");
const mw = @import("moonui");

const Page = enum { overview, components, forms, theming, performance };
const Plan = enum { starter, pro, team };

const State = struct {
    page: Page = .overview,
    // components
    notifications: bool = true,
    autosave: bool = false,
    compact: bool = true,
    agree: bool = true,
    beta: bool = false,
    plan: Plan = .pro,
    volume: f32 = 64,
    quality: i32 = 3,
    range_tab: usize = 1,
    view_mode: usize = 0,
    tab: usize = 0,
    region: usize = 1,
    loading: bool = false,
    progress: f32 = 0.42,
    // forms
    name: mw.TextBuffer(64) = .init("Ada Lovelace"),
    email: mw.TextBuffer(96) = .init(""),
    password: mw.TextBuffer(64) = .init(""),
    search: mw.TextBuffer(64) = .init(""),
    bio: mw.TextBuffer(256) = .init(""),
    // overlays
    dialog_open: bool = false,
    // theming
    theme_index: usize = 0,
    accent_index: usize = 0,
    radius_scale: f32 = 1.0,
    motion: bool = true,
    clicks: u32 = 0,
};

const accents = [_]mw.Color{
    mw.Color.hex(0x7C6CFF), mw.Color.hex(0x3B82F6), mw.Color.hex(0x14B8A6),
    mw.Color.hex(0x22C55E), mw.Color.hex(0xF59E0B), mw.Color.hex(0xEF4444),
    mw.Color.hex(0xEC4899),
};

/// Usage: moonwin-native-gallery [--page overview|components|forms|theming|performance]
///                               [--theme 0..3] [--capture out.bmp]
pub fn main(init: std.process.Init) !void {
    var state: State = .{};
    var capture: ?[]const u8 = null;
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    var i: usize = 1;
    while (i + 1 < args.len) : (i += 2) {
        const k = args[i];
        const v = args[i + 1];
        if (std.mem.eql(u8, k, "--page")) {
            state.page = std.meta.stringToEnum(Page, v) orelse state.page;
        } else if (std.mem.eql(u8, k, "--capture")) {
            capture = v;
        } else if (std.mem.eql(u8, k, "--theme")) {
            state.theme_index = @min(std.fmt.parseInt(usize, v, 10) catch 0, mw.themes.all.len - 1);
        }
    }
    try mw.run(.{
        .title = "MoonWin Native Gallery (Direct2D + DirectComposition + DirectWrite)",
        .width = 1320,
        .height = 860,
        .theme = mw.themes.all[state.theme_index].*,
        .capture_path = capture,
    }, &state, frame);
}

fn applyTheme(s: *State) void {
    var t = mw.themes.all[s.theme_index].*;
    if (s.accent_index > 0) t = t.withAccent(accents[s.accent_index - 1]);
    t = t.withRadius(s.radius_scale);
    t.motion.enabled = s.motion;
    mw.setTheme(t);
}

fn frame(s: *State) void {
    sidebar(s);
    mw.beginMain(.{ .max_width = 1080 });
    defer mw.endMain();
    switch (s.page) {
        .overview => overview(s),
        .components => components(s),
        .forms => forms(s),
        .theming => theming(s),
        .performance => performance(s),
    }
    confirmDialog(s);
}

// ---------------------------------------------------------------- sidebar

fn sidebar(s: *State) void {
    mw.beginSidebar(.{});
    defer mw.endSidebar();
    mw.sidebarBrand("MoonWin", "Native Direct2D", .layers);
    mw.navSection("Explore");
    if (mw.navItem(.home, "Overview", s.page == .overview, .{})) s.page = .overview;
    if (mw.navItem(.grid, "Components", s.page == .components, .{})) s.page = .components;
    if (mw.navItem(.edit, "Forms", s.page == .forms, .{ .count = 3 })) s.page = .forms;
    mw.navSection("System");
    if (mw.navItem(.palette, "Theming", s.page == .theming, .{})) s.page = .theming;
    if (mw.navItem(.activity, "Performance", s.page == .performance, .{})) s.page = .performance;

    mw.sidebarFooter(52);
    mw.beginRow(.sm);
    mw.avatar("Ada Lovelace", .{ .size = 36, .status = .success });
    mw.next();
    mw.beginGroup();
    mw.text("Ada Lovelace", .{ .size = .label, .weight = .semibold });
    mw.ui.get().box().cursor_y -= 6;
    mw.text("ada@moonwin.dev", .{ .size = .caption, .ink = .faint });
    mw.endGroup();
    mw.endRow();
}

// ---------------------------------------------------------------- overview

fn overview(s: *State) void {
    mw.pageHeader("Overview", "A dashboard assembled from pure native Direct2D + DirectWrite primitives.");
    mw.space(.lg);

    const trend_a = [_]f32{ 12, 18, 15, 22, 28, 24, 31, 35, 33, 41, 46, 52 };
    const trend_b = [_]f32{ 40, 38, 42, 37, 35, 39, 33, 30, 32, 28, 27, 25 };
    const trend_c = [_]f32{ 5, 9, 7, 12, 10, 14, 13, 17, 21, 19, 24, 27 };

    if (mw.beginGrid("kpis", 3, .{})) {
        defer mw.endGrid();
        mw.gridNext();
        kpi("revenue", "Monthly revenue", "$48,210", 12.4, &trend_a, .accent);
        mw.gridNext();
        kpi("latency", "p95 latency", "182 ms", -8.1, &trend_b, .success);
        mw.gridNext();
        kpi("users", "Active users", "9,482", 4.7, &trend_c, .info);
    }
    mw.space(.md);

    if (mw.beginGrid("panels", 2, .{})) {
        defer mw.endGrid();
        mw.gridNext();
        mw.beginCard("activity", .{});
        mw.section("Recent activity", "Latest events across your workspace");
        mw.space(.xs);
        activityRow("Grace Hopper", "deployed v2.4.0 to production", "2m", .success);
        activityRow("Alan Turing", "opened a review on the parser", "18m", .info);
        activityRow("Linus T.", "flagged a failing nightly build", "1h", .danger);
        activityRow("Margaret H.", "updated the release checklist", "3h", .neutral);
        _ = mw.endCard();

        mw.gridNext();
        mw.beginCard("storage", .{});
        mw.section("Storage", "Usage by category");
        mw.space(.xs);
        usageRow("Media", "68.2 GB", 0.68, .accent);
        usageRow("Documents", "21.4 GB", 0.21, .info);
        usageRow("Backups", "44.9 GB", 0.45, .warning);
        mw.space(.sm);
        mw.beginRow(.sm);
        if (mw.button("Upgrade plan", .{ .variant = .primary, .icon = .sparkles })) {
            mw.toast(.accent, "Upgrade started", .{ .description = "We'll email you when your new quota is active." });
        }
        mw.next();
        if (mw.button("Manage", .{ .variant = .ghost, .icon_right = .arrow_right })) s.page = .components;
        mw.endRow();
        _ = mw.endCard();
    }
}

fn kpi(id: [:0]const u8, title: []const u8, value: []const u8, delta: f32, trend: []const f32, tone: mw.Tone) void {
    mw.beginCard(id, .{ .hoverable = true });
    mw.stat(title, value, delta);
    mw.space(.sm);
    mw.sparkline(trend, .{ .tone = tone, .height = 44 });
    if (mw.endCard()) mw.toast(.info, title, .{ .description = "Opening detailed report..." });
}

fn activityRow(who: []const u8, what: []const u8, when: []const u8, tone: mw.Tone) void {
    mw.beginRow(.md);
    mw.avatar(who, .{ .size = 32 });
    mw.next();
    mw.beginGroup();
    mw.text(who, .{ .size = .label, .weight = .semibold });
    mw.ui.get().box().cursor_y -= 6;
    mw.text(what, .{ .size = .label, .ink = .muted });
    mw.endGroup();
    mw.endRow();
    mw.sameLine(.sm);
    mw.alignRight(56);
    mw.badge(when, .{ .tone = tone, .dot = true });
    mw.space(.xs);
}

fn usageRow(name: []const u8, amount: []const u8, frac: f32, tone: mw.Tone) void {
    mw.text(name, .{ .size = .label, .weight = .medium });
    mw.sameLine(.sm);
    mw.alignRight(56);
    mw.text(amount, .{ .size = .label, .ink = .muted });
    mw.progress(mw.fmt("usage-{s}", .{name}), frac, .{ .tone = tone });
    mw.space(.xs);
}

// ---------------------------------------------------------------- components

fn components(s: *State) void {
    mw.pageHeader("Components", "Every control, every variant.");
    mw.space(.lg);

    mw.beginCard("buttons", .{});
    mw.section("Buttons", "Six variants, three sizes, icons, loading and disabled states.");
    mw.beginRow(.sm);
    if (mw.button("Primary", .{ .variant = .primary })) s.clicks += 1;
    mw.next();
    if (mw.button("Secondary", .{ .variant = .secondary })) s.clicks += 1;
    mw.next();
    if (mw.button("Outline", .{ .variant = .outline })) s.clicks += 1;
    mw.next();
    if (mw.button("Ghost", .{ .variant = .ghost })) s.clicks += 1;
    mw.next();
    if (mw.button("Soft", .{ .variant = .soft })) s.clicks += 1;
    mw.next();
    if (mw.button("Delete", .{ .variant = .danger, .icon = .trash })) s.dialog_open = true;
    mw.endRow();
    mw.space(.xs);

    mw.beginRow(.sm);
    _ = mw.button("Small", .{ .size = .sm, .variant = .outline });
    mw.next();
    _ = mw.button("Medium", .{ .size = .md, .variant = .outline });
    mw.next();
    _ = mw.button("Large", .{ .size = .lg, .variant = .outline, .icon = .download });
    mw.next();
    if (mw.button("Save changes", .{ .variant = .primary, .loading = s.loading, .icon = .check })) {
        s.loading = true;
    }
    mw.next();
    if (s.loading) {
        if (mw.button("Stop", .{ .variant = .ghost })) s.loading = false;
    } else {
        _ = mw.button("Disabled", .{ .disabled = true });
    }
    mw.endRow();
    mw.space(.xs);

    mw.beginRow(.xs);
    inline for (.{ mw.Icon.bell, .search, .settings, .heart, .star, .copy, .refresh, .external }) |ic| {
        _ = mw.iconButton("##ib" ++ @tagName(ic), ic, .{ .tooltip = @tagName(ic) });
        mw.next();
    }
    _ = mw.iconButton("##ibactive", .bolt, .{ .active = true, .tooltip = "Active state" });
    mw.next();
    if (mw.iconButton("##more", .more, .{ .variant = .outline, .tooltip = "Open menu" })) mw.openMenu("demo-menu");
    if (mw.beginMenu("demo-menu")) {
        defer mw.endMenu();
        mw.menuLabel("Actions");
        if (mw.menuItem("Rename", .{ .icon = .edit, .shortcut = "F2" })) mw.toast(.info, "Rename", .{});
        if (mw.menuItem("Duplicate", .{ .icon = .copy, .shortcut = "Ctrl+D" })) mw.toast(.info, "Duplicated", .{});
        _ = mw.menuItem("Share", .{ .icon = .external });
        mw.menuSeparator();
        if (mw.menuItem("Delete", .{ .icon = .trash, .danger = true })) s.dialog_open = true;
    }
    mw.endRow();
    mw.text(mw.fmt("Clicks: {d}", .{s.clicks}), .{ .size = .caption, .ink = .faint });
    _ = mw.endCard();
    mw.space(.md);

    if (mw.beginGrid("ctl", 2, .{})) {
        defer mw.endGrid();
        mw.gridNext();
        mw.beginCard("toggles", .{});
        mw.section("Selection", "Switches, checkboxes and radio groups.");
        _ = mw.toggle("Push notifications", &s.notifications);
        _ = mw.toggle("Autosave drafts", &s.autosave);
        _ = mw.toggle("Compact mode", &s.compact);
        mw.space(.xs);
        _ = mw.checkbox("I agree to the terms", &s.agree);
        _ = mw.checkbox("Join the beta channel", &s.beta);
        mw.space(.xs);
        _ = mw.radioGroup("plan", Plan, &s.plan, .{ .labels = &.{ "Starter", "Pro", "Team" }, .horizontal = true });
        _ = mw.endCard();

        mw.gridNext();
        mw.beginCard("sliders", .{});
        mw.section("Range", "Sliders with keyboard support (← →).");
        _ = mw.slider("Volume", &s.volume, 0, 100, .{ .suffix = "%" });
        mw.space(.xs);
        _ = mw.sliderInt("Quality", &s.quality, 1, 5, .{});
        mw.space(.xs);
        _ = mw.slider("Progress", &s.progress, 0, 1, .{ .decimals = 2 });
        mw.progress("p-demo", s.progress, .{});
        mw.space(.xs);
        mw.progressIndeterminate(.{ .tone = .info, .height = 4 });
        _ = mw.endCard();
    }
    mw.space(.md);

    mw.beginCard("nav", .{});
    mw.section("Navigation", "Segmented controls, tabs and selects.");
    _ = mw.segmented("range", &.{ "Day", "Week", "Month", "Year" }, &s.range_tab, .{});
    mw.sameLine(.lg);
    _ = mw.segmented("view", &.{ "Grid", "List" }, &s.view_mode, .{ .size = .sm });
    mw.space(.sm);
    _ = mw.tabs("tabs", &.{ "General", "Members", "Billing", "Integrations" }, &s.tab);
    mw.space(.sm);
    mw.field("Region");
    _ = mw.select("Region", &.{ "US East (Virginia)", "EU West (Frankfurt)", "Asia (Tokyo)", "Asia (Seoul)" }, &s.region, .{ .width = .{ .px = 280 } });
    _ = mw.endCard();
    mw.space(.md);

    mw.beginCard("display", .{});
    mw.section("Display", "Badges, avatars, spinners, key caps, links and icons.");
    mw.beginRow(.sm);
    mw.badge("Neutral", .{});
    mw.next();
    mw.badge("Accent", .{ .tone = .accent });
    mw.next();
    mw.badge("Online", .{ .tone = .success, .dot = true });
    mw.next();
    mw.badge("Pending", .{ .tone = .warning });
    mw.next();
    mw.badge("Failed", .{ .tone = .danger, .solid = true });
    mw.next();
    mw.badge("Beta", .{ .tone = .info, .solid = true });
    mw.endRow();
    mw.space(.sm);
    mw.beginRow(.sm);
    mw.avatar("Grace Hopper", .{ .status = .success });
    mw.next();
    mw.avatar("Alan Turing", .{ .status = .warning });
    mw.next();
    mw.avatar("Katherine Johnson", .{});
    mw.next();
    mw.avatar("Edsger Dijkstra", .{ .size = 28 });
    mw.next();
    mw.spinner(.{});
    mw.next();
    mw.spinner(.{ .size = 16, .tone = .success });
    mw.next();
    mw.kbd("Ctrl");
    mw.next();
    mw.kbd("K");
    mw.next();
    if (mw.link("Read the docs")) mw.toast(.info, "Docs", .{ .description = "Opening documentation..." });
    mw.endRow();
    mw.space(.sm);
    mw.dividerText("ICONS");
    const all = std.enums.values(mw.Icon);
    for (all, 0..) |ic, i| {
        if (i % 14 != 0) mw.sameLine(.md);
        mw.icon(ic, .{ .size = 20, .ink = .muted });
        mw.tooltip(mw.fmt("{s}", .{@tagName(ic)}));
    }
    _ = mw.endCard();
}

// ---------------------------------------------------------------- forms

fn forms(s: *State) void {
    mw.pageHeader("Forms", "Inputs with focus rings, icons and hints.");
    mw.space(.lg);
    if (mw.beginGrid("formgrid", 2, .{})) {
        defer mw.endGrid();
        mw.gridNext();
        mw.beginCard("profile", .{});
        mw.section("Profile", "This information is shown publicly.");
        mw.field("Full name");
        _ = mw.textField("name", &s.name.buf, .{ .icon = .user });
        mw.field("Email");
        _ = mw.textField("email", &s.email.buf, .{ .hint = "you@example.com", .icon = .mail });
        mw.fieldHint("We'll never share your email.");
        mw.field("Password");
        _ = mw.textField("password", &s.password.buf, .{ .hint = "At least 12 characters", .icon = .lock, .password = true });
        mw.space(.sm);
        mw.beginRow(.sm);
        if (mw.button("Save profile", .{ .variant = .primary })) {
            if (s.email.slice().len == 0) {
                mw.toast(.warning, "Email required", .{ .description = "Please enter an email address." });
            } else {
                mw.toast(.success, "Profile saved", .{ .description = mw.fmt("Updated {s}", .{s.name.slice()}) });
            }
        }
        mw.next();
        if (mw.button("Reset", .{ .variant = .ghost })) {
            s.name.set("Ada Lovelace");
            s.email.clear();
            s.password.clear();
        }
        mw.endRow();
        _ = mw.endCard();

        mw.gridNext();
        mw.beginCard("search", .{});
        mw.section("Search", "Submit with Enter.");
        if (mw.textField("##search", &s.search.buf, .{ .hint = "Search anything...", .icon = .search, .submit_on_enter = true })) {
            mw.toast(.info, "Search", .{ .description = mw.fmt("You searched for \"{s}\"", .{s.search.slice()}) });
        }
        mw.space(.sm);
        mw.field("Small / large sizes");
        _ = mw.textField("##sm", &s.bio.buf, .{ .hint = "Small input", .size = .sm });
        _ = mw.textField("##lg", &s.bio.buf, .{ .hint = "Large input (shares the buffer)", .size = .lg });
        mw.space(.sm);
        mw.field("中文输入 / CJK text");
        mw.text("你好，世界 — 这是一段中文示例文本，由原生 DirectWrite 自动回退至微软雅黑矢量渲染。", .{ .wrap = true });
        _ = mw.endCard();
    }
}

// ---------------------------------------------------------------- theming

fn theming(s: *State) void {
    mw.pageHeader("Theming", "Swap presets, accents, radius and motion live.");
    mw.space(.lg);
    var changed = false;

    mw.beginCard("presets", .{});
    mw.section("Preset", null);
    var names: [mw.themes.all.len][:0]const u8 = undefined;
    for (mw.themes.all, 0..) |t, i| names[i] = mw.fmt("{s}", .{t.name});
    if (mw.segmented("preset", &names, &s.theme_index, .{})) changed = true;
    mw.space(.md);
    mw.section("Accent", null);
    if (swatch(0, mw.themes.all[s.theme_index].palette.accent, s.accent_index == 0)) {
        s.accent_index = 0;
        changed = true;
    }
    for (accents, 0..) |col, i| {
        mw.sameLine(.sm);
        if (swatch(i + 1, col, s.accent_index == i + 1)) {
            s.accent_index = i + 1;
            changed = true;
        }
    }
    mw.space(.md);
    mw.section("Shape & motion", null);
    if (mw.slider("Corner radius", &s.radius_scale, 0, 2, .{ .decimals = 1, .suffix = "x", .step = 0.1, .width = .{ .px = 360 } })) changed = true;
    mw.space(.xs);
    if (mw.toggle("Animations", &s.motion)) changed = true;
    _ = mw.endCard();
    if (changed) applyTheme(s);

    mw.space(.md);
    mw.beginCard("preview", .{});
    mw.section("Preview", "Components re-render with the active tokens.");
    mw.beginRow(.sm);
    _ = mw.button("Primary", .{ .variant = .primary, .icon = .sparkles });
    mw.next();
    _ = mw.button("Soft", .{ .variant = .soft });
    mw.next();
    _ = mw.button("Outline", .{ .variant = .outline });
    mw.next();
    mw.badge("Accent", .{ .tone = .accent });
    mw.next();
    mw.spinner(.{ .size = 18 });
    mw.endRow();
    _ = mw.endCard();
}

fn swatch(i: usize, col: mw.Color, selected: bool) bool {
    const u = mw.ui.get();
    const size: f32 = 28;
    const r = u.allocRect(mw.v2(size, size));
    const id = u.hashInt(i) ^ 0x57A7C4;
    const hit = u.buttonBehavior(id, r, false);
    const center = r.center();
    u.dl().circleFilled(center, size * 0.5, col);
    if (selected) {
        u.dl().circleStroke(center, size * 0.5 + 3, col, 2);
        mw.icons.draw(u.dl(), .check, center, 16, col.contrastText());
    }
    return hit.clicked;
}

// ---------------------------------------------------------------- performance

fn performance(s: *State) void {
    mw.pageHeader("Performance", "Pure native DirectComposition + event-driven 0% idle CPU loop.");
    mw.space(.lg);
    const st = mw.stats();
    if (mw.beginGrid("perf", 3, .{})) {
        defer mw.endGrid();
        mw.gridNext();
        mw.beginCard("frames", .{});
        mw.stat("Frames presented", mw.fmt("{d}", .{st.frames_presented}), null);
        mw.caption("Stops increasing when you stop moving the mouse.");
        _ = mw.endCard();
        mw.gridNext();
        mw.beginCard("state", .{});
        mw.text("Loop state", .{ .size = .label, .weight = .medium, .ink = .muted });
        mw.text(if (st.animating) "Animating" else "Idle-ready", .{ .size = .display, .weight = .bold });
        mw.badge(if (st.animating) "rendering continuously" else "sleeping on input", .{ .tone = if (st.animating) .warning else .success, .dot = true });
        _ = mw.endCard();
        mw.gridNext();
        mw.beginCard("fps", .{});
        mw.stat("Rolling FPS (while active)", mw.fmt("{d:.0}", .{st.fps}), null);
        mw.caption("Vsync-capped via DirectComposition.");
        _ = mw.endCard();
    }
    mw.space(.md);
    mw.beginCard("howto", .{});
    mw.section("How it works", null);
    mw.text("Zero Dear ImGui, zero C/C++ dependencies. Direct2D 1.1 renders crisp vector shapes and DirectWrite handles native typography and CJK fallback directly onto a DirectComposition premultiplied-alpha flip swapchain. When idle, the loop blocks in MsgWaitForMultipleObjectsEx.", .{ .wrap = true, .ink = .muted });
    mw.space(.sm);
    mw.beginRow(.sm);
    if (mw.button("Trigger toast", .{ .icon = .bell })) mw.toast(.success, "Hello!", .{ .description = "Native Direct2D toast notification." });
    mw.next();
    if (mw.button("Open dialog", .{ .variant = .outline })) s.dialog_open = true;
    mw.endRow();
    _ = mw.endCard();
}

// ---------------------------------------------------------------- dialog

fn confirmDialog(s: *State) void {
    if (mw.beginDialog("Delete project?", &s.dialog_open, .{ .description = "This permanently removes the project and all of its data. This action cannot be undone." })) {
        defer mw.endDialog();
        mw.beginDialogActions(220);
        if (mw.button("Cancel", .{ .variant = .ghost })) s.dialog_open = false;
        mw.sameLine(.sm);
        if (mw.button("Delete", .{ .variant = .danger, .icon = .trash })) {
            s.dialog_open = false;
            mw.toast(.danger, "Project deleted", .{ .description = "moonwin-demo was removed." });
        }
        mw.endDialogActions();
    }
}
