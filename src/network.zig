const std = @import("std");
const mem = std.mem;
const net = std.net;
const fs = std.fs;

/// Socket wrapper for TCP/UDP operations
pub const Socket = struct {
    socket: net.Stream = undefined,
    allocator: mem.Allocator,
    is_connected: bool = false,
    address: net.Address = undefined,
    timeout_ms: u64 = 5000,

    const Self = @This();

    /// Initialize a TCP socket
    pub fn initTcp(allocator: mem.Allocator) !Self {
        return Self{
            .allocator = allocator,
            .is_connected = false,
        };
    }

    /// Connect to a TCP server
    pub fn connect(self: *Self, host: []const u8, port: u16) !void {
        const address = try net.Address.parseIp(host, port);
        self.socket = try address.connect();
        self.is_connected = true;
        self.address = address;
    }

    /// Connect with timeout (simple implementation using non-blocking socket)
    pub fn connectWithTimeout(self: *Self, host: []const u8, port: u16) !void {
        // For now, use regular connect with timeout_ms set
        try self.connect(host, port);
    }

    /// Send data through socket
    pub fn send(self: *Self, data: []const u8) !usize {
        if (!self.is_connected) {
            return error.SocketNotConnected;
        }
        return try self.socket.writeAll(data);
    }

    /// Receive data from socket
    pub fn recv(self: *Self, buffer: []u8) !usize {
        if (!self.is_connected) {
            return error.SocketNotConnected;
        }
        return try self.socket.read(buffer);
    }

    /// Receive all available data
    pub fn recvAll(self: *Self, buffer: []u8) ![]u8 {
        if (!self.is_connected) {
            return error.SocketNotConnected;
        }
        const bytes_read = try self.recv(buffer);
        return buffer[0..bytes_read];
    }

    /// Close the socket
    pub fn close(self: *Self) void {
        if (self.is_connected) {
            self.socket.close();
            self.is_connected = false;
        }
    }

    /// Check if socket is connected
    pub fn isConnected(self: *Self) bool {
        return self.is_connected;
    }

    /// Set socket timeout
    pub fn setTimeout(self: *Self, timeout_ms: u64) void {
        self.timeout_ms = timeout_ms;
    }

    /// Deinitialize socket
    pub fn deinit(self: *Self) void {
        self.close();
    }
};

/// HTTP Request builder
pub const HttpRequest = struct {
    method: []const u8,
    uri: []const u8,
    headers: std.StringHashMap([]const u8),
    body: ?[]const u8,
    allocator: mem.Allocator,

    const Self = @This();

    /// Initialize HTTP GET request
    pub fn get(allocator: mem.Allocator, uri: []const u8) !Self {
        return Self{
            .method = "GET",
            .uri = uri,
            .headers = std.StringHashMap([]const u8).init(allocator),
            .body = null,
            .allocator = allocator,
        };
    }

    /// Initialize HTTP POST request
    pub fn post(allocator: mem.Allocator, uri: []const u8, body: []const u8) !Self {
        var req = Self{
            .method = "POST",
            .uri = uri,
            .headers = std.StringHashMap([]const u8).init(allocator),
            .body = body,
            .allocator = allocator,
        };
        try req.setHeader("Content-Length", try std.fmt.allocPrint(allocator, "{}", .{body.len}));
        return req;
    }

    /// Initialize HTTP PUT request
    pub fn put(allocator: mem.Allocator, uri: []const u8, body: []const u8) !Self {
        var req = Self{
            .method = "PUT",
            .uri = uri,
            .headers = std.StringHashMap([]const u8).init(allocator),
            .body = body,
            .allocator = allocator,
        };
        try req.setHeader("Content-Length", try std.fmt.allocPrint(allocator, "{}", .{body.len}));
        return req;
    }

    /// Initialize HTTP DELETE request
    pub fn delete(allocator: mem.Allocator, uri: []const u8) !Self {
        return Self{
            .method = "DELETE",
            .uri = uri,
            .headers = std.StringHashMap([]const u8).init(allocator),
            .body = null,
            .allocator = allocator,
        };
    }

    /// Set a header
    pub fn setHeader(self: *Self, key: []const u8, value: []const u8) !void {
        try self.headers.put(key, value);
    }

    /// Build the raw HTTP request
    pub fn build(self: *Self, host: []const u8) ![]u8 {
        var parts = try std.ArrayList([]const u8).initCapacity(self.allocator, 10);
        defer parts.deinit(self.allocator);

        // Request line
        const req_line = try std.fmt.allocPrint(self.allocator, "{s} {s} HTTP/1.1\r\n", .{ self.method, self.uri });
        try parts.append(self.allocator, req_line);

        // Host header
        const host_line = try std.fmt.allocPrint(self.allocator, "Host: {s}\r\n", .{host});
        try parts.append(self.allocator, host_line);

        // Other headers
        var iter = self.headers.iterator();
        while (iter.next()) |entry| {
            const header_line = try std.fmt.allocPrint(self.allocator, "{s}: {s}\r\n", .{ entry.key_ptr.*, entry.value_ptr.* });
            try parts.append(self.allocator, header_line);
        }

        // End of headers
        try parts.append(self.allocator, "\r\n");

        // Body
        if (self.body) |body| {
            try parts.append(self.allocator, body);
        }

        // Concatenate all parts
        var total_len: usize = 0;
        for (parts.items) |part| {
            total_len += part.len;
        }

        const buffer = try self.allocator.alloc(u8, total_len);
        var offset: usize = 0;
        for (parts.items) |part| {
            @memcpy(buffer[offset..][0..part.len], part);
            offset += part.len;
        }

        // Free allocated header strings (but keep body and static strings)
        for (0..parts.items.len - (if (self.body != null) @as(usize, 2) else @as(usize, 1))) |i| {
            self.allocator.free(parts.items[i]);
        }

        return buffer;
    }

    /// Deinitialize request
    pub fn deinit(self: *Self) void {
        self.headers.deinit();
    }
};

/// HTTP Response parser
pub const HttpResponse = struct {
    status_code: u16,
    headers: std.StringHashMap([]const u8),
    body: []u8,
    allocator: mem.Allocator,

    const Self = @This();

    /// Parse HTTP response from raw bytes
    pub fn parse(allocator: mem.Allocator, raw: []const u8) !Self {
        var response = Self{
            .status_code = 0,
            .headers = std.StringHashMap([]const u8).init(allocator),
            .body = &[_]u8{},
            .allocator = allocator,
        };

        var lines = std.mem.splitSequence(u8, raw, "\r\n");

        // Parse status line
        if (lines.next()) |status_line| {
            var parts = std.mem.splitSequence(u8, status_line, " ");
            _ = parts.next(); // HTTP/1.1
            if (parts.next()) |code_str| {
                response.status_code = try std.fmt.parseInt(u16, code_str, 10);
            }
        }

        // Parse headers
        while (lines.next()) |line| {
            if (line.len == 0) {
                break; // End of headers
            }
            if (std.mem.indexOf(u8, line, ": ")) |colon_pos| {
                const key = try allocator.dupe(u8, line[0..colon_pos]);
                const value = try allocator.dupe(u8, line[colon_pos + 2 ..]);
                try response.headers.put(key, value);
            }
        }

        // Remaining is body
        if (lines.next()) |body_start| {
            response.body = try allocator.dupe(u8, body_start);
        }

        return response;
    }

    /// Get header value
    pub fn getHeader(self: *Self, key: []const u8) ?[]const u8 {
        return self.headers.get(key);
    }

    /// Deinitialize response
    pub fn deinit(self: *Self) void {
        var iter = self.headers.iterator();
        while (iter.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.*);
        }
        self.headers.deinit();
        if (self.body.len > 0) {
            self.allocator.free(self.body);
        }
    }
};

/// Connection state for retry logic
pub const Connection = struct {
    host: []const u8,
    port: u16,
    max_retries: u32 = 3,
    retry_delay_ms: u64 = 1000,
    allocator: mem.Allocator,

    const Self = @This();

    /// Initialize connection
    pub fn init(allocator: mem.Allocator, host: []const u8, port: u16) !Self {
        return Self{
            .host = try allocator.dupe(u8, host),
            .port = port,
            .allocator = allocator,
        };
    }

    /// Set retry parameters
    pub fn setRetryParams(self: *Self, max_retries: u32, retry_delay_ms: u64) void {
        self.max_retries = max_retries;
        self.retry_delay_ms = retry_delay_ms;
    }

    /// Connect with retry logic
    pub fn connectWithRetry(self: *Self) !Socket {
        var socket = try Socket.initTcp(self.allocator);
        var attempt: u32 = 0;

        while (attempt < self.max_retries) : (attempt += 1) {
            if (socket.connect(self.host, self.port)) {
                return socket;
            } else |err| {
                if (attempt < self.max_retries - 1) {
                    std.time.sleep(self.retry_delay_ms * 1_000_000);
                } else {
                    return err;
                }
            }
        }

        return error.ConnectionFailed;
    }

    /// Deinitialize connection
    pub fn deinit(self: *Self) void {
        self.allocator.free(self.host);
    }
};

/// HTTP Client
pub const HttpClient = struct {
    allocator: mem.Allocator,
    default_timeout_ms: u64 = 5000,

    const Self = @This();

    /// Initialize HTTP client
    pub fn init(allocator: mem.Allocator) Self {
        return Self{
            .allocator = allocator,
        };
    }

    /// Send GET request
    pub fn get(self: *Self, host: []const u8, port: u16, uri: []const u8) ![]u8 {
        var socket = try Socket.initTcp(self.allocator);
        defer socket.deinit();

        try socket.connect(host, port);
        socket.setTimeout(self.default_timeout_ms);

        var request = try HttpRequest.get(self.allocator, uri);
        defer request.deinit();

        const raw_request = try request.build(host);
        defer self.allocator.free(raw_request);

        _ = try socket.send(raw_request);

        var buffer = try self.allocator.alloc(u8, 4096);
        const bytes_read = try socket.recv(buffer);

        return buffer[0..bytes_read];
    }

    /// Send POST request
    pub fn post(self: *Self, host: []const u8, port: u16, uri: []const u8, body: []const u8) ![]u8 {
        var socket = try Socket.initTcp(self.allocator);
        defer socket.deinit();

        try socket.connect(host, port);
        socket.setTimeout(self.default_timeout_ms);

        var request = try HttpRequest.post(self.allocator, uri, body);
        defer request.deinit();

        const raw_request = try request.build(host);
        defer self.allocator.free(raw_request);

        _ = try socket.send(raw_request);

        var buffer = try self.allocator.alloc(u8, 4096);
        const bytes_read = try socket.recv(buffer);

        return buffer[0..bytes_read];
    }

    /// Set default timeout
    pub fn setTimeout(self: *Self, timeout_ms: u64) void {
        self.default_timeout_ms = timeout_ms;
    }

    /// Deinitialize client
    pub fn deinit(self: *Self) void {
        _ = self;
    }
};

// ===== Tests =====

test "Socket initialization" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var socket = try Socket.initTcp(arena.allocator());
    defer socket.deinit();

    try std.testing.expect(!socket.isConnected());
    try std.testing.expectEqual(@as(u64, 5000), socket.timeout_ms);
}

test "Socket timeout setting" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var socket = try Socket.initTcp(arena.allocator());
    defer socket.deinit();

    socket.setTimeout(10000);
    try std.testing.expectEqual(@as(u64, 10000), socket.timeout_ms);
}

test "HttpRequest GET" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var request = try HttpRequest.get(arena.allocator(), "/api/users");
    defer request.deinit();

    try std.testing.expectEqualSlices(u8, "GET", request.method);
    try std.testing.expectEqualSlices(u8, "/api/users", request.uri);
    try std.testing.expect(request.body == null);
}

test "HttpRequest POST" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const body = "test data";
    var request = try HttpRequest.post(arena.allocator(), "/api/users", body);
    defer request.deinit();

    try std.testing.expectEqualSlices(u8, "POST", request.method);
    try std.testing.expectEqualSlices(u8, "/api/users", request.uri);
    try std.testing.expect(request.body != null);
}

test "HttpRequest PUT" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const body = "updated data";
    var request = try HttpRequest.put(arena.allocator(), "/api/users/1", body);
    defer request.deinit();

    try std.testing.expectEqualSlices(u8, "PUT", request.method);
    try std.testing.expectEqualSlices(u8, "/api/users/1", request.uri);
}

test "HttpRequest DELETE" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var request = try HttpRequest.delete(arena.allocator(), "/api/users/1");
    defer request.deinit();

    try std.testing.expectEqualSlices(u8, "DELETE", request.method);
    try std.testing.expect(request.body == null);
}

test "HttpRequest set headers" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var request = try HttpRequest.get(arena.allocator(), "/api");
    defer request.deinit();

    try request.setHeader("Content-Type", "application/json");
    try request.setHeader("Authorization", "Bearer token");

    try std.testing.expect(request.headers.contains("Content-Type"));
    try std.testing.expect(request.headers.contains("Authorization"));
}

test "HttpRequest build GET" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var request = try HttpRequest.get(arena.allocator(), "/api/test");
    defer request.deinit();

    try request.setHeader("User-Agent", "ZBoost");

    const raw = try request.build("example.com");
    defer arena.allocator().free(raw);

    try std.testing.expect(std.mem.containsAtLeast(u8, raw, 1, "GET /api/test HTTP/1.1"));
    try std.testing.expect(std.mem.containsAtLeast(u8, raw, 1, "Host: example.com"));
    try std.testing.expect(std.mem.containsAtLeast(u8, raw, 1, "User-Agent: ZBoost"));
}

test "HttpRequest build POST" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const body = "test body content";
    var request = try HttpRequest.post(arena.allocator(), "/api/data", body);
    defer request.deinit();

    const raw = try request.build("api.example.com");
    defer arena.allocator().free(raw);

    try std.testing.expect(std.mem.containsAtLeast(u8, raw, 1, "POST /api/data HTTP/1.1"));
    try std.testing.expect(std.mem.containsAtLeast(u8, raw, 1, "Host: api.example.com"));
    try std.testing.expect(std.mem.containsAtLeast(u8, raw, 1, body));
}

test "HttpResponse parse status code" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const raw = "HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\n\r\nHello World";
    var response = try HttpResponse.parse(arena.allocator(), raw);
    defer response.deinit();

    try std.testing.expectEqual(@as(u16, 200), response.status_code);
}

test "HttpResponse parse headers" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const raw = "HTTP/1.1 404 Not Found\r\nContent-Type: application/json\r\nServer: TestServer\r\n\r\n";
    var response = try HttpResponse.parse(arena.allocator(), raw);
    defer response.deinit();

    try std.testing.expectEqual(@as(u16, 404), response.status_code);
    try std.testing.expect(response.getHeader("Content-Type") != null);
    try std.testing.expect(response.getHeader("Server") != null);
}

test "HttpResponse parse 500 status" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const raw = "HTTP/1.1 500 Internal Server Error\r\n\r\nError occurred";
    var response = try HttpResponse.parse(arena.allocator(), raw);
    defer response.deinit();

    try std.testing.expectEqual(@as(u16, 500), response.status_code);
}

test "Connection initialization" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var conn = try Connection.init(arena.allocator(), "localhost", 8080);
    defer conn.deinit();

    try std.testing.expectEqual(@as(u16, 8080), conn.port);
    try std.testing.expectEqual(@as(u32, 3), conn.max_retries);
}

test "Connection retry parameters" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var conn = try Connection.init(arena.allocator(), "127.0.0.1", 9000);
    defer conn.deinit();

    conn.setRetryParams(5, 500);

    try std.testing.expectEqual(@as(u32, 5), conn.max_retries);
    try std.testing.expectEqual(@as(u64, 500), conn.retry_delay_ms);
}

test "HttpClient initialization" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var client = HttpClient.init(arena.allocator());
    client.setTimeout(10000);

    try std.testing.expectEqual(@as(u64, 10000), client.default_timeout_ms);
}

test "HttpClient timeout configuration" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var client = HttpClient.init(arena.allocator());

    try std.testing.expectEqual(@as(u64, 5000), client.default_timeout_ms);

    client.setTimeout(15000);

    try std.testing.expectEqual(@as(u64, 15000), client.default_timeout_ms);
}
