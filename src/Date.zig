const std = @import("std");

const Self = @This();

hour: u8,
minute: u8,
second: u8,
day_of_week: []const u8,
day_of_month: u8,
month: []const u8,  
year: u16,

pub fn init(timestamp_ms: i64) Self {
    const sec = std.time.epoch.EpochSeconds{ 
        .secs = @intCast(u64, @divTrunc(timestamp_ms, 1000))
    };
    const day_seconds = sec.getDaySeconds();
    const day = sec.getEpochDay();
    const year_and_day = day.calculateYearDay();
    const month_and_day = year_and_day.calculateMonthDay();

    return Self {
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