const std = @import("std");

/// A simple fixed-size circular queue implementation.
/// This queue does not support dynamic resizing and will return an error if you try to enqueue when it's full or dequeue when it's empty.
pub fn BasicQueue(comptime T: type, comptime capacity: usize) type {
    return struct {
        data: [capacity]T = undefined,
        front: usize = 0,
        back: usize = 0,
        count: usize = 0,

        const Self = @This();
        pub const Error = error{ QueueIsFull, QueueIsEmpty };

        pub fn enqueue(self: *Self, value: T) Error!void {
            if (self.count >= capacity) {
                return Error.QueueIsFull;
            }

            self.data[self.back] = value;
            self.back = (self.back + 1) % capacity;
            self.count += 1;
        }

        pub fn dequeue(self: *Self) Error!T {
            if (self.count == 0) {
                return Error.QueueIsEmpty;
            }

            const value = self.data[self.front];
            self.front = (self.front + 1) % capacity;
            self.count -= 1;

            return value;
        }

        pub fn peek(self: *Self) Error!T {
            if (self.count == 0) {
                return Error.QueueIsEmpty;
            }
            return self.data[self.front];
        }

        pub fn isEmpty(self: *Self) bool {
            return self.count == 0;
        }

        pub fn isFull(self: *Self) bool {
            return self.count >= capacity;
        }

        pub fn len(self: *Self) usize {
            return self.count;
        }

        pub fn clear(self: *Self) void {
            self.front = 0;
            self.back = 0;
            self.count = 0;
        }

        pub fn reset(self: *Self) void {
            self.clear();
        }
    };
}

/// A thread-safe concurrent queue implementation using a mutex and condition variables.
/// This queue supports blocking enqueue and dequeue operations, as well as non-blocking tryEnqueue and tryDequeue operations.
///
/// **The queue uses an ArrayList internally to store items**, and it has a configurable maximum capacity to prevent unbounded growth.
///
/// **Note**: This implementation is not optimized for high performance and is intended for demonstration purposes.
/// In a production environment, you may want to consider more efficient concurrent data structures or lock-free algorithms.
pub fn ConcurrentQueue(comptime T: type) type {
    return struct {
        allocator: std.mem.Allocator,
        mutex: std.Thread.Mutex = .{},
        not_empty: std.Thread.Condition = .{},
        not_full: std.Thread.Condition = .{},
        items: std.ArrayList(T),
        max_capacity: usize = 1024,

        const Self = @This();
        pub const Error = error{ QueueIsFull, QueueIsEmpty, OutOfMemory };

        pub fn init(allocator: std.mem.Allocator, max_capacity: usize) Error!Self {
            const items = try std.ArrayList(T).initCapacity(allocator, 16);
            return Self{
                .allocator = allocator,
                .items = items,
                .max_capacity = max_capacity,
            };
        }

        pub fn deinit(self: *Self) void {
            self.items.deinit(self.allocator);
        }

        pub fn enqueue(self: *Self, value: T) Error!void {
            self.mutex.lock();
            defer self.mutex.unlock();

            while (self.items.items.len >= self.max_capacity) {
                self.not_full.wait(&self.mutex);
            }

            self.items.append(self.allocator, value) catch return Error.OutOfMemory;
            self.not_empty.signal();
        }

        pub fn dequeue(self: *Self) Error!T {
            self.mutex.lock();
            defer self.mutex.unlock();

            while (self.items.items.len == 0) {
                self.not_empty.wait(&self.mutex);
            }

            const value = self.items.items[0];
            _ = self.items.orderedRemove(0);
            self.not_full.signal();

            return value;
        }

        pub fn tryEnqueue(self: *Self, value: T) Error!void {
            self.mutex.lock();
            defer self.mutex.unlock();

            if (self.items.items.len >= self.max_capacity) {
                return Error.QueueIsFull;
            }

            self.items.append(self.allocator, value) catch return Error.OutOfMemory;
            self.not_empty.signal();
        }

        pub fn tryDequeue(self: *Self) Error!T {
            self.mutex.lock();
            defer self.mutex.unlock();

            if (self.items.items.len == 0) {
                return Error.QueueIsEmpty;
            }

            const value = self.items.items[0];
            _ = self.items.orderedRemove(0);
            self.not_full.signal();

            return value;
        }

        pub fn peek(self: *Self) Error!T {
            self.mutex.lock();
            defer self.mutex.unlock();

            if (self.items.items.len == 0) {
                return Error.QueueIsEmpty;
            }

            return self.items.items[0];
        }

        pub fn len(self: *Self) usize {
            self.mutex.lock();
            defer self.mutex.unlock();

            return self.items.items.len;
        }

        pub fn isEmpty(self: *Self) bool {
            self.mutex.lock();
            defer self.mutex.unlock();

            return self.items.items.len == 0;
        }

        pub fn isFull(self: *Self) bool {
            self.mutex.lock();
            defer self.mutex.unlock();

            return self.items.items.len >= self.max_capacity;
        }

        pub fn clear(self: *Self) void {
            self.mutex.lock();
            defer self.mutex.unlock();

            self.items.clearAndFree(self.allocator);
            self.not_full.broadcast();
        }
    };
}

/// A simple binary search tree (BST) implementation.
/// This is a basic implementation and does not include balancing, so it may degrade to a linked list in the worst case.
/// For a production-quality B-tree, you would need to implement node splitting and merging, as well as support for multiple keys per node.
///
/// **Note**: This implementation is for demonstration purposes and is not optimized for performance or memory usage.
pub fn BTree(comptime T: type) type {
    return struct {
        // B-tree specific methods would go here (insert, delete, search, etc.)
        const Node = struct {
            value: T,
            left: ?*Node = null,
            right: ?*Node = null,
        };

        allocator: std.mem.Allocator,
        root: ?*Node = null,

        const Self = @This();

        pub fn init(allocator: std.mem.Allocator) Self {
            return Self{
                .allocator = allocator,
                .root = null,
            };
        }

        pub fn deinit(self: *Self) void {
            self.deinitNode(self.root);
        }

        fn deinitNode(self: *Self, node: ?*Node) void {
            if (node) |n| {
                self.deinitNode(n.left);
                self.deinitNode(n.right);
                self.allocator.destroy(n);
            }
        }

        pub fn insert(self: *Self, value: T) !void {
            const new_node = try self.allocator.create(Node);
            new_node.* = Node{ .value = value };

            if (self.root == null) {
                self.root = new_node;
                return;
            }

            var current = self.root;

            while (true) {
                if (value < current.?.value) {
                    if (current.?.left == null) {
                        current.?.left = new_node;
                        return;
                    }

                    current = current.?.left;
                } else if (value > current.?.value) {
                    if (current.?.right == null) {
                        current.?.right = new_node;
                        return;
                    }

                    current = current.?.right;
                } else {
                    // duplicate, ignore
                    self.allocator.destroy(new_node);
                    return;
                }
            }
        }

        pub fn search(self: *Self, value: T) bool {
            var current = self.root;

            while (current) |node| {
                if (value == node.value) {
                    return true;
                } else if (value < node.value) {
                    current = node.left;
                } else {
                    current = node.right;
                }
            }

            return false;
        }

        pub fn delete(self: *Self, value: T) void {
            self.root = self.deleteNode(self.root, value);
        }

        fn deleteNode(self: *Self, node: ?*Node, value: T) ?*Node {
            if (node == null) return null;
            var n = node.?;

            if (value < n.value) {
                n.left = self.deleteNode(n.left, value);
            } else if (value > n.value) {
                n.right = self.deleteNode(n.right, value);
            } else {
                if (n.left == null) {
                    const temp = n.right;
                    self.allocator.destroy(n);

                    return temp;
                } else if (n.right == null) {
                    const temp = n.left;
                    self.allocator.destroy(n);

                    return temp;
                }

                // node with two children
                const temp = self.minValueNode(n.right);
                n.value = temp.?.value;
                n.right = self.deleteNode(n.right, temp.?.value);
            }

            return node;
        }

        fn minValueNode(_: *Self, node: ?*Node) ?*Node {
            var current = node;

            while (current != null and current.?.left != null) {
                current = current.?.left;
            }

            return current;
        }

        pub fn inorder(self: *Self, context: anytype, callback: fn (@TypeOf(context), *const T) void) void {
            self.inorderTraverse(self.root, context, callback);
        }

        fn inorderTraverse(self: *Self, node: ?*Node, context: anytype, callback: fn (@TypeOf(context), *const T) void) void {
            if (node) |n| {
                self.inorderTraverse(n.left, context, callback);
                callback(context, &n.value);
                self.inorderTraverse(n.right, context, callback);
            }
        }
    };
}

test "BasicQueue basic operations" {
    var queue = BasicQueue(i32, 5){};

    try queue.enqueue(10);
    try queue.enqueue(20);
    try queue.enqueue(30);

    try std.testing.expect(queue.len() == 3);
    try std.testing.expect(!queue.isEmpty());
    try std.testing.expect(!queue.isFull());

    const val = try queue.peek();
    try std.testing.expectEqual(val, 10);
    try std.testing.expectEqual(queue.len(), 3);

    const dequeued = try queue.dequeue();
    try std.testing.expectEqual(dequeued, 10);
    try std.testing.expectEqual(queue.len(), 2);
}

test "BasicQueue fill to capacity" {
    var queue = BasicQueue(i32, 3){};

    try queue.enqueue(1);
    try queue.enqueue(2);
    try queue.enqueue(3);

    try std.testing.expect(queue.isFull());
    try std.testing.expectError(BasicQueue(i32, 3).Error.QueueIsFull, queue.enqueue(4));
}

test "BasicQueue circular behavior" {
    var queue = BasicQueue(i32, 3){};

    try queue.enqueue(1);
    try queue.enqueue(2);
    try queue.enqueue(3);

    _ = try queue.dequeue();
    _ = try queue.dequeue();

    try queue.enqueue(4);
    try queue.enqueue(5);

    try std.testing.expectEqual(try queue.dequeue(), 3);
    try std.testing.expectEqual(try queue.dequeue(), 4);
    try std.testing.expectEqual(try queue.dequeue(), 5);
}

test "BasicQueue clear" {
    var queue = BasicQueue(i32, 5){};

    try queue.enqueue(1);
    try queue.enqueue(2);
    queue.clear();

    try std.testing.expect(queue.isEmpty());
    try std.testing.expectEqual(queue.len(), 0);
}

test "ConcurrentQueue basic operations" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var queue = try ConcurrentQueue(i32).init(allocator, 10);
    defer queue.deinit();

    try queue.enqueue(42);
    try queue.enqueue(84);

    try std.testing.expectEqual(queue.len(), 2);
    try std.testing.expect(!queue.isEmpty());

    const val1 = try queue.dequeue();
    try std.testing.expectEqual(val1, 42);

    const val2 = try queue.dequeue();
    try std.testing.expectEqual(val2, 84);

    try std.testing.expect(queue.isEmpty());
}

test "ConcurrentQueue tryEnqueue and tryDequeue" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var queue = try ConcurrentQueue(i32).init(allocator, 2);
    defer queue.deinit();

    try queue.tryEnqueue(1);
    try queue.tryEnqueue(2);

    try std.testing.expectError(ConcurrentQueue(i32).Error.QueueIsFull, queue.tryEnqueue(3));

    const val = try queue.tryDequeue();
    try std.testing.expectEqual(val, 1);

    try queue.tryEnqueue(3);
    try std.testing.expectEqual(queue.len(), 2);
}

test "ConcurrentQueue peek" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var queue = try ConcurrentQueue(i32).init(allocator, 5);
    defer queue.deinit();

    try queue.enqueue(100);
    try queue.enqueue(200);

    const peeked = try queue.peek();
    try std.testing.expectEqual(peeked, 100);
    try std.testing.expectEqual(queue.len(), 2);
}

test "ConcurrentQueue clear" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var queue = try ConcurrentQueue(i32).init(allocator, 10);
    defer queue.deinit();

    try queue.enqueue(1);
    try queue.enqueue(2);
    try queue.enqueue(3);

    queue.clear();

    try std.testing.expect(queue.isEmpty());
    try std.testing.expectEqual(queue.len(), 0);
}

test "BTree insert and search" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var tree = BTree(i32).init(allocator);
    defer tree.deinit();

    try tree.insert(10);
    try tree.insert(5);
    try tree.insert(15);
    try tree.insert(3);
    try tree.insert(7);

    try std.testing.expect(tree.search(10));
    try std.testing.expect(tree.search(5));
    try std.testing.expect(tree.search(15));
    try std.testing.expect(tree.search(3));
    try std.testing.expect(tree.search(7));
    try std.testing.expect(!tree.search(8));
}

test "BTree delete" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var tree = BTree(i32).init(allocator);
    defer tree.deinit();

    try tree.insert(10);
    try tree.insert(5);
    try tree.insert(15);

    tree.delete(5);
    try std.testing.expect(!tree.search(5));

    tree.delete(10);
    try std.testing.expect(!tree.search(10));

    tree.delete(15);
    try std.testing.expect(!tree.search(15));
}

test "BTree inorder traversal" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var tree = BTree(i32).init(allocator);
    defer tree.deinit();

    try tree.insert(10);
    try tree.insert(5);
    try tree.insert(15);
    try tree.insert(3);
    try tree.insert(7);

    var result = try std.ArrayList(i32).initCapacity(allocator, 5);
    defer result.deinit(allocator);

    const CollectCallback = struct {
        list: *std.ArrayList(i32),
        alloc: std.mem.Allocator,

        pub fn collect(self: @This(), value: *const i32) void {
            self.list.append(self.alloc, value.*) catch {};
        }
    };

    const callback = CollectCallback{ .list = &result, .alloc = allocator };
    tree.inorder(callback, CollectCallback.collect);

    try std.testing.expectEqual(result.items[0], 3);
    try std.testing.expectEqual(result.items[1], 5);
    try std.testing.expectEqual(result.items[2], 7);
    try std.testing.expectEqual(result.items[3], 10);
    try std.testing.expectEqual(result.items[4], 15);
}
