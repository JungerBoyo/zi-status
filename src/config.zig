// GENERAL 
pub const SLEEP_PERIOD = 1; // [s]

// TIME CONFIG
pub const TIME_ENABLE = true;
pub const TIME_UPDATE_PERIOD = 1; // [SLEEP_PERIOD]
pub const TIME_INCLUDE_SECONDS = true;
pub const TIME_TAG = "🕒";
pub const DATE_ENABLE = true;
pub const DATE_TAG = "📅";

// BAT CONFIG
pub const BAT_ENABLE = true;
pub const BAT_UPDATE_PERIOD = 1; // [SLEEP_PERIOD]
pub const BAT_UEVENT_PATH = "/sys/class/power_supply/BAT0/uevent";
pub const BAT_LOW_TAG = "🪫";
pub const BAT_HIGH_TAG = "🔋";
pub const BAT_STATE_CHARGING_TAG = "😀";
pub const BAT_STATE_DISCHARGING_TAG = "🫠";
pub const BAT_STATE_UNKNOWN_TAG = "🧐";

// NET CONFIG
pub const NET_ENABLE = false;
pub const NET_UPDATE_PERIOD = 1; // [SLEEP_PERIOD]
pub const NET_WIFI_TAG = "🛜";
pub const NET_ETHERNET_TAG = "🪱";

// SOUND CONFIG
pub const SOUND_ENABLE = true;
pub const SOUND_UPDATE_PERIOD = 1; // [SLEEP_PERIOD]
pub const SOUND_CARD = "default";
pub const SOUND_MIXER = "Master";
pub const SOUND_LOW_TAG = "🔈";
pub const SOUND_MEDIUM_TAG = "🔉";
pub const SOUND_HIGH_TAG = "🔊";

// WEATHER CONFIG
pub const WEATHER_ENABLE = true;
pub const WEATHER_UPDATE_PERIOD = 60; // [SLEEP_PERIOD]
pub const WEATHER_X_API_KEY = "qP50N/aq5nLA+c/e78WcAA==075zlDstMnbMdhvX";
pub const WEATHER_CITY = "Bialystok";
pub const WEATHER_TEMP_TAG = "⛅";
pub const WEATHER_HUMIDITY_TAG = "⛅";
pub const WEATHER_SUNSET_TAG = "⛅";