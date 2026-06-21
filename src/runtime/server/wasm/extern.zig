pub extern "__zx_ws" fn ws_upgrade() void;
pub extern "__zx_ws" fn ws_write(ptr: [*]const u8, len: usize) void;
pub extern "__zx_ws" fn ws_close(code: u16, reason_ptr: [*]const u8, reason_len: usize) void;
pub extern "__zx_ws" fn ws_recv(buf_ptr: [*]u8, buf_max: usize) i32;
pub extern "__zx_ws" fn ws_subscribe(topic_ptr: [*]const u8, topic_len: usize) void;
pub extern "__zx_ws" fn ws_unsubscribe(topic_ptr: [*]const u8, topic_len: usize) void;
pub extern "__zx_ws" fn ws_publish(topic_ptr: [*]const u8, topic_len: usize, data_ptr: [*]const u8, data_len: usize) usize;
pub extern "__zx_ws" fn ws_is_subscribed(topic_ptr: [*]const u8, topic_len: usize) i32;

/// level: 0=error, 1=warn, 2=info, 3=debug
pub extern "__zx" fn _log(level: u8, ptr: [*]const u8, len: usize) void;
