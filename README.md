# zi-status
---

<p>
    <img src="assets/showoff.png"/>
</p>

---
> currently shows
 - internet connection state (ip+mask+speed+type{wifi,ethernet}+SSID(only wifi)+signal strength(only wifi)
 - date and time info
 - battery info
 - sound level info (ALSA)
 - ram memory usage in MB (Total mem - Available mem)
 - weather info (temp+humidity+sunset)


## Configuration instructions
Under src/ there is config.zig file. In there you can adjust available config parameters that are mostly self-explanatory. Config argument `WEATHER_X_API_KEY` is a string that you get after making an account at https://api-ninjas.com. There you get 50k free API requests per month. 

## Running instructions
`zi-status` takes one optional* `timezone` parameter in format (+/-)NN00 where N is a digit. For example for timezone UTC+1 the argument should be +0100. Format is based on one that `timedatectl` command returns. Example of how to extract it from timedatectl output:

`timedatectl | grep zone | awk '{print$5}' | tr -d "\)"`

*if no timezone arg is passed timezone +0000 is assumed
