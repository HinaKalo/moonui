//! UTF-8 text-buffer editing primitives (caret movement, selection, insert,
//! delete) shared by `textField` and `textArea`. Pure functions, no UI state.
const std = @import("std");

/// Byte offset of the code point boundary before `pos`.
pub fn prevBoundary(buf: []const u8, pos: usize) usize {
    if (pos == 0) return 0;
    var p = @min(pos, buf.len) - 1;
    while (p > 0 and (buf[p] & 0xC0) == 0x80) p -= 1;
    return p;
}

/// Byte offset of the code point boundary after `pos`.
pub fn nextBoundary(buf: []const u8, pos: usize) usize {
    if (pos >= buf.len) return buf.len;
    const seq = std.unicode.utf8ByteSequenceLength(buf[pos]) catch 1;
    return @min(pos + seq, buf.len);
}

fn isWordByte(c: u8) bool {
    return std.ascii.isAlphanumeric(c) or c == '_' or c >= 0x80;
}

/// Ctrl+Left: start of the previous word.
pub fn prevWord(buf: []const u8, pos: usize) usize {
    var p = @min(pos, buf.len);
    while (p > 0 and !isWordByte(buf[p - 1])) p = prevBoundary(buf, p);
    while (p > 0 and isWordByte(buf[p - 1])) p = prevBoundary(buf, p);
    return p;
}

/// Ctrl+Right: end of the next word.
pub fn nextWord(buf: []const u8, pos: usize) usize {
    var p = @min(pos, buf.len);
    while (p < buf.len and !isWordByte(buf[p])) p = nextBoundary(buf, p);
    while (p < buf.len and isWordByte(buf[p])) p = nextBoundary(buf, p);
    return p;
}

/// Start of the line containing `pos` (multi-line buffers).
pub fn lineStart(buf: []const u8, pos: usize) usize {
    var p = @min(pos, buf.len);
    while (p > 0 and buf[p - 1] != '\n') p -= 1;
    return p;
}

/// End of the line containing `pos` (before its '\n').
pub fn lineEnd(buf: []const u8, pos: usize) usize {
    var p = @min(pos, buf.len);
    while (p < buf.len and buf[p] != '\n') p += 1;
    return p;
}

/// Removes bytes [a, b) from the NUL-terminated `buf` of length `len`. Returns the new length.
pub fn deleteRange(buf: []u8, len: usize, a: usize, b: usize) usize {
    const lo = @min(a, b);
    const hi = @min(@max(a, b), len);
    if (lo >= hi) return len;
    std.mem.copyForwards(u8, buf[lo .. len - (hi - lo)], buf[hi..len]);
    const new_len = len - (hi - lo);
    if (new_len < buf.len) buf[new_len] = 0;
    return new_len;
}

/// Inserts `text` at `pos`, truncated on a code point boundary so the buffer
/// keeps room for its NUL terminator. Returns the number of bytes inserted.
pub fn insert(buf: []u8, len: usize, pos: usize, text: []const u8) usize {
    if (buf.len == 0) return 0;
    const room = buf.len - 1 - @min(len, buf.len - 1);
    var n = @min(text.len, room);
    while (n > 0 and n < text.len and (text[n] & 0xC0) == 0x80) n -= 1;
    if (n == 0) return 0;
    const at = @min(pos, len);
    std.mem.copyBackwards(u8, buf[at + n .. len + n], buf[at..len]);
    @memcpy(buf[at .. at + n], text[0..n]);
    buf[len + n] = 0;
    return n;
}

pub const Selection = struct {
    lo: usize,
    hi: usize,

    pub fn empty(s: Selection) bool {
        return s.lo == s.hi;
    }
};

pub fn selection(caret: usize, anchor: usize) Selection {
    return .{ .lo = @min(caret, anchor), .hi = @max(caret, anchor) };
}

test "boundaries over CJK" {
    const s = "a中b";
    try std.testing.expectEqual(@as(usize, 1), nextBoundary(s, 0));
    try std.testing.expectEqual(@as(usize, 4), nextBoundary(s, 1));
    try std.testing.expectEqual(@as(usize, 1), prevBoundary(s, 4));
    try std.testing.expectEqual(@as(usize, 0), prevBoundary(s, 1));
}

test "insert truncates on code point boundary" {
    var buf: [6]u8 = @splat(0);
    const n = insert(&buf, 0, 0, "ab中文");
    // room = 5 bytes; "ab" + 3-byte "中" = 5.
    try std.testing.expectEqual(@as(usize, 5), n);
    try std.testing.expectEqualStrings("ab中", std.mem.sliceTo(&buf, 0));
    try std.testing.expectEqual(@as(usize, 0), insert(&buf, 5, 5, "x"));
}

test "insert and delete in the middle" {
    var buf: [32]u8 = @splat(0);
    var len = insert(&buf, 0, 0, "hello");
    len += insert(&buf, len, 2, "XY");
    try std.testing.expectEqualStrings("heXYllo", buf[0..len]);
    len = deleteRange(&buf, len, 4, 2);
    try std.testing.expectEqualStrings("hello", std.mem.sliceTo(&buf, 0));
}

test "word and line navigation" {
    const s = "foo bar\nbaz";
    try std.testing.expectEqual(@as(usize, 4), prevWord(s, 7));
    try std.testing.expectEqual(@as(usize, 7), nextWord(s, 4));
    try std.testing.expectEqual(@as(usize, 8), lineStart(s, 10));
    try std.testing.expectEqual(@as(usize, 7), lineEnd(s, 2));
}
