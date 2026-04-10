const std = @import("std");

const RawString = []const u8;

const ZBoostString = struct {
    allocator: std.mem.Allocator,
    content: []u8,

    const Self = @This();
    pub const Error = error{ OutOfMemory, InvalidUtf8, InvalidRange };

    pub fn init(allocator: std.mem.Allocator, content: RawString) !Self {
        const copy = try allocator.dupe(u8, content);
        if (!std.unicode.utf8ValidateSlice(copy)) {
            allocator.free(copy);
            return Error.InvalidUtf8;
        }
        return Self{ .allocator = allocator, .content = copy };
    }

    pub fn deinit(self: *Self) void {
        self.allocator.free(self.content);
    }

    pub fn length(self: *Self) usize {
        return self.content.len;
    }

    pub fn codepointCount(self: *Self) usize {
        return std.unicode.utf8CountCodepoints(self.content) catch unreachable;
    }

    pub fn contains(self: *Self, substring: RawString) bool {
        return std.mem.indexOf(u8, self.content, substring) != null;
    }

    pub fn startsWith(self: *Self, prefix: RawString) bool {
        return std.mem.startsWith(u8, self.content, prefix);
    }

    pub fn endsWith(self: *Self, suffix: RawString) bool {
        return std.mem.endsWith(u8, self.content, suffix);
    }

    pub fn append(self: *Self, other: RawString) !void {
        const new_len = self.content.len + other.len;
        const new_content = try self.allocator.alloc(u8, new_len);
        std.mem.copyForwards(u8, new_content, self.content);
        std.mem.copyForwards(u8, new_content[self.content.len..], other);
        if (!std.unicode.utf8ValidateSlice(new_content)) {
            self.allocator.free(new_content);
            return Error.InvalidUtf8;
        }
        self.allocator.free(self.content);
        self.content = new_content;
    }

    pub fn replace(self: *Self, needle: RawString, replacement: RawString) !void {
        if (needle.len == 0) return;

        var occurrences: usize = 0;
        var i: usize = 0;
        while (i + needle.len <= self.content.len) {
            if (std.mem.eql(u8, self.content[i .. i + needle.len], needle)) {
                occurrences += 1;
                i += needle.len;
            } else {
                i += 1;
            }
        }
        if (occurrences == 0) return;

        const new_len = self.content.len + occurrences * (replacement.len - needle.len);
        const new_content = try self.allocator.alloc(u8, new_len);

        var out_index: usize = 0;
        i = 0;
        while (i < self.content.len) {
            if (i + needle.len <= self.content.len and std.mem.eql(u8, self.content[i .. i + needle.len], needle)) {
                std.mem.copyForwards(u8, new_content[out_index .. out_index + replacement.len], replacement);
                out_index += replacement.len;
                i += needle.len;
            } else {
                new_content[out_index] = self.content[i];
                out_index += 1;
                i += 1;
            }
        }

        if (!std.unicode.utf8ValidateSlice(new_content)) {
            self.allocator.free(new_content);
            return Error.InvalidUtf8;
        }

        self.allocator.free(self.content);
        self.content = new_content;
    }

    pub fn substringCodepoints(self: *Self, start: usize, end: usize) !Self {
        const total = self.codepointCount();
        if (start > end or end > total) return Error.InvalidRange;

        var begin: usize = 0;
        var finish: usize = 0;
        var codepoint_index: usize = 0;
        var i: usize = 0;

        while (i < self.content.len) {
            if (codepoint_index == start) begin = i;
            const step = try std.unicode.utf8ByteSequenceLength(self.content[i]);
            i += step;
            codepoint_index += 1;
            if (codepoint_index == end) {
                finish = i;
                break;
            }
        }

        if (end == total and finish == 0) {
            finish = self.content.len;
        }

        return Self.init(self.allocator, self.content[begin..finish]);
    }

    pub fn reverse(self: *Self) !void {
        var offsets = try std.ArrayList(usize).initCapacity(self.allocator, 16);
        defer offsets.deinit(self.allocator);

        var i: usize = 0;
        while (i < self.content.len) {
            try offsets.append(self.allocator, i);
            const step = try std.unicode.utf8ByteSequenceLength(self.content[i]);
            i += step;
        }

        const result = try self.allocator.alloc(u8, self.content.len);
        defer self.allocator.free(result);

        var out_index: usize = 0;
        var idx: usize = offsets.items.len;
        while (idx > 0) : (idx -= 1) {
            const start = offsets.items[idx - 1];
            const step = try std.unicode.utf8ByteSequenceLength(self.content[start]);
            std.mem.copyForwards(u8, result[out_index .. out_index + step], self.content[start .. start + step]);
            out_index += step;
        }

        std.mem.copyForwards(u8, self.content, result);
    }
};

pub fn String(allocator: std.mem.Allocator, literal: RawString) !ZBoostString {
    return ZBoostString.init(allocator, literal);
}

test "check if the new string type works properly" {
    var my_string = try String(std.heap.page_allocator, "hello world");
    defer my_string.deinit();
    try my_string.reverse();
    std.debug.print("\nString length: {d}\nString reverse: {s}\n", .{
        my_string.length(),
        my_string.content,
    });
    try my_string.append("!");
    try std.testing.expect(my_string.endsWith("!"));
    try my_string.replace("ll", "LL");
    try std.testing.expect(my_string.contains("LL"));
}

test "unicode support and codepoint-safe operations" {
    var unicode_string = try String(std.heap.page_allocator, "héllo 🌍");
    defer unicode_string.deinit();

    const codepoints = unicode_string.codepointCount();
    try std.testing.expect(codepoints == 7);
    try std.testing.expect(unicode_string.startsWith("hé"));
    try std.testing.expect(unicode_string.endsWith("🌍"));

    var slice = try unicode_string.substringCodepoints(5, 7);
    defer slice.deinit();
    try std.testing.expectEqualSlices(u8, " 🌍", slice.content);

    try unicode_string.reverse();
    try std.testing.expectEqualSlices(u8, "🌍 olléh", unicode_string.content);
    try unicode_string.append("!");
    try std.testing.expect(unicode_string.endsWith("!"));
}
