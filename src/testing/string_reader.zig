const std = @import("std");

/// A string reader for testing.
pub const StringReader = struct {
    str: []const u8,
    cursor: usize = 0,

    const Error = error{NoError};
    const Self = @This();
    const Reader = std.io.Reader(*Self, Error, read);

    fn read(self: *Self, dest: []u8) Error!usize {
        if (self.cursor >= self.str.len or dest.len == 0) {
            return 0;
        }
        const size = std.math.min(dest.len, self.str.len - self.cursor);
        std.mem.copy(u8, dest, self.str[self.cursor .. self.cursor + size]);
        self.cursor += size;
        return size;
    }

    pub fn reader(self: *Self) Reader {
        return .{ .context = self };
    }

    pub fn close(self: *Self) void {
        // Nothing to do here.
    }
};
