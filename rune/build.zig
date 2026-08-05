const std = @import("std");

/// Parse version from build.zig.zon at comptime — single source of truth.
const zon_content = @embedFile("build.zig.zon");
const VERSION = blk: {
    const marker = ".version = \"";
    if (std.mem.indexOf(u8, zon_content, marker)) |start| {
        const after = zon_content[start + marker.len ..];
        if (std.mem.indexOf(u8, after, "\"")) |end| {
            break :blk after[0..end];
        }
    }
    break :blk "0.0.0";
};

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Inject version from build.zig.zon at compile time
    const options = b.addOptions();
    options.addOption([]const u8, "VERSION", VERSION);

    const mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    mod.addOptions("build_options", options);

    const exe = b.addExecutable(.{
        .name = "rune",
        .root_module = mod,
    });

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the rune compiler");
    run_step.dependOn(&run_cmd.step);

    // Unit tests (inline Zig test blocks)
    const unit_tests = b.addTest(.{
        .root_module = mod,
    });

    const run_unit_tests = b.addRunArtifact(unit_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_unit_tests.step);

    // Colocated test files (diff_test, fields_test, codegen_test)
    const colocated_mod = b.createModule(.{
        .root_source_file = b.path("src/tests.zig"),
        .target = target,
        .optimize = optimize,
    });
    colocated_mod.addOptions("build_options", options);
    const colocated_tests = b.addTest(.{
        .root_module = colocated_mod,
    });
    const run_colocated_tests = b.addRunArtifact(colocated_tests);
    test_step.dependOn(&run_colocated_tests.step);

    // ─── Golden Tests ────────────────────────────────────────────
    // Run all shell-based golden test suites via a single step.
    const golden_step = b.step("golden-tests", "Run all golden test suites (requires rune binary)");
    const run_golden = b.addRunArtifact(exe);
    run_golden.step.dependOn(b.getInstallStep());
    // The golden tests are shell scripts in tests/ — run them via bash
    const run_golden_sh = b.addSystemCommand(&.{ "bash", "-c", "cd .. && for t in rune/tests/test_*.sh; do echo \"Running $t...\"; bash \"$t\" || exit 1; done" });
    run_golden_sh.step.dependOn(b.getInstallStep());
    golden_step.dependOn(&run_golden_sh.step);

    // ─── Benchmark ────────────────────────────────────────────────
    const bench_exe = b.addExecutable(.{
        .name = "bench",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/bench.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    const run_bench = b.addRunArtifact(bench_exe);
    run_bench.step.dependOn(b.getInstallStep());
    if (b.args) |bench_args| {
        run_bench.addArgs(bench_args);
    }

    const bench_step = b.step("bench", "Run benchmark (bench/bench.zig [file] [iterations])");
    bench_step.dependOn(&run_bench.step);

    // ─── Fuzzing ───────────────────────────────────────────────────
    const fuzz_exe = b.addExecutable(.{
        .name = "fuzz",
        .root_module = b.createModule(.{
            .root_source_file = b.path("fuzz.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    const run_fuzz = b.addRunArtifact(fuzz_exe);
    if (b.args) |fuzz_args| {
        run_fuzz.addArgs(fuzz_args);
    }

    const fuzz_step = b.step("fuzz", "Run fuzzing (fuzz <target> <corpus_dir>)");
    fuzz_step.dependOn(&run_fuzz.step);
}
