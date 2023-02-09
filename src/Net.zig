const std = @import("std");

const c = @cImport({
    @cInclude("NetworkManager.h");
    @cInclude("glib.h");
});

const Self = @This();

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

pub fn init() NMError!Self {
    var err: [*c]c.GError = 0x0;
    // connect to network manager
    var client = c.nm_client_new(0x0, &err);
    if (client == null) {
        std.log.err("zi-status:(NetworkManager) [{}] {s}", .{err.*.code, err.*.message});
        c.g_error_free(err);
        return error.CantConnectToNetworkManager;
    }
    return Self {
        .client = client.?
    };
}

pub fn state(self: *Self) State {
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

pub fn deinit(self: *Self) void {
    c.g_object_unref(self.client);
}