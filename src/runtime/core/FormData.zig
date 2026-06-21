//! The FormData interface provides a way to construct a set of key/value pairs
//! representing form fields and their values, which can be sent using fetch()
//! or XMLHttpRequest.send().
//!
//! This implementation handles application/x-www-form-urlencoded data only.
//! For multipart/form-data with file uploads, use MultiFormData instead.
//!
//! Reads delegate to the unified `Http` backend (see `core/Http.zig`).
//!
//! https://developer.mozilla.org/en-US/docs/Web/API/FormData

const std = @import("std");
const Http = @import("Http.zig");

pub const FormData = @This();

// --- Types --- //

/// Entry type for iteration
pub const Entry = struct {
    key: []const u8,
    value: []const u8,
};

// --- Instance Fields --- //

/// Internal backend transport carrier. All reads delegate here.
_internal: Http.Facade = .{},

// --- Instance Methods --- //
// https://developer.mozilla.org/en-US/docs/Web/API/FormData#instance_methods

/// Returns the first value associated with a given key from within a FormData object.
///
/// https://developer.mozilla.org/en-US/docs/Web/API/FormData/get
///
/// **Zig Note:** Returns `?[]const u8` instead of `FormDataEntryValue | null`.
pub fn get(self: *const FormData, name: []const u8) ?[]const u8 {
    return self._internal.http.reqFormGet(name);
}

/// Returns whether a FormData object contains a certain key.
///
/// https://developer.mozilla.org/en-US/docs/Web/API/FormData/has
pub fn has(self: *const FormData, name: []const u8) bool {
    return self._internal.http.reqFormHas(name);
}

// --- Iterator --- //

/// Iterator for FormData entries backed by parallel key/value arrays.
pub const Iterator = struct {
    pos: usize = 0,
    keys: []const []const u8,
    values: []const []const u8,

    /// Returns the next entry, or null if iteration is complete.
    pub fn next(self: *Iterator) ?Entry {
        if (self.pos >= self.keys.len) {
            return null;
        }
        const entry = Entry{
            .key = self.keys[self.pos],
            .value = self.values[self.pos],
        };
        self.pos += 1;
        return entry;
    }

    /// Resets the iterator to the beginning.
    pub fn reset(self: *Iterator) void {
        self.pos = 0;
    }
};
