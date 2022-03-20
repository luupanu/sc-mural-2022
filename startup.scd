// Server setup
s = Server.default;
s.latency = 0.05;

// MIDI setup
MIDIClient.init;
m = MIDIOut.newByName("IAC Driver", "Bus 1").latency_(0);
CmdPeriod.add({(0..127).do{ |n| m.noteOff(0, n) }});

// Ableton Link setup
l = LinkClock(2).latency_(Server.default.latency);

// For mural
Server.default.options.device_("ZOOM L-8 Driver");
Server.default.options.numOutputBusChannels_(4);

s.waitForBoot({
    VSTPlugin.search;
});
