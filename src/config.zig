// GENERAL 
pub const SLEEP_PERIOD = 1; // [s]

// sometimes some modules don't "catch" instantly 
// so it is a dirty way of mitigating the issue
// (for now hopefully đĢ )
pub const SLEEP_PERIODS_BEFORE_INIT = 30;

// TIME CONFIG
pub const DATE_TIME_UPDATE_PERIOD = 1; // [SLEEP_PERIOD]
pub const TIME_ENABLE = true;
pub const TIME_INCLUDE_SECONDS = false;
pub const TIME_TAG = "đ";
pub const DATE_ENABLE = true;
pub const DATE_ORDER_INDEX = 1;
pub const DATE_TAG = "đ";

// BAT CONFIG
pub const BAT_ENABLE = true;
pub const BAT_UPDATE_PERIOD = 1; // [SLEEP_PERIOD]
pub const BAT_UEVENT_PATH = "/sys/class/power_supply/BAT0/uevent";
pub const BAT_LOW_TAG = "đĒĢ";
pub const BAT_HIGH_TAG = "đ";
pub const BAT_STATE_CHARGING_TAG = "đ";
pub const BAT_STATE_DISCHARGING_TAG = "đĢ ";
pub const BAT_STATE_UNKNOWN_TAG = "đ§";

// NET CONFIG
pub const NET_ENABLE = true;
pub const NET_INCLUDE_IP_ADDRESS = false;
pub const NET_UPDATE_PERIOD = 1; // [SLEEP_PERIOD]
pub const NET_WIFI_TAG = "đ";
pub const NET_ETHERNET_TAG = "đĒą";
pub const NET_UNKNOWN_TAG = "đ¤ˇ";

// SOUND CONFIG
pub const SOUND_ENABLE = true;
pub const SOUND_UPDATE_PERIOD = 1; // [SLEEP_PERIOD]
pub const SOUND_CARD = "default";
pub const SOUND_MIXER = "Master";
pub const SOUND_LOW_TAG = "đ";
pub const SOUND_MEDIUM_TAG = "đ";
pub const SOUND_HIGH_TAG = "đ";
pub const SOUND_MUTE_TAG = "đ";

// MEM CONFIG
pub const MEM_ENABLE = true;
pub const MEM_UPDATE_PERIOD = 1; // [SLEEP_PERIOD]
pub const MEM_INFO_PATH = "/proc/meminfo";
pub const MEM_TAG = "â";

// WEATHER CONFIG
pub const WEATHER_ENABLE = true;
pub const WEATHER_UPDATE_PERIOD = 3 * 60 * 60; // [SLEEP_PERIOD]
pub const WEATHER_X_API_KEY = ":)";
pub const WEATHER_CITY = "Bialystok";
pub const WEATHER_TEMP_COLD_THRESHOLD = 9;
pub const WEATHER_TEMP_HOT_THRESHOLD = 25;
pub const WEATHER_TEMP_HIGH_TAG = "đĨĩ";
pub const WEATHER_TEMP_MEDIUM_TAG = "đ";
pub const WEATHER_TEMP_LOW_TAG = "đĨļ";
pub const WEATHER_HUMIDITY_TAG = "đ§";
pub const WEATHER_SUNSET_TAG = "đ";

// ORDERING CONFIG
pub const Module = enum(u8) { time, date, bat, net, sound, weather, mem };

// from right to left
pub const FMT_ORDER: [7]Module = .{
    .time,
    .date,
    .bat,
    .sound,
    .mem,
    .net,
    .weather,
};   