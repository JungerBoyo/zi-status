const c = @cImport({
    @cInclude("X11/Xlib.h");
});

const std = @import("std");

const config = @import("config.zig");

const Date      = @import("Date.zig");
const Bat       = @import("Bat.zig");
const Mixer     = @import("Mixer.zig");
const Net       = @import("Net.zig");
const Weather   = @import("Weather.zig");
const Mem       = @import("Mem.zig");

const ZiStatus = struct {
    // display
    x_dpy: *c.Display,

    // handles
    mixer: ?Mixer,
    net: ?Net,
    weather: ?Weather,

    // state
    date: Date,
    bat: ?Bat,     
    mem: ?Mem,
    mixer_state: Mixer.State,
    net_state: ?Net.State,
    weather_state: ?Weather.State,

    update_counters: [6]u64 = .{0} ** 6,

    timezone_offset: i64,

    const ID_DATE_TIME  = 0;
    const ID_BAT        = 1;
    const ID_MIXER      = 2;
    const ID_NET        = 3;
    const ID_WEATHER    = 4;
    const ID_MEM        = 5;

    const TIME_FMT = if (config.TIME_INCLUDE_SECONDS)
        "[{s} {s} {:0>2}:{:0>2}:{:0>2}]" 
    else 
        "[{s} {s} {:0>2}:{:0>2}]";

    const NET_FMT = if (config.NET_INCLUDE_IP_ADDRESS) 
        "[{s}/{} {d:.2}Mb/s | {s} {s} {}%]"
    else 
        "[{d:.2}Mb/s | {s} {s} {}%]";

    const DATE_FMT      = "[{s} {} {s} {}]";
    const BAT_FMT       = "[{s}~{}%{s}]";
    const MEM_FMT       = "[{s}~{}MB]";
    const SOUND_FMT     = "[{s}{}%]";
    const WEATHER_FMT   = "[{s}{}({}) {s}{}% {s}{:0>2}:{:0>2}]";    

    pub fn init(x_dpy: *c.Display, timezone_offset_in_ms: i64) anyerror!ZiStatus {
        return ZiStatus {
            .x_dpy = x_dpy,

            .mixer = if (config.SOUND_ENABLE)
                    try Mixer.init(config.SOUND_CARD, config.SOUND_MIXER)
                else 
                    null,
            .net = if (config.NET_ENABLE) 
                    try Net.init()
                else 
                    null,
            .weather = if (config.WEATHER_ENABLE)
                    try Weather.init()
                else 
                    null,
            .date = Date.init(std.time.milliTimestamp() + timezone_offset_in_ms),
            .bat = if (config.BAT_ENABLE)
                    try Bat.init(config.BAT_UEVENT_PATH)
                else    
                    null,
            .mem = if (config.MEM_ENABLE)
                    try Mem.init(config.MEM_INFO_PATH)
                else 
                    null,
            .mixer_state = Mixer.State{},
            .net_state = null,
            .weather_state = null,
            .timezone_offset = timezone_offset_in_ms,
        };
    }

    pub fn tryUpdate(self: *ZiStatus) void {
        if (config.TIME_ENABLE or config.DATE_ENABLE) {
            const counter = &self.update_counters[ID_DATE_TIME];
            if (counter.* == 0) {
                self.date = Date.init(std.time.milliTimestamp() + self.timezone_offset);
            } 
            if (counter.* == config.DATE_TIME_UPDATE_PERIOD) {
                counter.* = 0;
            } else {
                counter.* += 1;
            }
        }

        if (config.BAT_ENABLE) {
            const counter = &self.update_counters[ID_BAT];
            if (counter.* == 0) {
                self.bat = Bat.init(config.BAT_UEVENT_PATH) catch null;
            } 
            if (counter.* == config.BAT_UPDATE_PERIOD) {
                counter.* = 0;
            } else {
                counter.* += 1;
            }
        }

        if (config.SOUND_ENABLE) {
            const counter = &self.update_counters[ID_MIXER];
            if (counter.* == 0) {
                if (self.mixer) |*mixer| {
                    self.mixer_state = mixer.state();
                }
            } 
            if (counter.* == config.SOUND_UPDATE_PERIOD) {
                counter.* = 0;
            } else {
                counter.* += 1;
            }
        }

        if (config.NET_ENABLE) {
            const counter = &self.update_counters[ID_NET];
            if (counter.* == 0) {
                if (self.net) |*net| {
                    self.net_state = net.state();
                } else {
                    self.net = Net.init() catch null;
                    if (self.net) |*net| {
                        self.net_state = net.state();
                    }
                }
            } 
            if (counter.* == config.NET_UPDATE_PERIOD) {
                counter.* = 0;
            } else {
                counter.* += 1;
            }
        }

        if (config.MEM_ENABLE) {
            const counter = &self.update_counters[ID_MEM];
            if (counter.* == 0) {
                self.mem = Mem.init(config.MEM_INFO_PATH) catch null;
            } 
            if (counter.* == config.MEM_UPDATE_PERIOD) {
                counter.* = 0;
            } else {
                counter.* += 1;
            }
        }

        if (config.WEATHER_ENABLE) {
            const counter = &self.update_counters[ID_WEATHER];
            if (counter.* == 0) {
                if (self.weather) |*weather| {
                    if (weather.stateReceiving()) {
                        return;
                    } else if (weather.stateAvailable()) {
                        self.weather_state = weather.state(self.timezone_offset) catch null;
                    } else {
                        weather.stateRequest();
                        return;
                    }
                }
            } 
            if (counter.* == config.WEATHER_UPDATE_PERIOD) {
                counter.* = 0;
            } else {
                counter.* += 1;
            }
        }
    }

    fn trySetStatusStringWeather(self: *ZiStatus, buf: []u8) usize {
        if (config.WEATHER_ENABLE) {
            if (self.weather_state) |*weather_state| {
                const status = std.fmt.bufPrint(buf, WEATHER_FMT, .{
                    blk: {
                        if (weather_state.temperature >= config.WEATHER_TEMP_HOT_THRESHOLD) {
                            break :blk config.WEATHER_TEMP_HIGH_TAG;
                        } else if (weather_state.temperature <= config.WEATHER_TEMP_COLD_THRESHOLD) {
                            break :blk config.WEATHER_TEMP_LOW_TAG;
                        } else {
                            break :blk config.WEATHER_TEMP_MEDIUM_TAG;
                        }
                    } ,
                    weather_state.temperature,
                    weather_state.temperature_feels_like,
                    config.WEATHER_HUMIDITY_TAG,
                    weather_state.humidity,
                    config.WEATHER_SUNSET_TAG,
                    weather_state.sunset.hour,
                    weather_state.sunset.minute,
                }) catch unreachable;
                return status.len;
            }
        }
        return 0;
    }

    fn trySetStatusStringNet(self: *ZiStatus, buf: []u8) usize {
        if (config.NET_ENABLE) {
            if (self.net_state) |*net_state| {
                const status = std.fmt.bufPrint(buf, NET_FMT, 
                if (config.NET_INCLUDE_IP_ADDRESS)
                    .{
                        net_state.ipv4[0..net_state.ipv4_len],
                        net_state.mask,
                        net_state.connection_speed,
                        switch (net_state.connection_type) {
                            .wifi => config.NET_WIFI_TAG,
                            .ethernet => config.NET_ETHERNET_TAG,
                            .unknown => config.NET_UNKNOWN_TAG,
                        },
                        net_state.SSID[0..net_state.SSID_len],
                        net_state.signal_strength,
                    } 
                else 
                    .{
                        net_state.connection_speed,
                        switch (net_state.connection_type) {
                            .wifi => config.NET_WIFI_TAG,
                            .ethernet => config.NET_ETHERNET_TAG,
                            .unknown => config.NET_UNKNOWN_TAG,
                        },
                        net_state.SSID[0..net_state.SSID_len],
                        net_state.signal_strength,
                    }
                ) catch unreachable;
                return status.len;
            }
        }
        return 0;
    }

    fn trySetStatusStringSound(self: *ZiStatus, buf: []u8) usize {
        if (config.SOUND_ENABLE) {
            const status = std.fmt.bufPrint(buf, SOUND_FMT, .{
                blk: {
                    if (self.mixer_state.is_unmuted) {
                        if (self.mixer_state.volume <= 25) {
                            break :blk config.SOUND_LOW_TAG; 
                        } else if (self.mixer_state.volume >= 75) {
                            break :blk config.SOUND_HIGH_TAG; 
                        } else {
                            break :blk config.SOUND_MEDIUM_TAG;
                        }
                    } else {
                        break :blk config.SOUND_MUTE_TAG;
                    }
                },
                self.mixer_state.volume,
            }) catch unreachable;
            return status.len;
        }
        return 0;
    }

    fn trySetStatusStringBat(self: *ZiStatus, buf: []u8) usize {
        if (config.BAT_ENABLE) {
            if (self.bat) |bat| {
                const status = std.fmt.bufPrint(buf, BAT_FMT, .{
                    if (bat.capacity <= 20) 
                        config.BAT_LOW_TAG 
                    else 
                        config.BAT_HIGH_TAG,
                    bat.capacity,
                    switch (bat.state) {
                        .charging    => config.BAT_STATE_CHARGING_TAG,
                        .discharging => config.BAT_STATE_DISCHARGING_TAG,
                        .unknown     => config.BAT_STATE_UNKNOWN_TAG,
                    },
                }) catch unreachable;
                return status.len;
            }
        }
        return 0;
    }

    fn trySetStatusStringDate(self: *ZiStatus, buf: []u8) usize {
        if (config.DATE_ENABLE) {
            const status = std.fmt.bufPrint(buf, DATE_FMT, .{
                config.DATE_TAG,
                self.date.day_of_month,
                self.date.month,
                self.date.year,
            }) catch unreachable;
            return status.len;
        }
        return 0;
    }

    fn trySetStatusStringTime(self: *ZiStatus, buf: []u8) usize {
        if (config.TIME_ENABLE) {
            const status = std.fmt.bufPrint(buf, TIME_FMT, 
            if (config.TIME_INCLUDE_SECONDS)
                .{
                    config.TIME_TAG,
                    self.date.day_of_week,
                    self.date.hour,
                    self.date.minute,
                    self.date.second,
                }
            else 
                .{
                    config.TIME_TAG,
                    self.date.day_of_week,
                    self.date.hour,
                    self.date.minute,
                }
            ) catch unreachable;
            return status.len;
        }
        return 0;
    } 

    fn trySetStatusStringMem(self: *ZiStatus, buf: []u8) usize {
        if (config.MEM_ENABLE) {
            if (self.mem) |mem| {
                const status = std.fmt.bufPrint(buf, MEM_FMT, .{
                    config.MEM_TAG,
                    mem.ram_usage_MB
                }) catch unreachable;
                return status.len;
            }
        }
        return 0;
    }

    fn trySetStatusStringMousePos(self: *ZiStatus, buf: []u8) usize {
        if (config.MOUSE_POS_ENABLE) {
            var focused_x_win: c.Window = undefined; 
            var revert_to: c_int = 0;

            _ = c.XGetInputFocus(self.x_dpy, &focused_x_win, &revert_to);

            var dummy: c.Window = undefined;
            var mask_return: c_uint = 0;
            var win_mouse_x: c_int = 0;
            var win_mouse_y: c_int = 0;
            var root_mouse_x: c_int = 0;
            var root_mouse_y: c_int = 0;
            _ = c.XQueryPointer(
                self.x_dpy, focused_x_win, &dummy, &dummy, 
                &root_mouse_x, &root_mouse_y, 
                &win_mouse_x, &win_mouse_y,
                &mask_return
            );

            const status = std.fmt.bufPrint(
                buf, 
                "[{s}({:.2}, {:.2})]", 
                .{
                    config.MOUSE_POS_TAG,
                    root_mouse_x, 
                    root_mouse_y,
                }
            ) catch unreachable;

            return status.len;
        }

        return 0;
    }

    pub fn setStatusString(self: *ZiStatus, buf: []u8) void {
        var status_len: usize = 0;

        var i: i32 = @intCast(i32, config.FMT_ORDER.len) - 1;
        while (i >= 0) : (i -= 1) {
            const len_to_add = switch (config.FMT_ORDER[@intCast(usize, i)]) {
                .time       => self.trySetStatusStringTime(buf[status_len..]),
                .date       => self.trySetStatusStringDate(buf[status_len..]),
                .bat        => self.trySetStatusStringBat(buf[status_len..]),
                .mem        => self.trySetStatusStringMem(buf[status_len..]),
                .sound      => self.trySetStatusStringSound(buf[status_len..]),
                .net        => self.trySetStatusStringNet(buf[status_len..]),
                .weather    => self.trySetStatusStringWeather(buf[status_len..]),    
                .mouse_pos  => self.trySetStatusStringMousePos(buf[status_len..]),
            };

            status_len += len_to_add;

            if (len_to_add != 0 and i > 0) {
                buf[status_len] = ' ';
                status_len += 1;
            }
        }

        buf[status_len] = 0; // delim with 0 (zig str => c str)
    }

    pub fn deinit(self: *ZiStatus) void {
        self.mixer.deinit();
        self.net.deinit();
        self.weather.deinit();
    }
};

pub fn main() !void {
    // eg
    // timedatectl | grep zone | awk '{print$5}' | tr -d "\)"
    var arg_iter = std.process.args();
    _ = arg_iter.next(); // ignore first argument (exe name)
    const timezone_arg = arg_iter.next();
    arg_iter.deinit();

    var timezone_offset_in_ms = parseTimezone(timezone_arg) catch {
        std.log.err("zi-status: zone argument must be in format (+/-)NN00 where N is a digit[0-9]", .{});     
        return;
    };

    var x_dpy = c.XOpenDisplay(null);
    if (x_dpy == null) {
        std.log.err("zi-status: failed open X display.\n", .{});
        return;
    }
    defer _ = c.XCloseDisplay(x_dpy);

    const sleep_time: u64 = config.SLEEP_PERIOD * 1_000_000_000; // 1 [s]

    std.time.sleep(config.SLEEP_PERIODS_BEFORE_INIT * sleep_time);

    var zi_status = ZiStatus.init(x_dpy.?, timezone_offset_in_ms) catch |err| {
        switch (err) {
            error.MixerOpenFailure =>{
                std.log.err("zi-status: failed to open a mixer", .{});
            }, 
            error.MixerAttachFailure => {
                std.log.err("zi-status: failed to attach a mixer to card device", .{});
            },
            error.MixerSelemRegisterFailure => {
                std.log.err("zi-status: failed to register element class to the mixer", .{});
            },
            error.MixerLoadFailure=> {
                std.log.err("zi-status: failed to load a mixer elements", .{});
            },
            error.CantReadVolumeRange => {
                std.log.err("zi-status: failed to query min/max volume range", .{});
            },
            error.CantConnectToNetworkManager => {
                std.log.err("zi-status: failed to connect to NetworkManager", .{});
            },
            error.CurlInitFailed => {
                std.log.err("zi-status: failed to init weather service (curl init failed)", .{});
            },
            error.BatFileOpenFailure => {
                std.log.err("zi-status: failed to open file {s}", .{config.BAT_UEVENT_PATH});
            },
            error.BatStreamTooLong => {
                std.log.err("zi-status: failed to parse file {s}, some line exceeds 128 bytes", .{config.BAT_UEVENT_PATH});
            },
            error.FailedToParsePowerSupplyCapacity => {
                std.log.err("zi-status: failed to parse file {s}, failed to parse one of arguments to int", .{config.BAT_UEVENT_PATH});
            },
            error.MemFileOpenFailure => {
                std.log.err("zi-status: failed to open file {s}", .{config.MEM_INFO_PATH});
            },
            error.FailedToParseTotalMemArg => {
                std.log.err("zi-status: faied to parse total mem from file {s}",.{config.MEM_INFO_PATH});
            },
            error.FailedToParseAvailableMemArg => {
                std.log.err("zi-status: faied to parse available mem from file {s}",.{config.MEM_INFO_PATH});
            },
            else => {}
        }
        return err;
    };
    defer zi_status.deinit();

    while (true) {
        zi_status.tryUpdate();

        var buf: [256]u8 = undefined;
        zi_status.setStatusString(&buf);

        _ = c.XStoreName(x_dpy, c.DefaultRootWindow(x_dpy), &buf);
        _ = c.XSync(x_dpy, 0);

        std.time.sleep(sleep_time);
    }
}

const ParseTimezoneError = error {
    WrongArgFormat
};
// returns timezone in miliseconds
fn parseTimezone(timezone_arg: ?[:0]const u8) ParseTimezoneError!i64 {
    if (timezone_arg != null) {
        const polarity_char = timezone_arg.?[0];
        var polarity: i8 = 0;
        if (polarity_char == '-') {
            polarity = -1;
        } else if (polarity_char == '+') {
            polarity = 1;
        } else {
            return error.WrongArgFormat;
        }

        const tens_char = timezone_arg.?[1];
        if (tens_char < '0' or tens_char > '9') {
            return error.WrongArgFormat;
        } 
        const tens: i8 = @intCast(i8, tens_char) - 48;
        
        const units_char = timezone_arg.?[2];
        if (units_char < '0' or units_char > '9') {
            return error.WrongArgFormat;
        } 
        const units: i8 = @intCast(i8, units_char) - 48;

        return @intCast(i64, polarity * (10 * tens + units)) * 60 * 60 * 1000;
    }

    return 0;
}
