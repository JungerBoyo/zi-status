const std = @import("std");
const Date = @import("Date.zig");
const config = @import("config.zig");

const c = @cImport({
    @cInclude("curl/curl.h");
});

const Self = @This();

pub const CurlError = error {
    CurlInitFailed,
    CurlRequestHandleInitFailed,
};

pub const State = struct {
    temperature: i8, // in 'C
    temperature_feels_like: i8,
    humidity: u8,
    sunset: Date,
};

const InternalState = struct {
    temp: i8,
    feels_like: i8,
    humidity: u8,
    sunset: i64,
};

const HEADER: [:0]const u8 = "X-Api-Key: ";
const URL: [:0]const u8 = "https://api.api-ninjas.com/v1/weather?city=";

const RECIEVED_DATA_MAX_BUFFER_SIZE = 512;

curl_request_handle: *c.CURL,

received_data_buffer: [RECIEVED_DATA_MAX_BUFFER_SIZE]u8 = .{0} ** RECIEVED_DATA_MAX_BUFFER_SIZE,
received_data_buffer_size: u64 = 0,
received_data: bool = false,
receiving_data: bool = false,

fn receiveData(ptr: *anyopaque, size: u64, nmemb: u64, userdata: *anyopaque) callconv(.C) u64 {
    const self = @ptrCast(*Self, @alignCast(@alignOf(Self), userdata));

    const size_in_bytes = @min(RECIEVED_DATA_MAX_BUFFER_SIZE, size * nmemb);
    std.mem.copy(
        u8, 
        self.received_data_buffer[0..size_in_bytes], 
        @ptrCast([*]u8, ptr)[0..size_in_bytes]
    );

    @atomicStore(bool, &self.received_data, true, .Release);
    @atomicStore(bool, &self.receiving_data, false, .Release);
    
    self.received_data_buffer_size = size_in_bytes;
    return size_in_bytes;
}

pub fn init() CurlError!Self {
    if (c.curl_global_init(c.CURL_GLOBAL_SSL) != 0) {
       return error.CurlInitFailed;
    }

    const curl_handle = c.curl_easy_init();
    if (curl_handle == null) {
        return error.CurlRequestHandleInitFailed;
    }

    // set URL
    const url = URL ++ config.WEATHER_CITY;
    _ = c.curl_easy_setopt(curl_handle, c.CURLOPT_URL, @ptrCast([*c]const u8, url));

    // set HEADER
    const header = HEADER ++ config.WEATHER_X_API_KEY;
    var header_list: [*c]c.curl_slist = 0x0;
    header_list = c.curl_slist_append(header_list, @ptrCast([*c]const u8, header));
    // _ = c.curl_easy_setopt(curl_handle, c.CURLOPT_HEADER, @as(c_long, 1));
    _ = c.curl_easy_setopt(curl_handle, c.CURLOPT_HTTPHEADER, header_list);
    _ = c.curl_easy_setopt(curl_handle, c.CURLOPT_WRITEFUNCTION, receiveData);

    return Self{ .curl_request_handle = curl_handle.? };
}

pub fn stateRequest(self: *Self) void {
    @atomicStore(bool, &self.received_data, false, .Release);
    @atomicStore(bool, &self.receiving_data, true, .Release);
    _ = c.curl_easy_setopt(
        self.curl_request_handle, 
        c.CURLOPT_WRITEDATA, 
        @ptrCast(*anyopaque, self)
    );
    _ = c.curl_easy_perform(self.curl_request_handle);
}

pub fn stateReceiving(self: *Self) bool {
    return @atomicLoad(bool, &self.receiving_data, .Acquire);
}

pub fn stateAvailable(self: *Self) bool {
    return @atomicLoad(bool, &self.received_data, .Acquire);
}

pub fn state(self: *Self) !State {
    @atomicStore(bool, &self.received_data, false, .Release);
    var stream = std.json.TokenStream.init(self.received_data_buffer[0..self.received_data_buffer_size]);
    const internal_state = try std.json.parse(InternalState, &stream, .{ .ignore_unknown_fields = true });
    return State {
        .temperature = internal_state.temp,
        .temperature_feels_like = internal_state.feels_like,
        .humidity = internal_state.humidity,
        .sunset = Date.init(internal_state.sunset * 1000)
    };
}

pub fn deinit(self: *Self) void {
    c.curl_easy_cleanup(self.curl_request_handle);
    c.curl_global_cleanup();
}