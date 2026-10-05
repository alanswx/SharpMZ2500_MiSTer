-- Headless comparison helper: after N frames, save a snapshot and dump main RAM / VRAM, then exit.
local frames = tonumber(os.getenv("SNAP_FRAMES") or "600")
local out = os.getenv("SNAP_OUT") or "snap"
local n = 0
emu.register_frame_done(function()
  n = n + 1
  if n == frames then
    manager.machine.video:snapshot()
    local mem = manager.machine.devices[":maincpu"].spaces["program"]
    local f = io.open(out .. "_cpu64k.bin", "wb")
    for a = 0, 0xffff do f:write(string.char(mem:read_u8(a))) end
    f:close()
    for _, name in ipairs({":wram", ":cgram", ":tvram"}) do
      local s = manager.machine.memory.shares[name]
      if s then
        local g = io.open(out .. "_" .. name:sub(2) .. ".bin", "wb")
        for a = 0, s.size - 1 do g:write(string.char(s:read_u8(a))) end
        g:close()
      end
    end
    manager.machine:exit()
  end
end)
