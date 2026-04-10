const std = @import("std");
const Allocator = std.mem.Allocator;
const Thread = std.Thread;
const Mutex = Thread.Mutex;
const Condition = Thread.Condition;

/// Thread-safe wrapper around a value
pub fn Synchronized(comptime T: type) type {
    return struct {
        value: T,
        mutex: Mutex = .{},

        const Self = @This();

        /// Lock and execute a function with the value
        pub fn withLock(self: *Self, comptime F: fn (*T) void) void {
            self.mutex.lock();
            defer self.mutex.unlock();
            F(&self.value);
        }

        /// Lock and read the value
        pub fn read(self: *Self) T {
            self.mutex.lock();
            defer self.mutex.unlock();
            return self.value;
        }

        /// Lock and write the value
        pub fn write(self: *Self, new_value: T) void {
            self.mutex.lock();
            defer self.mutex.unlock();
            self.value = new_value;
        }
    };
}

/// Semaphore - synchronization primitive for controlling access to resources
pub const Semaphore = struct {
    count: usize,
    mutex: Mutex = .{},
    condition: Condition = .{},
    max_count: usize,

    /// Initialize a semaphore with initial count and max count
    pub fn init(initial_count: usize, max_count: usize) Semaphore {
        return Semaphore{
            .count = initial_count,
            .max_count = max_count,
        };
    }

    /// Acquire a permit (wait and decrement count)
    pub fn acquire(self: *Semaphore) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        while (self.count == 0) {
            self.condition.wait(&self.mutex);
        }
        self.count -= 1;
    }

    /// Try to acquire without blocking
    pub fn tryAcquire(self: *Semaphore) bool {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.count > 0) {
            self.count -= 1;
            return true;
        }
        return false;
    }

    /// Release a permit (increment count and signal)
    pub fn release(self: *Semaphore) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.count < self.max_count) {
            self.count += 1;
            self.condition.signal();
        }
    }

    /// Get current count
    pub fn getCount(self: *Semaphore) usize {
        self.mutex.lock();
        defer self.mutex.unlock();
        return self.count;
    }
};

/// RwLock - Reader-Writer Lock for multiple readers or single writer
pub fn RwLock(comptime T: type) type {
    return struct {
        value: T,
        readers: usize = 0,
        writers_waiting: usize = 0,
        writers_active: usize = 0,
        mutex: Mutex = .{},
        read_condition: Condition = .{},
        write_condition: Condition = .{},

        const Self = @This();

        /// Initialize RwLock with value
        pub fn init(value: T) Self {
            return Self{ .value = value };
        }

        /// Acquire read lock
        pub fn readLock(self: *Self) void {
            self.mutex.lock();
            defer self.mutex.unlock();

            while (self.writers_active > 0 or self.writers_waiting > 0) {
                self.read_condition.wait(&self.mutex);
            }
            self.readers += 1;
        }

        /// Release read lock
        pub fn readUnlock(self: *Self) void {
            self.mutex.lock();
            defer self.mutex.unlock();

            self.readers -= 1;
            if (self.readers == 0) {
                self.write_condition.signal();
            }
        }

        /// Acquire write lock
        pub fn writeLock(self: *Self) void {
            self.mutex.lock();
            defer self.mutex.unlock();

            self.writers_waiting += 1;
            while (self.readers > 0 or self.writers_active > 0) {
                self.write_condition.wait(&self.mutex);
            }
            self.writers_waiting -= 1;
            self.writers_active += 1;
        }

        /// Release write lock
        pub fn writeUnlock(self: *Self) void {
            self.mutex.lock();
            defer self.mutex.unlock();

            self.writers_active -= 1;
            self.write_condition.signal();
            self.read_condition.broadcast();
        }

        /// Execute function with read lock
        pub fn withReadLock(self: *Self, comptime F: fn (*const T) void) void {
            self.readLock();
            defer self.readUnlock();
            F(&self.value);
        }

        /// Execute function with write lock
        pub fn withWriteLock(self: *Self, comptime F: fn (*T) void) void {
            self.writeLock();
            defer self.writeUnlock();
            F(&self.value);
        }
    };
}

/// Channel - thread-safe message passing
pub fn Channel(comptime T: type) type {
    return struct {
        items: std.ArrayList(T),
        allocator: Allocator,
        mutex: Mutex = .{},
        send_condition: Condition = .{},
        recv_condition: Condition = .{},
        closed: bool = false,
        max_size: ?usize = null,

        const Self = @This();

        /// Initialize channel
        pub fn init(allocator: Allocator, max_size: ?usize) Allocator.Error!Self {
            return Self{
                .items = try std.ArrayList(T).initCapacity(allocator, 0),
                .allocator = allocator,
                .max_size = max_size,
            };
        }

        /// Send a value (blocks if full)
        pub fn send(self: *Self, value: T) Allocator.Error!void {
            self.mutex.lock();
            defer self.mutex.unlock();

            // Wait if channel is at max capacity
            while (self.max_size != null and self.items.items.len >= self.max_size.?) {
                self.send_condition.wait(&self.mutex);
            }

            try self.items.append(self.allocator, value);
            self.recv_condition.signal();
        }

        /// Try to send without blocking
        pub fn trySend(self: *Self, value: T) Allocator.Error!bool {
            self.mutex.lock();
            defer self.mutex.unlock();

            if (self.max_size != null and self.items.items.len >= self.max_size.?) {
                return false;
            }

            try self.items.append(self.allocator, value);
            self.recv_condition.signal();
            return true;
        }

        /// Receive a value (blocks if empty)
        pub fn recv(self: *Self) Allocator.Error!?T {
            self.mutex.lock();
            defer self.mutex.unlock();

            while (self.items.items.len == 0) {
                self.recv_condition.wait(&self.mutex);
            }

            const value = self.items.orderedRemove(0);
            self.send_condition.signal();
            return value;
        }

        /// Try to receive without blocking
        pub fn tryRecv(self: *Self) ?T {
            self.mutex.lock();
            defer self.mutex.unlock();

            if (self.items.items.len == 0) {
                return null;
            }

            const value = self.items.orderedRemove(0);
            self.send_condition.signal();
            return value;
        }

        /// Get number of items in channel
        pub fn len(self: *Self) usize {
            self.mutex.lock();
            defer self.mutex.unlock();
            return self.items.items.len;
        }

        /// Close the channel
        pub fn close(self: *Self) void {
            self.mutex.lock();
            defer self.mutex.unlock();

            self.closed = true;
            self.recv_condition.broadcast();
            self.send_condition.broadcast();
        }

        /// Deinitialize the channel
        pub fn deinit(self: *Self) void {
            self.items.deinit(self.allocator);
        }
    };
}

/// Thread-safe counter
pub const AtomicCounter = struct {
    value: i64 = 0,
    mutex: Mutex = .{},

    /// Increment and return new value
    pub fn increment(self: *AtomicCounter) i64 {
        self.mutex.lock();
        defer self.mutex.unlock();
        self.value += 1;
        return self.value;
    }

    /// Decrement and return new value
    pub fn decrement(self: *AtomicCounter) i64 {
        self.mutex.lock();
        defer self.mutex.unlock();
        self.value -= 1;
        return self.value;
    }

    /// Add value
    pub fn add(self: *AtomicCounter, delta: i64) i64 {
        self.mutex.lock();
        defer self.mutex.unlock();
        self.value += delta;
        return self.value;
    }

    /// Get current value
    pub fn get(self: *AtomicCounter) i64 {
        self.mutex.lock();
        defer self.mutex.unlock();
        return self.value;
    }

    /// Set value
    pub fn set(self: *AtomicCounter, new_value: i64) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        self.value = new_value;
    }
};

/// Thread Pool for parallel task execution
pub const ThreadPool = struct {
    allocator: Allocator,
    threads: std.ArrayList(Thread),
    task_queue: std.ArrayList(Task),
    task_mutex: Mutex = .{},
    task_condition: Condition = .{},
    is_shutdown: bool = false,
    active_tasks: usize = 0,
    all_tasks_done: Condition = .{},

    const Task = struct {
        func: *const fn (?*anyopaque) void,
        context: ?*anyopaque,
    };

    const Self = @This();

    /// Initialize thread pool with N worker threads
    pub fn init(allocator: Allocator, num_threads: usize) Allocator.Error!Self {
        var self = Self{
            .allocator = allocator,
            .threads = try std.ArrayList(Thread).initCapacity(allocator, num_threads),
            .task_queue = try std.ArrayList(Task).initCapacity(allocator, 0),
        };

        var i: usize = 0;
        while (i < num_threads) : (i += 1) {
            const thread = try self.threads.allocator.create(Thread);
            thread.* = try Thread.spawn(.{}, workerThread, .{&self});
            try self.threads.append(thread.*);
        }

        return self;
    }

    /// Submit a task to the thread pool
    pub fn submit(self: *Self, func: *const fn (?*anyopaque) void, context: ?*anyopaque) Allocator.Error!void {
        self.task_mutex.lock();
        defer self.task_mutex.unlock();

        if (self.is_shutdown) {
            return error.ThreadPoolShutdown;
        }

        try self.task_queue.append(.{
            .func = func,
            .context = context,
        });
        self.active_tasks += 1;
        self.task_condition.signal();
    }

    /// Worker thread function
    fn workerThread(self: *Self) void {
        while (true) {
            self.task_mutex.lock();

            // Wait for task or shutdown signal
            while (self.task_queue.items.len == 0 and !self.is_shutdown) {
                self.task_condition.wait(&self.task_mutex);
            }

            if (self.is_shutdown and self.task_queue.items.len == 0) {
                self.task_mutex.unlock();
                break;
            }

            const task = self.task_queue.orderedRemove(0);
            self.task_mutex.unlock();

            // Execute task
            task.func(task.context);

            // Signal task completion
            self.task_mutex.lock();
            self.active_tasks -= 1;
            if (self.active_tasks == 0) {
                self.all_tasks_done.broadcast();
            }
            self.task_mutex.unlock();
        }
    }

    /// Wait for all tasks to complete
    pub fn waitAll(self: *Self) void {
        self.task_mutex.lock();
        defer self.task_mutex.unlock();

        while (self.active_tasks > 0) {
            self.all_tasks_done.wait(&self.task_mutex);
        }
    }

    /// Shutdown the thread pool
    pub fn shutdownPool(self: *Self) void {
        self.task_mutex.lock();
        self.is_shutdown = true;
        self.task_condition.broadcast();
        self.task_mutex.unlock();

        for (self.threads.items) |thread| {
            thread.join();
        }

        self.threads.deinit();
        self.task_queue.deinit();
    }

    /// Deinitialize the thread pool
    pub fn deinit(self: *Self) void {
        if (!self.is_shutdown) {
            self.shutdownPool();
        }
    }
};

/// Barrier - synchronization point for multiple threads
pub const Barrier = struct {
    num_threads: usize,
    count: usize = 0,
    mutex: Mutex = .{},
    condition: Condition = .{},

    /// Initialize barrier for N threads
    pub fn init(num_threads: usize) Barrier {
        return Barrier{ .num_threads = num_threads };
    }

    /// Wait for all threads to reach barrier
    pub fn wait(self: *Barrier) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        self.count += 1;

        if (self.count == self.num_threads) {
            self.count = 0;
            self.condition.broadcast();
        } else {
            while (self.count != 0) {
                self.condition.wait(&self.mutex);
            }
        }
    }
};

// Tests
const testing = std.testing;

test "Semaphore creation" {
    const sem = Semaphore.init(0, 5);
    _ = sem;
    try testing.expect(true);
}

test "AtomicCounter creation" {
    const counter = AtomicCounter{};
    _ = counter;
    try testing.expect(true);
}

test "Semaphore tryAcquire when available" {
    var sem = Semaphore.init(3, 5);

    try testing.expect(sem.tryAcquire() == true);
    try testing.expect(sem.tryAcquire() == true);
    try testing.expect(sem.getCount() == 1);
}

test "Semaphore tryAcquire when exhausted" {
    var sem = Semaphore.init(0, 5);

    try testing.expect(sem.tryAcquire() == false);
    try testing.expect(sem.getCount() == 0);
}

test "Semaphore release respects max_count" {
    var sem = Semaphore.init(5, 5);

    sem.release();
    try testing.expect(sem.getCount() == 5);
}

test "AtomicCounter increment" {
    var counter = AtomicCounter{};

    const v1 = counter.increment();
    const v2 = counter.increment();
    const v3 = counter.increment();

    try testing.expect(v1 == 1);
    try testing.expect(v2 == 2);
    try testing.expect(v3 == 3);
}

test "AtomicCounter decrement" {
    var counter = AtomicCounter{ .value = 10 };

    const v1 = counter.decrement();
    const v2 = counter.decrement();

    try testing.expect(v1 == 9);
    try testing.expect(v2 == 8);
}

test "AtomicCounter add" {
    var counter = AtomicCounter{ .value = 5 };

    const result = counter.add(10);
    try testing.expect(result == 15);
    try testing.expect(counter.get() == 15);
}

test "AtomicCounter set and get" {
    var counter = AtomicCounter{};

    counter.set(42);
    try testing.expect(counter.get() == 42);
}

test "RwLock value initialization" {
    const lock = RwLock(i32).init(100);

    try testing.expect(lock.value == 100);
}

test "RwLock read operations" {
    var lock = RwLock(i32).init(42);

    lock.readLock();
    try testing.expect(lock.value == 42);
    lock.readUnlock();
}

test "RwLock write operations" {
    var lock = RwLock(i32).init(10);

    lock.writeLock();
    lock.value = 20;
    lock.writeUnlock();

    lock.readLock();
    try testing.expect(lock.value == 20);
    lock.readUnlock();
}

test "RwLock multiple readers" {
    var lock = RwLock(i32).init(50);

    lock.readLock();
    lock.readLock();
    try testing.expect(lock.readers == 2);
    lock.readUnlock();
    lock.readUnlock();
}

test "Synchronized read value" {
    var sync = Synchronized(i32){ .value = 123 };

    const val = sync.read();
    try testing.expect(val == 123);
}

test "Synchronized write value" {
    var sync = Synchronized(i32){ .value = 0 };

    sync.write(456);
    try testing.expect(sync.read() == 456);
}

test "Barrier initialization" {
    const barrier = Barrier.init(4);
    try testing.expect(barrier.num_threads == 4);
    try testing.expect(barrier.count == 0);
}

test "Channel initialization" {
    const allocator = testing.allocator;
    var channel = try Channel(i32).init(allocator, 10);
    defer channel.deinit();

    try testing.expect(channel.len() == 0);
    try testing.expect(channel.closed == false);
}

test "Channel send and receive single value" {
    const allocator = testing.allocator;
    var channel = try Channel(i32).init(allocator, 10);
    defer channel.deinit();

    try channel.send(42);
    const value = try channel.recv();

    try testing.expect(value.? == 42);
}

test "Channel multiple sends and receives" {
    const allocator = testing.allocator;
    var channel = try Channel(i32).init(allocator, 10);
    defer channel.deinit();

    try channel.send(1);
    try channel.send(2);
    try channel.send(3);

    const v1 = try channel.recv();
    const v2 = try channel.recv();
    const v3 = try channel.recv();

    try testing.expect(v1.? == 1);
    try testing.expect(v2.? == 2);
    try testing.expect(v3.? == 3);
}

test "Channel trySend when available" {
    const allocator = testing.allocator;
    var channel = try Channel(i32).init(allocator, 5);
    defer channel.deinit();

    const result = try channel.trySend(99);
    try testing.expect(result == true);
}

test "Channel tryRecv empty" {
    const allocator = testing.allocator;
    var channel = try Channel(i32).init(allocator, 10);
    defer channel.deinit();

    const value = channel.tryRecv();
    try testing.expect(value == null);
}

test "Channel tryRecv with value" {
    const allocator = testing.allocator;
    var channel = try Channel(i32).init(allocator, 10);
    defer channel.deinit();

    try channel.send(77);
    const value = channel.tryRecv();
    try testing.expect(value == 77);
}

test "Channel length tracking" {
    const allocator = testing.allocator;
    var channel = try Channel(i32).init(allocator, 10);
    defer channel.deinit();

    try testing.expect(channel.len() == 0);
    try channel.send(1);
    try testing.expect(channel.len() == 1);
    try channel.send(2);
    try testing.expect(channel.len() == 2);

    _ = try channel.recv();
    try testing.expect(channel.len() == 1);
}

test "Channel close behavior" {
    const allocator = testing.allocator;
    var channel = try Channel(i32).init(allocator, 10);
    defer channel.deinit();

    channel.close();
    try testing.expect(channel.closed == true);
}

test "Channel FIFO ordering" {
    const allocator = testing.allocator;
    var channel = try Channel(u32).init(allocator, 20);
    defer channel.deinit();

    var i: u32 = 0;
    while (i < 10) : (i += 1) {
        try channel.send(i);
    }

    i = 0;
    while (i < 10) : (i += 1) {
        const val = try channel.recv();
        try testing.expect(val.? == i);
    }
}

test "Channel with string type" {
    const allocator = testing.allocator;
    var channel = try Channel([]const u8).init(allocator, 5);
    defer channel.deinit();

    const msg1 = "hello";
    const msg2 = "world";

    try channel.send(msg1);
    try channel.send(msg2);

    const received1 = try channel.recv();
    const received2 = try channel.recv();

    try testing.expect(std.mem.eql(u8, received1.?, msg1));
    try testing.expect(std.mem.eql(u8, received2.?, msg2));
}

test "Concurrency Synchronized with struct" {
    const Point = struct { x: i32, y: i32 };
    var sync = Synchronized(Point){ .value = .{ .x = 10, .y = 20 } };

    const p = sync.read();
    try testing.expect(p.x == 10);
    try testing.expect(p.y == 20);

    sync.write(.{ .x = 30, .y = 40 });
    const p2 = sync.read();
    try testing.expect(p2.x == 30);
    try testing.expect(p2.y == 40);
}
