//! The MultiFormData interface provides a way to construct a set of key/value pairs
//! representing multipart form fields and their values, including file uploads.
//!
//! This implementation handles multipart/form-data with file upload support.
//! For simple key-value form data (application/x-www-form-urlencoded), use FormData instead.
//!
//! https://developer.mozilla.org/en-US/docs/Web/API/FormData

const std = @import("std");
const Http = @import("Http.zig");

pub const MultiFormData = @This();

// --- Types --- //

/// A single form data entry value, which can be a string or a file.
///
/// **Zig Note:** In the web standard, values can be `string | Blob`.
/// This implementation uses a struct that can represent both.
pub const Value = struct {
    /// The value content as bytes
    data: []const u8,
    /// Optional filename for file uploads (null for regular fields)
    filename: ?[]const u8 = null,

    /// Returns true if this entry represents a file upload
    pub fn isFile(self: Value) bool {
        return self.filename != null;
    }
};

/// Entry type for iteration
pub const Entry = struct {
    key: []const u8,
    value: Value,
};

// --- Instance Fields --- //

/// Internal backend transport carrier. All reads delegate here.
_internal: Http.Facade = .{},

// --- Instance Methods --- //
// https://developer.mozilla.org/en-US/docs/Web/API/FormData#instance_methods

/// Returns the first value associated with a given key from within a MultiFormData object.
///
/// https://developer.mozilla.org/en-US/docs/Web/API/FormData/get
///
/// **Zig Note:** Returns `?Value` instead of `FormDataEntryValue | null`.
pub fn get(self: *const MultiFormData, name: []const u8) ?Value {
    return self._internal.http.reqMultiGet(name);
}

/// Returns the first string value associated with a given key.
///
/// **Zig Note:** Convenience method that returns just the data portion.
pub fn getValue(self: *const MultiFormData, name: []const u8) ?[]const u8 {
    if (self.get(name)) |v| {
        return v.data;
    }
    return null;
}

/// Returns an array of all the values associated with a given key from within a MultiFormData.
///
/// https://developer.mozilla.org/en-US/docs/Web/API/FormData/getAll
///
/// **Zig Note:** Returns `?[]const Value` instead of `FormDataEntryValue[]`.
/// Requires an allocator for the returned slice.
pub fn getAll(self: *const MultiFormData, name: []const u8, allocator: std.mem.Allocator) ?[]const Value {
    return self._internal.http.reqMultiGetAll(name, allocator);
}

/// Returns whether a MultiFormData object contains a certain key.
///
/// https://developer.mozilla.org/en-US/docs/Web/API/FormData/has
pub fn has(self: *const MultiFormData, name: []const u8) bool {
    return self._internal.http.reqMultiHas(name);
}

// --- Iterator --- //

/// Iterator for MultiFormData entries backed by parallel key/value arrays.
pub const Iterator = struct {
    pos: usize = 0,
    keys: []const []const u8,
    values: []const Value,

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
