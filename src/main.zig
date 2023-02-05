const c = @cImport({
    @cInclude("X11/Xlib.h");
    @cInclude("alsa/asoundlib.h");
});

const std = @import("std");

const Date = struct {
    hour: u8,
    minute: u8,
    second: u8,
    day_of_week: []const u8,
    day_of_month: u8,
    month: []const u8,  
    year: u16,

    pub fn init(timestamp_ms: i64) Date {
        const sec = std.time.epoch.EpochSeconds{ 
            .secs = @intCast(u64, @divTrunc(timestamp_ms, 1000))
        };
        const day_seconds = sec.getDaySeconds();
        const day = sec.getEpochDay();
        const year_and_day = day.calculateYearDay();
        const month_and_day = year_and_day.calculateMonthDay();

        return Date{
            .hour = @as(u8, day_seconds.getHoursIntoDay()),
            .minute = @as(u8, day_seconds.getMinutesIntoHour()), 
            .second = @as(u8, day_seconds.getSecondsIntoMinute()),
            .day_of_week = switch((day.day + 3) % 7) { // 1 oct 1970 was thursday
                0 => "Mon",
                1 => "Tue",
                2 => "Wed",
                3 => "Thu",
                4 => "Fri",
                5 => "Sat",
                6 => "Sun",
                else => "Err"
            },
            .day_of_month = @as(u8, month_and_day.day_index + 1),
            .month = switch(month_and_day.month) {
                .jan => "Jan",
                .feb => "Feb",
                .mar => "Mar",
                .apr => "Apr",
                .may => "May",
                .jun => "Jun",
                .jul => "Jul",
                .aug => "Aug",
                .sep => "Sep",
                .oct => "Oct",
                .nov => "Nov",
                .dec => "Dec",
            },
            .year = year_and_day.year
        };
    }
};

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

const Bat = struct {
    pub const BatReadError = error {
        FileOpenFailure,
        StreamTooLong,
        ParseIntFailure,
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

    pub fn init(bat_uevent_path: []const u8) BatReadError!Bat {
        const file = std.fs.openFileAbsolute(
            bat_uevent_path, 
            .{ .mode = .read_only }
        ) catch {
            return error.FileOpenFailure;
        };
        defer file.close();

        const file_reader = file.reader();

        var result = Bat{};
    
        var buf: [128]u8 = undefined;
        while (file_reader.readUntilDelimiterOrEof(&buf, '\n') catch { return error.StreamTooLong; }) |line| {
            if (std.mem.eql(u8, CAPACITY_ARG, line[0..CAPACITY_ARG.len])) {
                result.capacity = std.fmt.parseInt(
                    u8, 
                    line[(CAPACITY_ARG.len)..(line.len)], 
                    10
                ) catch {
                    return error.ParseIntFailure;
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
};

const Mixer = struct {
    handle: ?*c.snd_mixer_t = null,
    card: [:0]const u8,
    elem: ?*c.snd_mixer_elem_t = null,
    vol_max: c_long = 0,
    vol_min: c_long = 0,

    pub const ALSAError = error {
        MixerOpenFailure,
        MixerAttachFailure,
        MixerSelemRegisterFailure,
        MixerLoadFailure,
        CantReadVolumeRange,
    };

    pub fn init(card: [:0]const u8, selem_name: [:0]const u8) ALSAError!Mixer {
        var handle: ?*c.snd_mixer_t = null;
        if (c.snd_mixer_open(&handle, 0) != 0) {
            return error.MixerOpenFailure;            
        }
        if (c.snd_mixer_attach(handle, card.ptr) != 0) {
            return error.MixerAttachFailure;
        }
        if (c.snd_mixer_selem_register(handle, 0x0, 0x0) != 0) {
            return error.MixerSelemRegisterFailure;
        }
        if (c.snd_mixer_load(handle) != 0) {
            return error.MixerLoadFailure;
        }

        var sid: ?*c.snd_mixer_selem_id_t = null;
        _ = c.snd_mixer_selem_id_malloc(&sid);
        defer c.snd_mixer_selem_id_free(sid);

        c.snd_mixer_selem_id_set_index(sid, 0);
        c.snd_mixer_selem_id_set_name(sid, selem_name.ptr);
        var elem = c.snd_mixer_find_selem(handle, sid);

        var vol_min: c_long = 0;
        var vol_max: c_long = 0;
        if (c.snd_mixer_selem_get_playback_volume_range(elem, &vol_min, &vol_max) != 0) {
            return error.CantReadVolumeRange;
        }

        return Mixer{
            .handle = handle,
            .card = card,
            .elem = elem,
            .vol_min = vol_min,
            .vol_max = vol_max,
        };
    }

    // returns volume level in %
    pub fn getVolume(self: *Mixer) u8 {
        _ = c.snd_mixer_handle_events(self.handle);

        var vol_lhs: c_long = 0;
        _ = c.snd_mixer_selem_get_playback_volume(
            self.elem, 
            c.SND_MIXER_SCHN_SIDE_LEFT,
            &vol_lhs
        );
        
        var vol_rhs: c_long = 0;
        _ = c.snd_mixer_selem_get_playback_volume(
            self.elem, 
            c.SND_MIXER_SCHN_SIDE_LEFT,
            &vol_rhs
        );

        const vol_resolution = self.vol_max - self.vol_min;

        const vol = @divTrunc(vol_lhs + vol_rhs, 2);
        const vol_normalized = @divTrunc((100 * (vol - self.vol_min)), vol_resolution);

        return @intCast(u8, vol_normalized);
    }

    pub fn deinit(self: *Mixer) void {
        _ = c.snd_mixer_detach(self.handle, self.card.ptr);
        _ = c.snd_mixer_close(self.handle);
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

    const sleep_time: u64 = 1_000_000_000; // 1 [s]

    var mixer = Mixer.init("default", "Master") catch |err| {
        switch (err) {
            error.MixerOpenFailure =>{
                std.log.err("zi-status:(ALSA) failed to open a mixer", .{});
            }, 
            error.MixerAttachFailure => {
                std.log.err("zi-status:(ALSA) failed to attach a mixer to card device", .{});
            },
            error.MixerSelemRegisterFailure => {
                std.log.err("zi-status:(ALSA) failed to register element class to the mixer", .{});
            },
            error.MixerLoadFailure=> {
                std.log.err("zi-status:(ALSA) failed to load a mixer elements", .{});
            },
            error.CantReadVolumeRange => {
                std.log.err("zi-status:(ALSA) failed to query min/max volume range", .{});
            },
        }
        return;
    };
    defer mixer.deinit();
    
    while (true) {
        const date = Date.init(std.time.milliTimestamp() + timezone_offset_in_ms);
        const bat = Bat.init("/sys/class/power_supply/BAT0/uevent") catch |err| {
            switch (err) {
                error.FileOpenFailure => {
                    std.log.err("zi-status: failed to open file /sys/class/power_supply/BAT0/uevent", .{});
                },
                error.StreamTooLong => {
                    std.log.err("zi-status: failed to parse file /sys/class/power_supply/BAT0/uevent, some line exceeds 128 bytes", .{});
                },
                error.ParseIntFailure => {
                    std.log.err("zi-status: failed to parse file /sys/class/power_supply/BAT0/uevent, failed to parse one of arguments to int", .{});
                }
            }
            return;
        };
        const vol = mixer.getVolume();

        var buf: [128]u8 = undefined;
        const status = std.fmt.bufPrint(
            &buf,
            "[{s}{}%] [{s}~{}%{s}] [📅 {} {s} {}] [🕒 {s} {}:{}:{}]", 
            .{
                blk: {
                    if (vol <= 25) {
                        break :blk "🔈";
                    } else if (vol >= 75) {
                        break :blk "🔊";
                    } else {
                        break :blk "🔉";
                    }
                },
                vol,
                if (bat.capacity <= 20) "🪫" else "🔋",
                bat.capacity,
                switch (bat.state) {
                    .charging    => "😀",
                    .discharging => "🫠",
                    .unknown     => "🧐",
                },
                date.day_of_month,
                date.month,
                date.year,
                date.day_of_week,
                date.hour,
                date.minute,
                date.second,
            }
        ) catch unreachable;
        
        buf[status.len] = 0; // delim with 0 (zig str => c str)

        _ = c.XStoreName(x_dpy, c.DefaultRootWindow(x_dpy), &buf);
        _ = c.XSync(x_dpy, 0);

        std.time.sleep(sleep_time);
    }
}