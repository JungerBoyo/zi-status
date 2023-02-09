const std = @import("std");

const Self = @This();

pub const BatReadError = error {
    FileOpenFailure,
    StreamTooLong,
    FailedToParsePowerSupplyCapacity,
};

pub const State = enum(u8) {
    charging,
    discharging,
    unknown
};

capacity: u8 = 0, // [%]
state: State = .unknown,

const CAPACITY_ARG = "POWER_SUPPLY_CAPACITY=";
const CHARGING_ARG = "POWER_SUPPLY_STATUS=";

pub fn init(bat_uevent_path: []const u8) BatReadError!Self {
    const file = std.fs.openFileAbsolute(
        bat_uevent_path, 
        .{ .mode = .read_only }
    ) catch {
        return error.FileOpenFailure;
    };
    defer file.close();

    const file_reader = file.reader();

    var result = Self{};

    var buf: [128]u8 = undefined;
    while (file_reader.readUntilDelimiterOrEof(&buf, '\n') catch { return error.StreamTooLong; }) |line| {
        if (std.mem.eql(u8, CAPACITY_ARG, line[0..CAPACITY_ARG.len])) {
            result.capacity = std.fmt.parseInt(
                u8, 
                line[(CAPACITY_ARG.len)..(line.len)], 
                10
            ) catch {
                return error.FailedToParsePowerSupplyCapacity;
            };
        } else if (std.mem.eql(u8, CHARGING_ARG, line[0..CHARGING_ARG.len])) {
            if (std.mem.eql(u8, "Charging", line[(CHARGING_ARG.len)..(line.len)])) {
                result.state = .charging;
            } else if (std.mem.eql(u8, "Discharging", line[(CHARGING_ARG.len)..(line.len)])) {
                result.state = .discharging; 
            } 
        }
    }

    return result;
}