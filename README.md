# ZBoost: Advanced libraries for Zig language.

## Concept
This project is a set of libraries for the Zig language that offers a lot of resources to extend and simplify the practical use of the Zig standard libraries. Its purpose is very similar to the Boost libraries for C++, but for Zig.

## Resource Scopes
- Networking
    - HTTP
    - TCP/UDP
    - Sockets
    - Routing and Middleware
    - Connection Security
- Concurrency
    - Futures
    - Semaphores
    - Thread Pooling
    - Multiprocessing
    - Message Passing
    - Asynchronous Event Handling
- Math
    - Linear Algebra
    - Statistics and Probability
    - Advanced Calculus
- AI
    - Machine Learning
    - Tensors
    - Reinforcement Learning
- Collections
    - Stacks
    - Queues
    - Trees and Graphs
- System
    - OS Functions
    - Args and Envs
- Misc
    - Strings
    - Traits and Helper Types
    - Metaprogramming
    - Memory Interfaces

## Installation Guide

### Prerequisites

Before installing ZBoost, ensure you have the following installed on your system:

- **Zig** (0.12.0 or later): Download from [https://ziglang.org/download](https://ziglang.org/download)
  - Verify installation: `zig version`
  - Ensure `zig` is in your system PATH

### Step-by-Step Installation

#### 1. Clone the Repository

```bash
git clone https://github.com/abdiel-sobreira/zboost.git
cd zboost
```

#### 2. Verify the Project Structure

```bash
tree -L 2  # Display project structure
```

Expected structure:
```
zboost/
├── build.zig
├── build.zig.zon
├── README.md
├── LICENSE
├── src/
│   ├── lib.zig (main entry point)
│   ├── network.zig
│   ├── math.zig
│   ├── concurrency.zig
│   ├── collections.zig
│   ├── memory.zig
│   ├── string.zig
│   ├── system.zig
│   └── math/
│       ├── linalg.zig (Linear Algebra)
│       └── stats.zig (Statistics)
└── zig-out/
    └── lib/
```

#### 3. Build the Library

```bash
# Build the ZBoost library
zig build

# Output will be in zig-out/lib/
```

#### 4. Run Tests

```bash
# Run all tests
zig build test

# Run specific module tests
zig test src/math/linalg.zig    # Linear Algebra tests
zig test src/math/stats.zig     # Statistics tests
zig test src/network.zig        # Network tests
```

### Using ZBoost in Your Project

#### Option 1: As a Local Dependency

1. Add to your `build.zig.zon`:
```zig
.{
    .name = "my_project",
    .version = "0.1.0",
    .dependencies = .{
        .zboost = .{
            .path = "../zboost",
        },
    },
}
```

2. In your `build.zig`:
```zig
const zboost_dep = b.dependency("zboost", .{
    .target = target,
    .optimize = optimize,
});

const my_module = b.addModule("my_module", .{
    .root_source_file = b.path("src/main.zig"),
    .target = target,
    .optimize = optimize,
});

my_module.addImport("zboost", zboost_dep.module("zboost"));
```

3. In your Zig code:
```zig
const zboost = @import("zboost");

pub fn main() void {
    // Use zboost modules
    const network = zboost.network;
    const math = zboost.math;
    const stats = zboost.math.stats;
}
```

#### Option 2: Remote Dependency with `zig fetch`

1. Fetch the package from the remote repository:
```bash
# Fetch ZBoost from GitHub
zig fetch --save git+https://github.com/abdiel-sobreira/zboost.git#master

# Or use a specific commit hash
zig fetch --save git+https://github.com/abdiel-sobreira/zboost.git#<commit-hash>
```

2. Your `build.zig.zon` will be automatically updated:
```zig
.{
    .name = "my_project",
    .version = "0.1.0",
    .dependencies = .{
        .zboost = .{
            .url = "git+https://github.com/abdiel-sobreira/zboost.git#<hash>",
            .hash = "<content-hash>",
        },
    },
}
```

3. In your `build.zig`:
```zig
const zboost_dep = b.dependency("zboost", .{
    .target = target,
    .optimize = optimize,
});

const my_module = b.addModule("my_module", .{
    .root_source_file = b.path("src/main.zig"),
    .target = target,
    .optimize = optimize,
});

my_module.addImport("zboost", zboost_dep.module("zboost"));
```

4. In your Zig code:
```zig
const zboost = @import("zboost");

pub fn main() void {
    // Use zboost modules
    const network = zboost.network;
    const math = zboost.math;
    const stats = zboost.math.stats;
}
```

#### Option 3: Copy Source Files

Simply copy the `src/` directory into your project and import the modules:

```zig
const math = @import("src/lib.zig").math;
const linalg = @import("src/math/linalg.zig");
const stats = @import("src/math/stats.zig");
```

### Quick Examples

#### Using Linear Algebra

```zig
const std = @import("std");
const linalg = @import("zboost").math.linalg;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Create a 2x2 matrix
    const data = [_]f64{ 1, 2, 3, 4 };
    var matrix = try linalg.Matrix(f64).initFromArray(allocator, 2, 2, &data);
    defer matrix.deinit();

    // Calculate determinant
    const det = try matrix.determinant();
    std.debug.print("Determinant: {d}\n", .{det});

    // Calculate inverse
    var inv = try matrix.inverse();
    defer inv.deinit();
}
```

#### Using Statistics

```zig
const std = @import("std");
const stats = @import("zboost").math.stats;

pub fn main() void {
    const data = [_]f64{ 10, 20, 30, 40, 50 };

    // Calculate basic statistics
    const mean = stats.Descriptive.mean(&data);
    const variance = stats.Descriptive.variance(&data);
    const stddev = stats.Descriptive.stdDev(&data);

    std.debug.print("Mean: {d}\n", .{mean});
    std.debug.print("Variance: {d}\n", .{variance});
    std.debug.print("Standard Deviation: {d}\n", .{stddev});
}
```

#### Using Network Tools

```zig
const std = @import("std");
const network = @import("zboost").network;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Create and initialize socket
    var socket = try network.Socket.initTcp(allocator);
    defer socket.deinit();

    // Build HTTP request
    var request = try network.HttpRequest.get(allocator, "/api/data");
    defer request.deinit();

    try request.setHeader("User-Agent", "ZBoost/1.0");

    const raw_request = try request.build("example.com");
    defer allocator.free(raw_request);
}
```

### Troubleshooting

#### Common Issues

1. **Zig not found**: Ensure Zig is installed and added to PATH
   ```bash
   export PATH="$HOME/.local/zig:$PATH"  # or wherever Zig is installed
   ```

2. **Build errors**: Clean and rebuild
   ```bash
   rm -rf zig-cache zig-out
   zig build
   ```

3. **Test failures**: Check Zig version compatibility
   ```bash
   zig version
   ```

### Development Setup

If you want to contribute to ZBoost:

```bash
# Clone the repository
git clone https://github.com/abdiel-sobreira/zboost.git
cd zboost

# Make your changes
# Test your changes
zig build test

# Run the complete test suite
zig test src/math/linalg.zig
zig test src/math/stats.zig
zig test src/network.zig
```

### Support and Documentation

- **Issue Tracker**: [GitHub Issues](https://github.com/abdiel-sobreira/zboost/issues)
- **Zig Documentation**: [https://ziglang.org/documentation](https://ziglang.org/documentation)
- **Standard Library**: [https://ziglang.org/learn/](https://ziglang.org/learn/)

### License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.