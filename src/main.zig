const c = @cImport({
    @cInclude("X11/Xlib.h");
    @cInclude("alsa/asoundlib.h");
    @cInclude("NetworkManager.h");
    @cInclude("glib.h");
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
};

const Net = struct {
    pub const NMError = error {
        CantConnectToNetworkManager,
    };

    pub const ConnectionType = enum(u8) {
        wifi,
        ethernet,
        unknown,
    };

    pub const State = struct {
        connection_speed: f32 = 0.0, // in Mb/s
        connection_type: ConnectionType = .unknown,
        signal_strength: u8 = 0,
        SSID: [63]u8 = .{0} ** 63,
        SSID_len: u8 = 0,
        ipv4: [15]u8 = .{0} ** 15,
        ipv4_len: u8 = 0,
        mask: u8 = 0,
    };

    client: *c.NMClient,

    pub fn init() NMError!Net {
        var err: [*c]c.GError = 0x0;
        // connect to network manager
        var client = c.nm_client_new(0x0, &err);
        if (client == null) {
            std.log.err("zi-status:(NetworkManager) [{}] {s}", .{err.*.code, err.*.message});
            c.g_error_free(err);
            return error.CantConnectToNetworkManager;
        }
        return Net {
            .client = client.?
        };
    }

    pub fn state(self: *Net) State {
        // list devices
        const devices = c.nm_client_get_devices(self.client);

        var i: usize = 0;
        while (i < devices.*.len) : (i += 1) {
            var device = @ptrCast(*c.NMDevice, devices.*.pdata[i]);
            const active_connection = c.nm_device_get_active_connection(device); 
            if (active_connection != null) { // is connection on <device> active
                var result = State{};

                // query dev type wifi or ethernet
                var device_type = c.nm_device_get_device_type(device); 
                
                // get ip
                const ipv4_config = c.nm_device_get_ip4_config(device);
                const ip_arr = c.nm_ip_config_get_addresses(ipv4_config);
                const ip_address = @ptrCast(*c.NMIPAddress, ip_arr.*.pdata[0]);
                const mask_prefix = c.nm_ip_address_get_prefix(ip_address);
                const address = c.nm_ip_address_get_address(ip_address);
                const address_len = std.mem.len(address);

                result.mask = @intCast(u8, mask_prefix);
                std.mem.copy( // copy with \0 included
                    u8,
                    result.ipv4[0..address_len], 
                    address[0..address_len]
                );
                result.ipv4_len = @intCast(u8, address_len);

                if (device_type == c.NM_DEVICE_TYPE_ETHERNET) {
                    const ethernet_device = @ptrCast(?*c.NMDeviceEthernet, device);
                    const speed_mbs = c.nm_device_ethernet_get_speed(ethernet_device);

                    result.connection_type = .ethernet;
                    result.connection_speed = @intToFloat(f32, speed_mbs);

                    return result;
                } else if (device_type == c.NM_DEVICE_TYPE_WIFI) {
                    const wifi_device = @ptrCast(?*c.NMDeviceWifi, device);
                    const access_point = c.nm_device_wifi_get_active_access_point(wifi_device);
                    const ssid = c.nm_access_point_get_ssid(access_point);
                    const ssid_utf8 = c.nm_utils_ssid_to_utf8(
                        @ptrCast([*c]const c.guint8, c.g_bytes_get_data(ssid, 0x0)), 
                        c.g_bytes_get_size(ssid)
                    );
                    const ssid_utf8_len = std.mem.len(ssid_utf8);
                    const signal_strength = c.nm_access_point_get_strength(access_point);
                    const max_bitrate = c.nm_access_point_get_max_bitrate(access_point);

                    result.connection_type = .wifi;
                    result.connection_speed =  (@intToFloat(f32, signal_strength) / 100.0) * @intToFloat(f32, max_bitrate/1000);
                    result.signal_strength = @intCast(u8, signal_strength);
                    std.mem.copy(
                        u8,
                        result.SSID[0..ssid_utf8_len], 
                        ssid_utf8[0..ssid_utf8_len]
                    );
                    result.SSID_len = @intCast(u8, ssid_utf8_len);
                    
                    return result;
                }

            }
        }
        return State{};
    }

    pub fn deinit(self: *Net) void {
        c.g_object_unref(self.client);
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
        }
        return;
    };
    defer mixer.deinit();

    var net = Net.init() catch |err| {
        switch (err) {
            error.CantConnectToNetworkManager => {
                std.log.err("zi-status: failed to connect to NetworkManager", .{});
                return;
            }
        }
    };
    defer net.deinit();

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
                error.FailedToParsePowerSupplyCapacity => {
                    std.log.err("zi-status: failed to parse file /sys/class/power_supply/BAT0/uevent, failed to parse one of arguments to int", .{});
                }
            }
            return;
        };
        const vol = mixer.getVolume();
        const net_state = net.state();
        // 🛜
        // 🪱

        var buf: [128]u8 = undefined;
        const status = std.fmt.bufPrint(
            &buf,
            "[{s}/{} {d:.2}Mb/s | {s} {s} {}%] [{s}{}%] [{s}~{}%{s}] [📅 {} {s} {}] [🕒 {s} {:0>2}:{:0>2}:{:0>2}]",
            .{
                net_state.ipv4[0..net_state.ipv4_len],
                net_state.mask,
                net_state.connection_speed,
                if (net_state.connection_type == .wifi) "🛜" else "🪱",
                net_state.SSID[0..net_state.SSID_len],
                net_state.signal_strength,
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