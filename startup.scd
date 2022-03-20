// Server setup
s = Server.default;
s.latency = 0.15;

// For mural
Server.default.options.device_("LINE (ZOOM L-8 Audio)");
Server.default.options.numOutputBusChannels_(4);

s.waitForBoot({
    VSTPlugin.search;
});
