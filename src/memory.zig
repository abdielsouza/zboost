const std = @import("std");
const Allocator = std.mem.Allocator;

/// Memory utilities and smart pointers for Zig
pub const Memory = struct {
    /// Safe allocation wrapper that panics on failure
    pub fn allocate(allocator: Allocator, comptime T: type) Allocator.Error!*T {
        return try allocator.create(T);
    }

    /// Safe deallocation wrapper
    pub fn deallocate(allocator: Allocator, ptr: anytype) void {
        allocator.destroy(ptr);
    }

    /// Allocate an array of type T
    pub fn allocateArray(allocator: Allocator, comptime T: type, count: usize) Allocator.Error![]T {
        return try allocator.alloc(T, count);
    }

    /// Deallocate an array
    pub fn deallocateArray(allocator: Allocator, slice: anytype) void {
        allocator.free(slice);
    }

    /// Create a zero-initialized value
    pub fn allocateZero(allocator: Allocator, comptime T: type) Allocator.Error!*T {
        const ptr = try allocator.create(T);
        ptr.* = std.mem.zeroes(T);
        return ptr;
    }
};

/// UniquePtr - exclusive ownership smart pointer
/// Only one owner at a time, transfers ownership on move
pub fn UniquePtr(comptime T: type) type {
    return struct {
        ptr: ?*T,
        allocator: Allocator,

        const Self = @This();

        /// Initialize a UniquePtr with a value
        pub fn init(allocator: Allocator, value: T) Allocator.Error!Self {
            const ptr = try allocator.create(T);
            ptr.* = value;
            return Self{
                .ptr = ptr,
                .allocator = allocator,
            };
        }

        /// Initialize with a raw pointer
        pub fn initRaw(allocator: Allocator, ptr: *T) Self {
            return Self{
                .ptr = ptr,
                .allocator = allocator,
            };
        }

        /// Get a reference to the value
        pub fn get(self: *Self) ?*T {
            return self.ptr;
        }

        /// Dereference the pointer
        pub fn deref(self: *Self) ?T {
            if (self.ptr) |p| {
                return p.*;
            }
            return null;
        }

        /// Release ownership and return the raw pointer
        pub fn release(self: *Self) ?*T {
            defer self.ptr = null;
            return self.ptr;
        }

        /// Swap with another UniquePtr
        pub fn swap(self: *Self, other: *Self) void {
            std.mem.swap(Self, self, other);
        }

        /// Check if pointer is non-null
        pub fn isValid(self: *Self) bool {
            return self.ptr != null;
        }

        /// Reset the pointer and deallocate
        pub fn reset(self: *Self) void {
            if (self.ptr) |p| {
                self.allocator.destroy(p);
            }
            self.ptr = null;
        }

        /// Deinitialize and deallocate
        pub fn deinit(self: *Self) void {
            self.reset();
        }
    };
}

/// Reference counter for SharedPtr
const RefCounter = struct {
    count: usize,
    weak_count: usize,

    fn init() RefCounter {
        return RefCounter{
            .count = 1,
            .weak_count = 0,
        };
    }
};

/// SharedPtr - shared ownership smart pointer
/// Multiple owners, deallocated when last owner is destroyed
pub fn SharedPtr(comptime T: type) type {
    return struct {
        ptr: ?*T,
        ref_counter: ?*RefCounter,
        allocator: Allocator,

        const Self = @This();

        /// Initialize a SharedPtr with a value
        pub fn init(allocator: Allocator, value: T) Allocator.Error!Self {
            const ptr = try allocator.create(T);
            const ref_counter = try allocator.create(RefCounter);
            ref_counter.* = RefCounter.init();
            ptr.* = value;
            return Self{
                .ptr = ptr,
                .ref_counter = ref_counter,
                .allocator = allocator,
            };
        }

        /// Clone the SharedPtr (increment reference count)
        pub fn clone(self: *const Self) Allocator.Error!Self {
            if (self.ref_counter) |rc| {
                rc.count += 1;
            }
            return Self{
                .ptr = self.ptr,
                .ref_counter = self.ref_counter,
                .allocator = self.allocator,
            };
        }

        /// Get a reference to the value
        pub fn get(self: *Self) ?*T {
            return self.ptr;
        }

        /// Dereference the pointer
        pub fn deref(self: *Self) ?T {
            if (self.ptr) |p| {
                return p.*;
            }
            return null;
        }

        /// Get reference count
        pub fn refCount(self: *Self) usize {
            if (self.ref_counter) |rc| {
                return rc.count;
            }
            return 0;
        }

        /// Check if this is the only owner
        pub fn isUnique(self: *Self) bool {
            return self.refCount() == 1;
        }

        /// Check if pointer is valid
        pub fn isValid(self: *Self) bool {
            return self.ptr != null;
        }

        /// Deinitialize and deallocate if this was the last owner
        pub fn deinit(self: *Self) void {
            if (self.ref_counter) |rc| {
                rc.count -= 1;
                if (rc.count == 0 and rc.weak_count == 0) {
                    if (self.ptr) |p| {
                        self.allocator.destroy(p);
                    }
                    self.allocator.destroy(rc);
                }
            }
        }
    };
}

/// WeakPtr - non-owning reference to SharedPtr
/// Does not prevent deallocation
pub fn WeakPtr(comptime T: type) type {
    return struct {
        ptr: ?*T,
        ref_counter: ?*RefCounter,
        allocator: Allocator,

        const Self = @This();

        /// Create a WeakPtr from a SharedPtr
        pub fn fromShared(shared: *SharedPtr(T)) Allocator.Error!Self {
            if (shared.ref_counter) |rc| {
                rc.weak_count += 1;
            }
            return Self{
                .ptr = shared.ptr,
                .ref_counter = shared.ref_counter,
                .allocator = shared.allocator,
            };
        }

        /// Try to upgrade to a SharedPtr
        pub fn upgrade(self: *Self) ?SharedPtr(T) {
            if (self.ptr == null or self.ref_counter == null) {
                return null;
            }
            self.ref_counter.?.count += 1;
            return SharedPtr(T){
                .ptr = self.ptr,
                .ref_counter = self.ref_counter,
                .allocator = self.allocator,
            };
        }

        /// Check if the referenced object is still alive
        pub fn isAlive(self: *Self) bool {
            if (self.ref_counter) |rc| {
                return rc.count > 0;
            }
            return false;
        }

        /// Deinitialize WeakPtr
        pub fn deinit(self: *Self) void {
            if (self.ref_counter) |rc| {
                rc.weak_count -= 1;
            }
            self.ptr = null;
            self.ref_counter = null;
        }
    };
}

/// Arena allocator wrapper for batch allocations
pub const Arena = struct {
    child_allocator: Allocator,
    state: std.heap.ArenaAllocator,

    const Self = @This();

    /// Initialize an arena allocator
    pub fn init(child_allocator: Allocator) Self {
        return Self{
            .child_allocator = child_allocator,
            .state = std.heap.ArenaAllocator.init(child_allocator),
        };
    }

    /// Get the allocator interface
    pub fn allocator(self: *Self) Allocator {
        return self.state.allocator();
    }

    /// Free all allocations at once
    pub fn deinit(self: *Self) void {
        self.state.deinit();
    }
};

// Tests
const testing = std.testing;

test "Memory.allocate and deallocate" {
    const allocator = testing.allocator;
    const ptr = try Memory.allocate(allocator, i32);
    ptr.* = 42;
    try testing.expect(ptr.* == 42);
    Memory.deallocate(allocator, ptr);
}

test "Memory.allocateArray and deallocateArray" {
    const allocator = testing.allocator;
    const arr = try Memory.allocateArray(allocator, i32, 10);
    arr[0] = 1;
    arr[9] = 9;
    try testing.expect(arr[0] == 1 and arr[9] == 9);
    Memory.deallocateArray(allocator, arr);
}

test "Memory.allocateZero" {
    const allocator = testing.allocator;
    const StructType = struct { a: i32, b: i32 };
    const ptr = try Memory.allocateZero(allocator, StructType);
    try testing.expect(ptr.a == 0 and ptr.b == 0);
    Memory.deallocate(allocator, ptr);
}

test "UniquePtr initialization and access" {
    const allocator = testing.allocator;
    var ptr = try UniquePtr(i32).init(allocator, 42);
    defer ptr.deinit();

    try testing.expect(ptr.isValid());
    try testing.expect(ptr.deref().? == 42);
}

test "UniquePtr release" {
    const allocator = testing.allocator;
    var ptr1 = try UniquePtr(i32).init(allocator, 100);
    const raw = ptr1.release();
    try testing.expect(raw != null);
    try testing.expect(raw.?.* == @as(i32, 100));
    try testing.expect(!ptr1.isValid());
    allocator.destroy(raw.?);
}

test "SharedPtr basic usage" {
    const allocator = testing.allocator;
    var ptr1 = try SharedPtr(i32).init(allocator, 42);
    defer ptr1.deinit();

    try testing.expect(ptr1.isValid());
    try testing.expect(ptr1.refCount() == 1);
    try testing.expect(ptr1.deref().? == 42);
}

test "SharedPtr cloning" {
    const allocator = testing.allocator;
    var ptr1 = try SharedPtr(i32).init(allocator, 42);
    defer ptr1.deinit();

    var ptr2 = try ptr1.clone();
    defer ptr2.deinit();

    try testing.expect(ptr1.refCount() == 2);
    try testing.expect(!ptr1.isUnique());
}

test "SharedPtr deallocation" {
    const allocator = testing.allocator;
    var ptr1 = try SharedPtr(i32).init(allocator, 42);
    var ptr2 = try ptr1.clone();

    ptr1.deinit();
    try testing.expect(ptr2.refCount() == 1);

    ptr2.deinit();
}

test "WeakPtr from SharedPtr" {
    const allocator = testing.allocator;
    var shared = try SharedPtr(i32).init(allocator, 42);
    defer shared.deinit();

    var weak = try WeakPtr(i32).fromShared(&shared);
    defer weak.deinit();

    try testing.expect(weak.isAlive());
}

test "WeakPtr upgrade" {
    const allocator = testing.allocator;
    var shared = try SharedPtr(i32).init(allocator, 42);
    defer shared.deinit();

    var weak = try WeakPtr(i32).fromShared(&shared);
    defer weak.deinit();

    if (weak.upgrade()) |upgraded| {
        var upgraded_mut = upgraded;
        defer upgraded_mut.deinit();
        try testing.expect(upgraded_mut.deref().? == 42);
    }
}

test "Arena allocator" {
    const allocator = testing.allocator;
    var arena = Arena.init(allocator);
    defer arena.deinit();

    const arena_allocator = arena.allocator();
    const arr = try arena_allocator.alloc(i32, 10);
    arr[0] = 1;
    try testing.expect(arr[0] == 1);
}
