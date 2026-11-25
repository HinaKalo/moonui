//! System clipboard (CF_UNICODETEXT) as UTF-8, plus opening URLs in the default browser.
const std = @import("std");
const win32 = @import("win32/win32.zig");

/// Current clipboard text as UTF-8 (caller frees), or null when it holds no text.
pub fn getText(gpa: std.mem.Allocator) ?[]u8 {
    if (win32.IsClipboardFormatAvailable(win32.CF_UNICODETEXT) == 0) return null;
    if (win32.OpenClipboard(null) == 0) return null;
    defer _ = win32.CloseClipboard();
    const h = win32.GetClipboardData(win32.CF_UNICODETEXT) orelse return null;
    const ptr = win32.GlobalLock(h) orelse return null;
    defer _ = win32.GlobalUnlock(h);
    const max_units = win32.GlobalSize(h) / 2;
    const wide: [*]const u16 = @ptrCast(@alignCast(ptr));
    var n: usize = 0;
    while (n < max_units and wide[n] != 0) n += 1;
    return std.unicode.utf16LeToUtf8Alloc(gpa, wide[0..n]) catch null;
}

/// Replaces the clipboard content with `text` (UTF-8). Returns false on failure.
pub fn setText(text: []const u8) bool {
    if (!std.unicode.utf8ValidateSlice(text)) return false;
    const units = std.unicode.calcUtf16LeLen(text) catch return false;
    const mem = win32.GlobalAlloc(win32.GMEM_MOVEABLE, (units + 1) * 2) orelse return false;
    {
        const ptr = win32.GlobalLock(mem) orelse {
            _ = win32.GlobalFree(mem);
            return false;
        };
        const wide: [*]u16 = @ptrCast(@alignCast(ptr));
        const n = std.unicode.utf8ToUtf16Le(wide[0..units], text) catch 0;
        wide[n] = 0;
        _ = win32.GlobalUnlock(mem);
    }
    if (win32.OpenClipboard(null) == 0) {
        _ = win32.GlobalFree(mem);
        return false;
    }
    defer _ = win32.CloseClipboard();
    _ = win32.EmptyClipboard();
    if (win32.SetClipboardData(win32.CF_UNICODETEXT, mem) == null) {
        _ = win32.GlobalFree(mem);
        return false;
    }
    // The clipboard owns `mem` now.
    return true;
}

/// Opens an http(s) URL in the user's default browser. Other schemes are refused.
pub fn openUrl(url: []const u8) bool {
    if (!std.mem.startsWith(u8, url, "https://") and !std.mem.startsWith(u8, url, "http://")) return false;
    var buf: [2048]u16 = undefined;
    if (url.len >= buf.len) return false;
    const wide = win32.utf8ToUtf16Z(&buf, url);
    const open = std.unicode.utf8ToUtf16LeStringLiteral("open");
    return win32.ShellExecuteW(null, open, wide.ptr, null, null, win32.SW_SHOWNORMAL) > 32;
}

/// Splits pasted text for a single-line field: newlines and tabs become spaces.
pub fn singleLine(text: []u8) []u8 {
    var out: usize = 0;
    var i: usize = 0;
    while (i < text.len) : (i += 1) {
        const c = text[i];
        if (c == '\r') {
            if (i + 1 < text.len and text[i + 1] == '\n') continue;
            text[out] = ' ';
        } else if (c == '\n' or c == '\t') {
            text[out] = ' ';
        } else {
            text[out] = c;
        }
        out += 1;
    }
    return text[0..out];
}

/// Normalizes CRLF / CR line endings to LF in place.
pub fn normalizeNewlines(text: []u8) []u8 {
    var out: usize = 0;
    var i: usize = 0;
    while (i < text.len) : (i += 1) {
        if (text[i] == '\r') {
            if (i + 1 < text.len and text[i + 1] == '\n') continue;
            text[out] = '\n';
        } else {
            text[out] = text[i];
        }
        out += 1;
    }
    return text[0..out];
}

test "single line paste" {
    var buf = "a\r\nb\tc\nd".*;
    try std.testing.expectEqualStrings("a b c d", singleLine(&buf));
}

test "normalize newlines" {
    var buf = "a\r\nb\rc\n".*;
    try std.testing.expectEqualStrings("a\nb\nc\n", normalizeNewlines(&buf));
}
