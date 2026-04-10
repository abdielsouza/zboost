const std = @import("std");
const mem = std.mem;
const math = std.math;

/// Matrix representation with generic element type
pub fn Matrix(comptime T: type) type {
    return struct {
        data: []T,
        rows: usize,
        cols: usize,
        allocator: mem.Allocator,

        const Self = @This();

        /// Initialize a matrix
        pub fn init(allocator: mem.Allocator, rows: usize, cols: usize) !Self {
            const data = try allocator.alloc(T, rows * cols);
            return Self{
                .data = data,
                .rows = rows,
                .cols = cols,
                .allocator = allocator,
            };
        }

        /// Initialize from array
        pub fn initFromArray(allocator: mem.Allocator, rows: usize, cols: usize, array: []const T) !Self {
            if (array.len != rows * cols) {
                return error.InvalidDimensions;
            }
            const matrix = try init(allocator, rows, cols);
            @memcpy(matrix.data, array);
            return matrix;
        }

        /// Initialize identity matrix
        pub fn identity(allocator: mem.Allocator, size: usize) !Self {
            var matrix = try init(allocator, size, size);
            for (0..size) |i| {
                for (0..size) |j| {
                    matrix.set(i, j, if (i == j) @as(T, 1) else @as(T, 0));
                }
            }
            return matrix;
        }

        /// Get element at position (row, col)
        pub fn get(self: *const Self, row: usize, col: usize) T {
            return self.data[row * self.cols + col];
        }

        /// Set element at position (row, col)
        pub fn set(self: *Self, row: usize, col: usize, value: T) void {
            self.data[row * self.cols + col] = value;
        }

        /// Add two matrices
        pub fn add(self: *const Self, other: *const Self) !Self {
            if (self.rows != other.rows or self.cols != other.cols) {
                return error.IncompatibleDimensions;
            }
            var result = try init(self.allocator, self.rows, self.cols);
            for (0..self.data.len) |i| {
                result.data[i] = self.data[i] + other.data[i];
            }
            return result;
        }

        /// Subtract two matrices
        pub fn subtract(self: *const Self, other: *const Self) !Self {
            if (self.rows != other.rows or self.cols != other.cols) {
                return error.IncompatibleDimensions;
            }
            var result = try init(self.allocator, self.rows, self.cols);
            for (0..self.data.len) |i| {
                result.data[i] = self.data[i] - other.data[i];
            }
            return result;
        }

        /// Multiply two matrices
        pub fn multiply(self: *const Self, other: *const Self) !Self {
            if (self.cols != other.rows) {
                return error.IncompatibleDimensions;
            }
            var result = try init(self.allocator, self.rows, other.cols);
            for (0..self.rows) |i| {
                for (0..other.cols) |j| {
                    var sum: T = 0;
                    for (0..self.cols) |k| {
                        sum += self.get(i, k) * other.get(k, j);
                    }
                    result.set(i, j, sum);
                }
            }
            return result;
        }

        /// Element-wise multiplication (Hadamard product)
        pub fn elementWiseMultiply(self: *const Self, other: *const Self) !Self {
            if (self.rows != other.rows or self.cols != other.cols) {
                return error.IncompatibleDimensions;
            }
            var result = try init(self.allocator, self.rows, self.cols);
            for (0..self.data.len) |i| {
                result.data[i] = self.data[i] * other.data[i];
            }
            return result;
        }

        /// Transpose matrix
        pub fn transpose(self: *const Self) !Self {
            var result = try init(self.allocator, self.cols, self.rows);
            for (0..self.rows) |i| {
                for (0..self.cols) |j| {
                    result.set(j, i, self.get(i, j));
                }
            }
            return result;
        }

        /// Scalar multiplication
        pub fn scalarMultiply(self: *const Self, scalar: T) !Self {
            var result = try init(self.allocator, self.rows, self.cols);
            for (0..self.data.len) |i| {
                result.data[i] = self.data[i] * scalar;
            }
            return result;
        }

        /// Compute trace (sum of diagonal elements)
        pub fn trace(self: *const Self) !T {
            if (self.rows != self.cols) {
                return error.MatrixNotSquare;
            }
            var sum: T = 0;
            for (0..self.rows) |i| {
                sum += self.get(i, i);
            }
            return sum;
        }

        /// Compute Frobenius norm
        pub fn frobeniusNorm(self: *const Self) f64 {
            var sum: f64 = 0;
            for (self.data) |elem| {
                const val = @as(f64, @floatFromInt(elem));
                sum += val * val;
            }
            return @sqrt(sum);
        }

        /// Compute determinant (2x2 and 3x3 only for simplicity)
        pub fn determinant(self: *const Self) !T {
            if (self.rows != self.cols) {
                return error.MatrixNotSquare;
            }
            if (self.rows == 1) {
                return self.get(0, 0);
            }
            if (self.rows == 2) {
                return self.get(0, 0) * self.get(1, 1) - self.get(0, 1) * self.get(1, 0);
            }
            if (self.rows == 3) {
                const a00 = self.get(0, 0);
                const a01 = self.get(0, 1);
                const a02 = self.get(0, 2);
                const a10 = self.get(1, 0);
                const a11 = self.get(1, 1);
                const a12 = self.get(1, 2);
                const a20 = self.get(2, 0);
                const a21 = self.get(2, 1);
                const a22 = self.get(2, 2);

                return a00 * (a11 * a22 - a12 * a21) -
                    a01 * (a10 * a22 - a12 * a20) +
                    a02 * (a10 * a21 - a11 * a20);
            }
            return error.UnsupportedSize;
        }

        /// Compute inverse (2x2 and 3x3 only)
        pub fn inverse(self: *const Self) !Self {
            if (self.rows != self.cols) {
                return error.MatrixNotSquare;
            }

            const det = try self.determinant();
            if (det == 0) {
                return error.SingularMatrix;
            }

            if (self.rows == 2) {
                var result = try init(self.allocator, 2, 2);
                result.set(0, 0, self.get(1, 1) / det);
                result.set(0, 1, -self.get(0, 1) / det);
                result.set(1, 0, -self.get(1, 0) / det);
                result.set(1, 1, self.get(0, 0) / det);
                return result;
            }

            if (self.rows == 3) {
                var result = try init(self.allocator, 3, 3);
                const a00 = self.get(0, 0);
                const a01 = self.get(0, 1);
                const a02 = self.get(0, 2);
                const a10 = self.get(1, 0);
                const a11 = self.get(1, 1);
                const a12 = self.get(1, 2);
                const a20 = self.get(2, 0);
                const a21 = self.get(2, 1);
                const a22 = self.get(2, 2);

                result.set(0, 0, (a11 * a22 - a12 * a21) / det);
                result.set(0, 1, -(a01 * a22 - a02 * a21) / det);
                result.set(0, 2, (a01 * a12 - a02 * a11) / det);
                result.set(1, 0, -(a10 * a22 - a12 * a20) / det);
                result.set(1, 1, (a00 * a22 - a02 * a20) / det);
                result.set(1, 2, -(a00 * a12 - a02 * a10) / det);
                result.set(2, 0, (a10 * a21 - a11 * a20) / det);
                result.set(2, 1, -(a00 * a21 - a01 * a20) / det);
                result.set(2, 2, (a00 * a11 - a01 * a10) / det);
                return result;
            }

            return error.UnsupportedSize;
        }

        /// Row reduction to row echelon form
        pub fn rowEchelonForm(self: *Self) !void {
            var lead: usize = 0;
            for (0..self.rows) |r| {
                if (lead >= self.cols) return;

                var i = r;
                while (self.get(i, lead) == 0) {
                    i += 1;
                    if (i == self.rows) {
                        i = r;
                        lead += 1;
                        if (lead == self.cols) return;
                    }
                }

                // Swap rows
                for (0..self.cols) |j| {
                    const tmp = self.get(i, j);
                    self.set(i, j, self.get(r, j));
                    self.set(r, j, tmp);
                }

                // Scale pivot row
                const div = self.get(r, lead);
                for (0..self.cols) |j| {
                    self.set(r, j, self.get(r, j) / div);
                }

                // Eliminate below
                for (0..self.rows) |k| {
                    if (k != r) {
                        const mult = self.get(k, lead);
                        for (0..self.cols) |j| {
                            self.set(k, j, self.get(k, j) - mult * self.get(r, j));
                        }
                    }
                }

                lead += 1;
            }
        }

        /// Get rank of matrix
        pub fn rank(self: *const Self) !usize {
            var copy = try init(self.allocator, self.rows, self.cols);
            @memcpy(copy.data, self.data);
            defer copy.deinit();

            try copy.rowEchelonForm();

            var count: usize = 0;
            for (0..copy.rows) |i| {
                var isZero = true;
                for (0..copy.cols) |j| {
                    if (copy.get(i, j) != 0) {
                        isZero = false;
                        break;
                    }
                }
                if (!isZero) count += 1;
            }
            return count;
        }

        /// Print matrix
        pub fn print(self: *const Self) void {
            std.debug.print("Matrix {}x{}:\n", .{ self.rows, self.cols });
            for (0..self.rows) |i| {
                std.debug.print("  ", .{});
                for (0..self.cols) |j| {
                    std.debug.print("{d:>10} ", .{self.get(i, j)});
                }
                std.debug.print("\n", .{});
            }
        }

        /// Deinitialize matrix
        pub fn deinit(self: *Self) void {
            self.allocator.free(self.data);
        }
    };
}

/// Vector operations
pub const Vector = struct {
    pub fn dotProduct(v1: []const f64, v2: []const f64) !f64 {
        if (v1.len != v2.len) return error.IncompatibleDimensions;
        var result: f64 = 0;
        for (0..v1.len) |i| {
            result += v1[i] * v2[i];
        }
        return result;
    }

    pub fn crossProduct(v1: []const f64, v2: []const f64, allocator: mem.Allocator) ![]f64 {
        if (v1.len != 3 or v2.len != 3) return error.InvalidDimensions;
        const result = try allocator.alloc(f64, 3);
        result[0] = v1[1] * v2[2] - v1[2] * v2[1];
        result[1] = v1[2] * v2[0] - v1[0] * v2[2];
        result[2] = v1[0] * v2[1] - v1[1] * v2[0];
        return result;
    }

    pub fn magnitude(v: []const f64) f64 {
        var sum: f64 = 0;
        for (v) |elem| {
            sum += elem * elem;
        }
        return @sqrt(sum);
    }

    pub fn normalize(v: []f64) !void {
        const mag = magnitude(v);
        if (mag == 0) return error.ZeroMagnitude;
        for (0..v.len) |i| {
            v[i] /= mag;
        }
    }
};

// ===== Tests =====

test "Matrix initialization" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var matrix = try Matrix(f64).init(arena.allocator(), 2, 2);
    defer matrix.deinit();

    try std.testing.expectEqual(@as(usize, 2), matrix.rows);
    try std.testing.expectEqual(@as(usize, 2), matrix.cols);
}

test "Matrix initialization from array" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const data = [_]f64{ 1, 2, 3, 4 };
    var matrix = try Matrix(f64).initFromArray(arena.allocator(), 2, 2, &data);
    defer matrix.deinit();

    try std.testing.expectEqual(@as(f64, 1), matrix.get(0, 0));
    try std.testing.expectEqual(@as(f64, 4), matrix.get(1, 1));
}

test "Matrix identity" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var matrix = try Matrix(f64).identity(arena.allocator(), 3);
    defer matrix.deinit();

    try std.testing.expectEqual(@as(f64, 1), matrix.get(0, 0));
    try std.testing.expectEqual(@as(f64, 1), matrix.get(1, 1));
    try std.testing.expectEqual(@as(f64, 1), matrix.get(2, 2));
    try std.testing.expectEqual(@as(f64, 0), matrix.get(0, 1));
}

test "Matrix get and set" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var matrix = try Matrix(f64).init(arena.allocator(), 2, 2);
    defer matrix.deinit();

    matrix.set(0, 0, 5.0);
    matrix.set(1, 1, 10.0);

    try std.testing.expectEqual(@as(f64, 5.0), matrix.get(0, 0));
    try std.testing.expectEqual(@as(f64, 10.0), matrix.get(1, 1));
}

test "Matrix addition" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const data1 = [_]f64{ 1, 2, 3, 4 };
    const data2 = [_]f64{ 5, 6, 7, 8 };

    var m1 = try Matrix(f64).initFromArray(arena.allocator(), 2, 2, &data1);
    defer m1.deinit();
    var m2 = try Matrix(f64).initFromArray(arena.allocator(), 2, 2, &data2);
    defer m2.deinit();

    var result = try m1.add(&m2);
    defer result.deinit();

    try std.testing.expectEqual(@as(f64, 6), result.get(0, 0));
    try std.testing.expectEqual(@as(f64, 8), result.get(0, 1));
    try std.testing.expectEqual(@as(f64, 10), result.get(1, 0));
}

test "Matrix subtraction" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const data1 = [_]f64{ 5, 6, 7, 8 };
    const data2 = [_]f64{ 1, 2, 3, 4 };

    var m1 = try Matrix(f64).initFromArray(arena.allocator(), 2, 2, &data1);
    defer m1.deinit();
    var m2 = try Matrix(f64).initFromArray(arena.allocator(), 2, 2, &data2);
    defer m2.deinit();

    var result = try m1.subtract(&m2);
    defer result.deinit();

    try std.testing.expectEqual(@as(f64, 4), result.get(0, 0));
    try std.testing.expectEqual(@as(f64, 4), result.get(1, 1));
}

test "Matrix multiplication" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const data1 = [_]f64{ 1, 2, 3, 4 };
    const data2 = [_]f64{ 5, 6, 7, 8 };

    var m1 = try Matrix(f64).initFromArray(arena.allocator(), 2, 2, &data1);
    defer m1.deinit();
    var m2 = try Matrix(f64).initFromArray(arena.allocator(), 2, 2, &data2);
    defer m2.deinit();

    var result = try m1.multiply(&m2);
    defer result.deinit();

    try std.testing.expectEqual(@as(f64, 19), result.get(0, 0)); // 1*5 + 2*7
    try std.testing.expectEqual(@as(f64, 22), result.get(0, 1)); // 1*6 + 2*8
}

test "Matrix transpose" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const data = [_]f64{ 1, 2, 3, 4, 5, 6 };
    var matrix = try Matrix(f64).initFromArray(arena.allocator(), 2, 3, &data);
    defer matrix.deinit();

    var transposed = try matrix.transpose();
    defer transposed.deinit();

    try std.testing.expectEqual(@as(usize, 3), transposed.rows);
    try std.testing.expectEqual(@as(usize, 2), transposed.cols);
    try std.testing.expectEqual(@as(f64, 1), transposed.get(0, 0));
    try std.testing.expectEqual(@as(f64, 4), transposed.get(0, 1));
}

test "Matrix scalar multiplication" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const data = [_]f64{ 1, 2, 3, 4 };
    var matrix = try Matrix(f64).initFromArray(arena.allocator(), 2, 2, &data);
    defer matrix.deinit();

    var result = try matrix.scalarMultiply(2.0);
    defer result.deinit();

    try std.testing.expectEqual(@as(f64, 2), result.get(0, 0));
    try std.testing.expectEqual(@as(f64, 8), result.get(1, 1));
}

test "Matrix trace" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const data = [_]f64{ 1, 2, 3, 4, 5, 6, 7, 8, 9 };
    var matrix = try Matrix(f64).initFromArray(arena.allocator(), 3, 3, &data);
    defer matrix.deinit();

    const tr = try matrix.trace();
    try std.testing.expectEqual(@as(f64, 15), tr); // 1 + 5 + 9
}

test "Matrix determinant 2x2" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const data = [_]f64{ 1, 2, 3, 4 };
    var matrix = try Matrix(f64).initFromArray(arena.allocator(), 2, 2, &data);
    defer matrix.deinit();

    const det = try matrix.determinant();
    try std.testing.expectEqual(@as(f64, -2), det); // 1*4 - 2*3
}

test "Matrix inverse 2x2" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const data = [_]f64{ 1, 2, 3, 4 };
    var matrix = try Matrix(f64).initFromArray(arena.allocator(), 2, 2, &data);
    defer matrix.deinit();

    var inv = try matrix.inverse();
    defer inv.deinit();

    try std.testing.expectEqual(@as(f64, -2), inv.get(0, 0));
    try std.testing.expectEqual(@as(f64, 1), inv.get(0, 1));
}

test "Vector dot product" {
    const v1 = [_]f64{ 1, 2, 3 };
    const v2 = [_]f64{ 4, 5, 6 };

    const result = try Vector.dotProduct(&v1, &v2);
    try std.testing.expectEqual(@as(f64, 32), result); // 1*4 + 2*5 + 3*6
}

test "Vector magnitude" {
    const v = [_]f64{ 3, 4 };
    const mag = Vector.magnitude(&v);
    try std.testing.expectEqual(@as(f64, 5), mag);
}

test "Vector cross product" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const v1 = [_]f64{ 1, 0, 0 };
    const v2 = [_]f64{ 0, 1, 0 };

    const result = try Vector.crossProduct(&v1, &v2, arena.allocator());
    defer arena.allocator().free(result);

    try std.testing.expectEqual(@as(f64, 0), result[0]);
    try std.testing.expectEqual(@as(f64, 0), result[1]);
    try std.testing.expectEqual(@as(f64, 1), result[2]);
}

test "Vector normalize" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var v = [_]f64{ 3, 4 };
    try Vector.normalize(&v);

    try std.testing.expectApproxEqRel(@as(f64, 0.6), v[0], 1e-10);
    try std.testing.expectApproxEqRel(@as(f64, 0.8), v[1], 1e-10);
}
