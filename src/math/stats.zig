const std = @import("std");
const mem = std.mem;
const math = std.math;

/// Descriptive statistics
pub const Descriptive = struct {
    /// Calculate mean (average)
    pub fn mean(data: []const f64) f64 {
        if (data.len == 0) return 0;
        var total: f64 = 0;
        for (data) |val| {
            total += val;
        }
        return total / @as(f64, @floatFromInt(data.len));
    }

    /// Calculate median
    pub fn median(data: []const f64, allocator: mem.Allocator) !f64 {
        if (data.len == 0) return error.EmptyData;

        const sorted = try allocator.dupe(f64, data);
        defer allocator.free(sorted);

        std.sort.insertion(f64, sorted, {}, comptime std.sort.asc(f64));

        const mid = sorted.len / 2;
        if (sorted.len % 2 == 0) {
            return (sorted[mid - 1] + sorted[mid]) / 2;
        } else {
            return sorted[mid];
        }
    }

    /// Calculate mode (most frequent value)
    pub fn mode(data: []const f64, allocator: mem.Allocator) !f64 {
        if (data.len == 0) return error.EmptyData;

        var map = std.AutoHashMap(u64, u32).init(allocator);
        defer map.deinit();

        for (data) |val| {
            const bits = @as(u64, @bitCast(val));
            const count = map.get(bits) orelse 0;
            try map.put(bits, count + 1);
        }

        var maxCount: u32 = 0;
        var maxBits: u64 = 0;

        var iter = map.iterator();
        while (iter.next()) |entry| {
            if (entry.value_ptr.* > maxCount) {
                maxCount = entry.value_ptr.*;
                maxBits = entry.key_ptr.*;
            }
        }

        return @as(f64, @bitCast(maxBits));
    }

    /// Calculate variance
    pub fn variance(data: []const f64) f64 {
        if (data.len == 0) return 0;

        const m = mean(data);
        var total: f64 = 0;

        for (data) |val| {
            const diff = val - m;
            total += diff * diff;
        }

        return total / @as(f64, @floatFromInt(data.len));
    }

    /// Calculate sample variance (N-1)
    pub fn sampleVariance(data: []const f64) f64 {
        if (data.len <= 1) return 0;

        const m = mean(data);
        var total: f64 = 0;

        for (data) |val| {
            const diff = val - m;
            total += diff * diff;
        }

        return total / @as(f64, @floatFromInt(data.len - 1));
    }

    /// Calculate standard deviation
    pub fn stdDev(data: []const f64) f64 {
        return @sqrt(variance(data));
    }

    /// Calculate sample standard deviation (N-1)
    pub fn sampleStdDev(data: []const f64) f64 {
        return @sqrt(sampleVariance(data));
    }

    /// Calculate range
    pub fn range(data: []const f64) !struct { min: f64, max: f64 } {
        if (data.len == 0) return error.EmptyData;

        var min = data[0];
        var max = data[0];

        for (data[1..]) |val| {
            if (val < min) min = val;
            if (val > max) max = val;
        }

        return .{ .min = min, .max = max };
    }

    /// Calculate interquartile range (IQR)
    pub fn iqr(data: []const f64, allocator: mem.Allocator) !f64 {
        if (data.len < 4) return error.InsufficientData;

        const sorted = try allocator.dupe(f64, data);
        defer allocator.free(sorted);

        std.sort.insertion(f64, sorted, {}, comptime std.sort.asc(f64));

        const q1_idx = sorted.len / 4;
        const q3_idx = (3 * sorted.len) / 4;

        return sorted[q3_idx] - sorted[q1_idx];
    }

    /// Calculate skewness
    pub fn skewness(data: []const f64) f64 {
        if (data.len == 0) return 0;

        const m = mean(data);
        const s = stdDev(data);

        if (s == 0) return 0;

        var total: f64 = 0;
        for (data) |val| {
            const z = (val - m) / s;
            total += z * z * z;
        }

        return (total / @as(f64, @floatFromInt(data.len)));
    }

    /// Calculate kurtosis
    pub fn kurtosis(data: []const f64) f64 {
        if (data.len == 0) return 0;

        const m = mean(data);
        const s = stdDev(data);

        if (s == 0) return 0;

        var total: f64 = 0;
        for (data) |val| {
            const z = (val - m) / s;
            total += z * z * z * z;
        }

        return (total / @as(f64, @floatFromInt(data.len))) - 3;
    }

    /// Calculate covariance between two datasets
    pub fn covariance(x: []const f64, y: []const f64) !f64 {
        if (x.len != y.len or x.len == 0) return error.IncompatibleData;

        const mean_x = mean(x);
        const mean_y = mean(y);

        var total: f64 = 0;
        for (0..x.len) |i| {
            total += (x[i] - mean_x) * (y[i] - mean_y);
        }

        return total / @as(f64, @floatFromInt(x.len));
    }

    /// Calculate Pearson correlation coefficient
    pub fn pearsonCorrelation(x: []const f64, y: []const f64) !f64 {
        if (x.len != y.len or x.len == 0) return error.IncompatibleData;

        const cov = try covariance(x, y);
        const std_x = stdDev(x);
        const std_y = stdDev(y);

        if (std_x == 0 or std_y == 0) return error.ZeroStdDev;

        return cov / (std_x * std_y);
    }

    /// Calculate sum
    pub fn sum(data: []const f64) f64 {
        var result: f64 = 0;
        for (data) |val| {
            result += val;
        }
        return result;
    }

    /// Calculate product
    pub fn product(data: []const f64) f64 {
        var result: f64 = 1;
        for (data) |val| {
            result *= val;
        }
        return result;
    }
};

/// Probability distributions
pub const Distributions = struct {
    /// Normal (Gaussian) distribution PDF
    pub fn normalPDF(x: f64, mean: f64, stddev: f64) f64 {
        if (stddev <= 0) return 0;
        const pi = std.math.pi;
        const exp_arg = -0.5 * math.pow(f64, (x - mean) / stddev, 2);
        return (1.0 / (stddev * @sqrt(2 * pi))) * @exp(exp_arg);
    }

    /// Uniform distribution PDF
    pub fn uniformPDF(x: f64, a: f64, b: f64) f64 {
        if (x >= a and x <= b) {
            return 1.0 / (b - a);
        }
        return 0;
    }

    /// Exponential distribution PDF
    pub fn exponentialPDF(x: f64, lambda: f64) f64 {
        if (lambda <= 0 or x < 0) return 0;
        return lambda * @exp(-lambda * x);
    }

    /// Exponential distribution CDF
    pub fn exponentialCDF(x: f64, lambda: f64) f64 {
        if (lambda <= 0 or x < 0) return 0;
        return 1.0 - @exp(-lambda * x);
    }

    /// Bernoulli distribution
    pub fn bernoulliPMF(x: u32, p: f64) f64 {
        if (p <= 0 or p >= 1) return 0;
        if (x == 0) return 1 - p;
        if (x == 1) return p;
        return 0;
    }

    /// Binomial distribution PMF
    pub fn binomialPMF(k: u32, n: u32, p: f64) f64 {
        if (p <= 0 or p >= 1 or k > n) return 0;

        // Calculate C(n,k)
        var coeff: f64 = 1;
        if (k < n - k) {
            for (0..k) |i| {
                coeff *= @as(f64, @floatFromInt(n - @as(u32, @intCast(i))));
                coeff /= @as(f64, @floatFromInt(@as(u32, @intCast(i)) + 1));
            }
        } else {
            for (0..n - k) |i| {
                coeff *= @as(f64, @floatFromInt(k + @as(u32, @intCast(i)) + 1));
                coeff /= @as(f64, @floatFromInt(@as(u32, @intCast(i)) + 1));
            }
        }

        const pk = math.pow(f64, p, @floatFromInt(k));
        const pn_k = math.pow(f64, 1 - p, @floatFromInt(n - k));

        return coeff * pk * pn_k;
    }

    /// Poisson distribution PMF
    pub fn poissonPMF(k: u32, lambda: f64) f64 {
        if (lambda <= 0) return 0;

        // Calculate factorial of k
        var factorial: f64 = 1;
        for (1..k + 1) |i| {
            factorial *= @as(f64, @floatFromInt(i));
        }

        return (math.pow(f64, lambda, @floatFromInt(k)) * @exp(-lambda)) / factorial;
    }

    /// Chi-squared distribution PDF (simplified for small degrees of freedom)
    pub fn chiSquaredPDF(x: f64, df: u32) f64 {
        if (x < 0 or df == 0) return 0;

        const k = @as(f64, @floatFromInt(df)) / 2.0;
        const numerator = math.pow(f64, x, k - 1) * @exp(-x / 2.0);
        const denominator = math.pow(f64, 2.0, k) * lgamma(k);

        return numerator / denominator;
    }
};

/// Hypothesis testing
pub const HypothesisTesting = struct {
    /// T-test statistic (two-sample)
    pub fn tTestStatistic(sample1: []const f64, sample2: []const f64) !f64 {
        if (sample1.len == 0 or sample2.len == 0) return error.EmptyData;

        const mean1 = Descriptive.mean(sample1);
        const mean2 = Descriptive.mean(sample2);
        const var1 = Descriptive.sampleVariance(sample1);
        const var2 = Descriptive.sampleVariance(sample2);

        const n1 = @as(f64, @floatFromInt(sample1.len));
        const n2 = @as(f64, @floatFromInt(sample2.len));

        const pooled_var = ((n1 - 1) * var1 + (n2 - 1) * var2) / (n1 + n2 - 2);
        const denominator = @sqrt(pooled_var * (1 / n1 + 1 / n2));

        if (denominator == 0) return error.ZeroVariance;

        return (mean1 - mean2) / denominator;
    }

    /// Chi-squared goodness of fit statistic
    pub fn chiSquaredGoodnessOfFit(observed: []const f64, expected: []const f64) !f64 {
        if (observed.len != expected.len or observed.len == 0) return error.IncompatibleData;

        var chi2: f64 = 0;
        for (0..observed.len) |i| {
            const diff = observed[i] - expected[i];
            if (expected[i] != 0) {
                chi2 += (diff * diff) / expected[i];
            }
        }

        return chi2;
    }

    /// Z-score
    pub fn zScore(value: f64, mean: f64, stddev: f64) f64 {
        if (stddev == 0) return 0;
        return (value - mean) / stddev;
    }
};

/// Helper function: natural logarithm of gamma function (Stirling approximation)
fn lgamma(z: f64) f64 {
    if (z <= 0) return 0;
    const pi = std.math.pi;
    return 0.5 * @log(2 * pi / z) + z * (@log(z) - 1);
}

// ===== Tests =====

test "Descriptive mean" {
    const data = [_]f64{ 1, 2, 3, 4, 5 };
    const m = Descriptive.mean(&data);
    try std.testing.expectEqual(@as(f64, 3), m);
}

test "Descriptive median even" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const data = [_]f64{ 1, 2, 3, 4 };
    const med = try Descriptive.median(&data, arena.allocator());
    try std.testing.expectEqual(@as(f64, 2.5), med);
}

test "Descriptive median odd" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const data = [_]f64{ 1, 2, 3, 4, 5 };
    const med = try Descriptive.median(&data, arena.allocator());
    try std.testing.expectEqual(@as(f64, 3), med);
}

test "Descriptive variance" {
    const data = [_]f64{ 1, 2, 3, 4, 5 };
    const var_result = Descriptive.variance(&data);
    try std.testing.expectApproxEqRel(@as(f64, 2), var_result, 1e-10);
}

test "Descriptive standard deviation" {
    const data = [_]f64{ 1, 2, 3, 4, 5 };
    const std_dev = Descriptive.stdDev(&data);
    try std.testing.expectApproxEqRel(@as(f64, std.math.sqrt(@as(f64, 2))), std_dev, 1e-10);
}

test "Descriptive range" {
    const data = [_]f64{ 1, 5, 3, 2, 4 };
    const r = try Descriptive.range(&data);
    try std.testing.expectEqual(@as(f64, 1), r.min);
    try std.testing.expectEqual(@as(f64, 5), r.max);
}

test "Descriptive sum" {
    const data = [_]f64{ 1, 2, 3, 4, 5 };
    const s = Descriptive.sum(&data);
    try std.testing.expectEqual(@as(f64, 15), s);
}

test "Descriptive product" {
    const data = [_]f64{ 2, 3, 4 };
    const p = Descriptive.product(&data);
    try std.testing.expectEqual(@as(f64, 24), p);
}

test "Descriptive skewness" {
    const data = [_]f64{ 1, 2, 3, 4, 5 };
    const skew = Descriptive.skewness(&data);
    try std.testing.expectApproxEqRel(@as(f64, 0), skew, 1e-10);
}

test "Descriptive covariance" {
    const x = [_]f64{ 1, 2, 3, 4, 5 };
    const y = [_]f64{ 2, 4, 6, 8, 10 };
    const cov = try Descriptive.covariance(&x, &y);
    try std.testing.expect(cov > 0);
}

test "Descriptive Pearson correlation" {
    const x = [_]f64{ 1, 2, 3, 4, 5 };
    const y = [_]f64{ 2, 4, 6, 8, 10 };
    const corr = try Descriptive.pearsonCorrelation(&x, &y);
    try std.testing.expectApproxEqRel(@as(f64, 1), corr, 1e-10);
}

test "Normal distribution PDF" {
    const pdf = Distributions.normalPDF(0, 0, 1);
    try std.testing.expectApproxEqRel(@as(f64, 1.0 / @sqrt(2 * std.math.pi)), pdf, 1e-10);
}

test "Uniform distribution PDF" {
    const pdf = Distributions.uniformPDF(0.5, 0, 1);
    try std.testing.expectEqual(@as(f64, 1), pdf);
}

test "Exponential distribution PDF" {
    const pdf = Distributions.exponentialPDF(0, 1);
    try std.testing.expectEqual(@as(f64, 1), pdf);
}

test "Exponential distribution CDF" {
    const cdf = Distributions.exponentialCDF(0, 1);
    try std.testing.expectEqual(@as(f64, 0), cdf);
}

test "Bernoulli distribution" {
    const pmf_0 = Distributions.bernoulliPMF(0, 0.5);
    const pmf_1 = Distributions.bernoulliPMF(1, 0.5);
    try std.testing.expectEqual(@as(f64, 0.5), pmf_0);
    try std.testing.expectEqual(@as(f64, 0.5), pmf_1);
}

test "Binomial distribution" {
    const pmf = Distributions.binomialPMF(2, 4, 0.5);
    try std.testing.expect(pmf > 0);
}

test "Poisson distribution" {
    const pmf = Distributions.poissonPMF(2, 3);
    try std.testing.expect(pmf > 0);
}

test "Z-score" {
    const z = HypothesisTesting.zScore(70, 50, 10);
    try std.testing.expectEqual(@as(f64, 2), z);
}

test "Chi-squared goodness of fit" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const observed = [_]f64{ 10, 15, 20, 15 };
    const expected = [_]f64{ 15, 15, 15, 15 };

    const chi2 = try HypothesisTesting.chiSquaredGoodnessOfFit(&observed, &expected);
    try std.testing.expect(chi2 >= 0);
}

test "Sample variance" {
    const data = [_]f64{ 1, 2, 3, 4, 5 };
    const svar = Descriptive.sampleVariance(&data);
    try std.testing.expectApproxEqRel(@as(f64, 2.5), svar, 1e-10);
}

test "Sample standard deviation" {
    const data = [_]f64{ 1, 2, 3, 4, 5 };
    const sstd = Descriptive.sampleStdDev(&data);
    try std.testing.expectApproxEqRel(@as(f64, @sqrt(2.5)), sstd, 1e-10);
}
