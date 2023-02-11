const std = @import("std");

const Self = @This();

pub const MemReadError = error {
    MemFileOpenFailure,
    FailedToParseTotalMemArg,
    FailedToParseAvailableMemArg,
};

const AVAILABLE_MEM_ARG = "MemAvailable:";
const TOTAL_MEM_ARG = "MemTotal:";

ram_usage_MB: u32 = 0, // [%]

pub fn init(meminfo_path: []const u8) MemReadError!Self {
    const file = std.fs.openFileAbsolute(
        meminfo_path, 
        .{ .mode = .read_only }
    ) catch {
        return error.MemFileOpenFailure;
    };
    defer file.close();

    const file_reader = file.reader();

    var total_mem_MB: u32 = 0;
    var available_mem_MB: u32 = 0;

    var buf: [128]u8 = undefined;
    while (file_reader.readUntilDelimiterOrEof(&buf, '\n') catch unreachable) |line| {
        const equals_total_mem_arg = std.mem.eql(u8, TOTAL_MEM_ARG, line[0..TOTAL_MEM_ARG.len]);
        const equals_available_mem_arg = std.mem.eql(u8, AVAILABLE_MEM_ARG, line[0..AVAILABLE_MEM_ARG.len]);
        if (!equals_total_mem_arg and !equals_available_mem_arg) {
            continue;
        }

        var b: usize = if(equals_total_mem_arg) TOTAL_MEM_ARG.len else AVAILABLE_MEM_ARG.len; 
        while (b < line.len and line[b] == ' ') : (b += 1) {}
        var e: usize = b + 1;
        while (e < line.len and line[e] != ' ') : (e += 1) {}

        if(equals_total_mem_arg) {
            total_mem_MB = std.fmt.parseInt(u32, line[b..e], 10) catch {
                return error.FailedToParseTotalMemArg;
            };
            total_mem_MB /= 1000;
        } else {
            available_mem_MB = std.fmt.parseInt(u32, line[b..e], 10) catch {
                return error.FailedToParseAvailableMemArg;
            };
            available_mem_MB /= 1000;
            break;
        }
    }

    return Self {
        .ram_usage_MB = total_mem_MB - available_mem_MB
    };
}