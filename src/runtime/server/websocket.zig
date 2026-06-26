const std = @import("std");
const WebSocket = @import("../core/WebSocket.zig");
const websocket = @import("httpz").websocket;

const CloseOptions = WebSocket.CloseOptions;
const WebSocketError = WebSocket.WebSocketError;
const Allocator = std.mem.Allocator;

/// Backend context stored in WebSocket.backend_ctx
const BackendContext = struct {
    client: websocket.Client,
    read_thread: ?std.Thread,
    ws_ptr: *WebSocket,

    fn init(allocator: Allocator, host: []const u8, port: u16, tls: bool) !*BackendContext {
        const ctx = try allocator.create(BackendContext);
        errdefer allocator.destroy(ctx);

        ctx.* = .{
            .client = try websocket.Client.init(allocator, .{
                .host = host,
                .port = port,
                .tls = tls,
            }),
            .read_thread = null,
            .ws_ptr = undefined,
        };

        return ctx;
    }

    fn deinit(self: *BackendContext, allocator: Allocator) void {
        // Wait for read thread to finish
        if (self.read_thread) |thread| {
            thread.join();
        }
        self.client.deinit();
        allocator.destroy(self);
    }
};

/// Handler for the websocket read loop
const ReadHandler = struct {
    ws: *WebSocket,

    pub fn serverMessage(self: *ReadHandler, data: []const u8, msg_type: websocket.MessageType) !void {
        const ws = self.ws;
        if (ws.onmessage) |handler| {
            if (msg_type == .binary) {
                handler(ws, .{ .data = .{ .binary = data } });
            } else {
                handler(ws, .{ .data = .{ .text = data } });
            }
        }
    }

    pub fn serverClose(self: *ReadHandler, data: []const u8) !void {
        const ws = self.ws;
        ws.ready_state = .closed;

        // Parse close code from data if available
        const code: u16 = if (data.len >= 2)
            std.mem.readInt(u16, data[0..2], .big)
        else
            1000;

        const reason = if (data.len > 2) data[2..] else "";

        if (ws.onclose) |handler| {
            handler(ws, .{
                .code = code,
                .reason = reason,
                .was_clean = true,
            });
        }
    }

    pub fn close(self: *ReadHandler) void {
        const ws = self.ws;
        if (ws.ready_state != .closed) {
            ws.ready_state = .closed;
        }
    }
};

/// Parse a WebSocket URL into components
fn parseWsUrl(url: []const u8) !struct { host: []const u8, port: u16, path: []const u8, tls: bool } {
    var tls = false;
    var rest: []const u8 = url;

    if (std.mem.startsWith(u8, url, "wss://")) {
        tls = true;
        rest = url[6..];
    } else if (std.mem.startsWith(u8, url, "ws://")) {
        rest = url[5..];
    } else {
        return error.InvalidUrl;
    }

    // Find path separator
    const path_start = std.mem.indexOf(u8, rest, "/") orelse rest.len;
    const host_port = rest[0..path_start];
    const path = if (path_start < rest.len) rest[path_start..] else "/";

    // Parse host:port
    if (std.mem.indexOf(u8, host_port, ":")) |colon| {
        const host = host_port[0..colon];
        const port = std.fmt.parseInt(u16, host_port[colon + 1 ..], 10) catch return error.InvalidUrl;
        return .{ .host = host, .port = port, .path = path, .tls = tls };
    } else {
        const default_port: u16 = if (tls) 443 else 80;
        return .{ .host = host_port, .port = default_port, .path = path, .tls = tls };
    }
}

/// Establish a WebSocket connection
pub fn connect(ws: *WebSocket) WebSocketError!void {
    const allocator = ws._allocator;

    // Parse URL
    const url_parts = parseWsUrl(ws.url) catch return error.InvalidUrl;

    // Create backend context
    const ctx = BackendContext.init(allocator, url_parts.host, url_parts.port, url_parts.tls) catch
        return error.ConnectionFailed;
    errdefer ctx.deinit(allocator);

    ctx.ws_ptr = ws;
    ws._backend_ctx = ctx;

    // Perform handshake
    ctx.client.handshake(url_parts.path, .{}) catch {
        return error.ConnectionFailed;
    };

    ws.ready_state = .open;

    // Notify open handler
    ws._handleOpen();

    // Start read loop in background thread
    ctx.read_thread = std.Thread.spawn(.{}, struct {
        fn run(context: *BackendContext) void {
            var handler = ReadHandler{ .ws = context.ws_ptr };
            context.client.readLoop(&handler) catch |err| {
                const w = context.ws_ptr;
                if (w.onerror) |error_handler| {
                    error_handler(w, .{ .message = @errorName(err) });
                }
            };
        }
    }.run, .{ctx}) catch {
        return error.ConnectionFailed;
    };
}

/// Send text data
pub fn send(ws: *WebSocket, data: []const u8) WebSocketError!void {
    const ctx: *BackendContext = @ptrCast(@alignCast(ws._backend_ctx orelse return error.NotConnected));

    // writeText takes a mutable slice, so we need to copy
    const buf = ws._allocator.alloc(u8, data.len) catch return error.SendFailed;
    defer ws._allocator.free(buf);
    @memcpy(buf, data);

    ctx.client.writeText(buf) catch return error.SendFailed;
}

/// Send binary data
pub fn sendBinary(ws: *WebSocket, data: []const u8) WebSocketError!void {
    const ctx: *BackendContext = @ptrCast(@alignCast(ws._backend_ctx orelse return error.NotConnected));

    // writeBin takes a mutable slice, so we need to copy
    const buf = ws._allocator.alloc(u8, data.len) catch return error.SendFailed;
    defer ws._allocator.free(buf);
    @memcpy(buf, data);

    ctx.client.writeBin(buf) catch return error.SendFailed;
}

/// Close the connection
pub fn close(ws: *WebSocket, options: CloseOptions) void {
    const ctx: *BackendContext = @ptrCast(@alignCast(ws._backend_ctx orelse return));

    ws.ready_state = .closing;
    const code = options.code orelse 1000;
    const reason = options.reason orelse "";

    ctx.client.close(.{ .code = code }) catch {};
    ws.ready_state = .closed;

    if (ws.onclose) |handler| {
        handler(ws, .{
            .code = code,
            .reason = reason,
            .was_clean = true,
        });
    }
}

/// Clean up resources
pub fn deinit(ws: *WebSocket) void {
    if (ws._backend_ctx) |ptr| {
        const ctx: *BackendContext = @ptrCast(@alignCast(ptr));
        ctx.deinit(ws._allocator);
        ws._backend_ctx = null;
    }
}
