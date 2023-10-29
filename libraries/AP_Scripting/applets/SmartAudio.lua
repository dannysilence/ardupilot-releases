--------------------------------------------------
--------------------------------------------------
--------- VTX LUA for SMARTAUDIO 2.0 -------------
------------based on work by----------------------
---------Craig Fitches 07/07/2020 ----------------
-------------Mods by H. Wurzburg -----------------
------------clean up by Peter Hall----------------

-----------------HARDWARE------------------
-- tested on CUAVv5Nano and TX8111 VTX

-- Prerequisites ----------------------------------
-- 1. Only works in Ardupilot 4.1dev or later
-- 2. FC with 2MB cache for LUA Scripting
-- 3. Currently only works with SmartAudio 2.0

------------ Instructions ------------------------
-- 1. Set an unused Serial port in Ardupilot to protocol 28 (scripting) and option 4 (half-duplex)
-- 2. Setup an rc channel's RXc_OPTION to 300 for changing power and SCR_USER1 parameter for initial power upon boot
---------and set to -1 for unchanged, 0 (PitMode),1,2,3, or 4 for power level (1 lowest,4 maximum)
-- 3. Attach the UART's TX for the Serial port chosen above to the VTX's SmartAudio input
-- 4. Other SmartAudio commands structure from https://www.team-blacksheep.com/media/files/tbs_smartaudio_rev08.pdf


-- init local variables
local startup_pwr = param:get('SCR_USER1') 
local startup_fre = param:get('SCR_USER2') 
local startup_chn = param:get('SCR_USER3') 
local scripting_rc = rc:find_channel_for_option(300)
local port = serial:find_serial(0)
local _current_power = -1

-- hexadecimal smart audio 2.0 commands
local power_commands = {}
power_commands[1] = { {0x00,0x00,0xAA,0x55,0x0B,0x01,0x01,0xF8,0x00}, "VTX Pit Mode" }
power_commands[2] = { {0x00,0x00,0xAA,0x55,0x05,0x01,0x00,0x6B,0x00}, "VTX PWR LOW" } -- SMARTAUDIO_V2_COMMAND_POWER_0
power_commands[3] = { {0x00,0x00,0xAA,0x55,0x05,0x01,0x01,0xBE,0x00}, "VTX PWR MED" } -- SMARTAUDIO_V2_COMMAND_POWER_1
power_commands[4] = { {0x00,0x00,0xAA,0x55,0x05,0x01,0x02,0x14,0x00}, "VTX PWR HIGH" } -- SMARTAUDIO_V2_COMMAND_POWER_2
power_commands[5] = { {0x00,0x00,0xAA,0x55,0x05,0x01,0x03,0xC1,0x00}, "VTX PWR MAX" } -- SMARTAUDIO_V2_COMMAND_POWER_3
power_commands[6] = { {0x00,0x00,0xAA,0x55,0x03,0x00,0x00,0x00,0x00}, "VTX Get Settings" } -- SMARTAUDIO_GET_SETTING


-- returns setting value ; 0 - channel, 1 - frequency, 2 - version. returns -1 in case of read failure 
-- SmartAudio V1 response: VTX: 0xAA 0x55 0x01 (Version/Command) 0x06 (Length) 0x00 (Channel) 0x00 (Power Level) 0x01(OperationMode) 0x16 0xE9(Current Frequency 5865) 0x4D(CRC8)
-- SmartAudio V2 response: VTX: 0xAA 0x55 0x09 (Version/Command) 0x06 (Length) 0x01 (Channel) 0x00 (Power Level) 0x1A(OperationMode) 0x16 0xE9(Current Frequency 5865) 0xDA(CRC
function getSetting(setting)
  updateSerial(power_commands[6][1])
  gcs:send_text(4, power_commands[6][2])

  local a = -1
    
  for count = 1, 12 do
    local b = port:read()
    if a == -1 then
      if b == 0xAA then
        a = count   
      end
    else
      if setting == 0 and count - a == 4 then
        return b
      end

      if setting == 1 and count - a == 6 then
        local c = port:read()

        return b * 0x100 + c
      end

      if setting == 0 and count - a == 2 then
        if b == 0x01 then 
          return 1
        end

        if b == 0x09 then
          return 2
        end

        return -1
      end
    end

    return -1
  end
end

-- set the frequency in the range 5000-6000 MHz
-- Example: 0xAA 0x55 0x09(Command 4) 0x02(Length) 0x16 0xE9(Frequency 5865) 0xDC(CRC8
function setFrequency(frequency)
  a = frequency // 0x100
  b = frequency % 0x100
  c = { {0x00,0x00,0xAA,0x55,0x09,0x02,a,b,0x00}, "VTX Frequency: ${frequency}" } 
  updateSerial(c[1])
  gcs:send_text(4, c[2])

  local x = getSetting(1)  
  local y = "VTX Actual Frequency: ${x}"
  gcs:send_text(4, y)
end

-- set the channel in the range 0-40
-- Example: 0xAA 0x55 0x07(Command 3) 0x01(Length) 0x00(All 40 Channels 0-40) 0xB8(CRC8
function setChannel(channel)
  b = { {0x00,0x00,0xAA,0x55,0x07,0x01,channel,0x00,0x00}, "VTX Channel: ${channel}" } 
  updateSerial(b[1])
  gcs:send_text(4, b[2])
    
  local x = getSetting(0)
  local y = "VTX Actual Channel: ${x}"
  gcs:send_text(4, y)
end


-- return a power level from 1 to 5 as set with a switch
function get_power()
  input = scripting_rc:norm_input() -- - 1 to 1
  input = (input + 1) * 2 -- 0 to 4
  return math.floor(input+0.5) + 1 -- integer 1 to 5
end

-- set the power in the range 1 to 5
function setPower(power)
  if power == _current_power then
    return
  end
  updateSerial(power_commands[power][1])
  gcs:send_text(4, power_commands[power][2])
  _current_power = power
end

-- write output to the serial port
function updateSerial(value)
  for count = 1, #value do
    port:write(value[count])
  end
end

---- main update ---
function update()
  setPower(get_power())
  return update, 500
end

-- initialization
function init()
  -- check if setup properly
  if not port then
    gcs:send_text(0, "SmartAudio: No Scripting Serial Port")
    return
  end
  if not scripting_rc then
    gcs:send_text(0, "SmartAudio: No RC option for scripting")
    return
  end

  port:begin(4800)

  -- Set initial power after boot based on SCR_USER1
  if startup_pwr then -- make sure we found the param
    if startup_pwr >= 0  and startup_pwr < 5 then
      setPower(math.floor(startup_pwr) + 1)

      -- set the current power local to that requested by the rc in
      -- this prevents instantly changing the power from the startup value
      _current_power = get_power()
    end
  end

  if startup_fre then -- make sure we found the param
    if startup_fre >= 5000 and startup_fre <= 6000 then
      setFrequency(startup_fre)
    end
  end

  if startup_chn then -- make sure we found the param
    if startup_chn >= 0 and startup_chn <= 40 then
      setChannel(startup_chn)
    end
  end
    
  return update, 500
end

return init, 2000 --Wait 2 sec before initializing, gives time for RC in to come good in SITL, also gives a better chance to see errors
