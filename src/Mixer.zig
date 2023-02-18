const std = @import("std");

const c = @cImport({
    @cInclude("alsa/asoundlib.h");
});

const Self = @This();

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

pub const State = struct {
    volume: u8 = 0,
    is_unmuted: bool = false,
};

pub fn init(card: [:0]const u8, selem_name: [:0]const u8) ALSAError!Self {
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

    return Self{
        .handle = handle,
        .card = card,
        .elem = elem,
        .vol_min = vol_min,
        .vol_max = vol_max,
    };
}

// returns volume level in %
pub fn state(self: *Self) State {
    _ = c.snd_mixer_handle_events(self.handle);

    var vol: c_long = 0;
    _ = c.snd_mixer_selem_get_playback_volume(
        self.elem, 
        c.SND_MIXER_SCHN_MONO,
        &vol
    );
    var vol_unmuted: c_int = 0;
    _ = c.snd_mixer_selem_get_playback_switch(
        self.elem,
        c.SND_MIXER_SCHN_MONO,
        &vol_unmuted
    );

    const vol_resolution = self.vol_max - self.vol_min;

    const vol_normalized = @divTrunc((100 * (vol - self.vol_min)), vol_resolution);

    return State {
        .volume = @intCast(u8, vol_normalized),
        .is_unmuted = vol_unmuted == 1
    };

}

pub fn deinit(self: *Self) void {
    _ = c.snd_mixer_detach(self.handle, self.card.ptr);
    _ = c.snd_mixer_close(self.handle);
}