(
~buffers = SoundFile.collectIntoBuffers(thisProcess.nowExecutingPath.dirname +/+ "sounds" +/+ "*";, s).do {
    |f| PathName(f.path).fileNameWithoutExtension.postln;
};
)

////////////////////////////////////////////// SETUP /////////////////////////////////////////////////////
(

/*s.waitForBoot({*/
/*~buffers = SoundFile.collectIntoBuffers(thisProcess.nowExecutingPath.dirname +/+ "sounds" +/+ "*";, s).do { |f| f.path.postln; };*/
VSTPlugin.search(
    action: {
        var window, distanceSlider, colorSlider;

        var distMin = 0;
        var distMax = 1;
        var lowerThresh = 0.1;
        var higherThresh = 0.75;

        var targetAddress = FileReader.read(thisProcess.nowExecutingPath.dirname +/+ "CONFIG")[0][0];
        var targetPort = 57121;
        var onsetTrig = 0;
        var targetServer = NetAddr(targetAddress, targetPort);

         ///////////////////////////////////////// SYNTHDEFS /////////////////////////////////////
        SynthDef(\convolution, { |in, out|
            var signal = In.ar(in, 1);
            Out.ar(out, VSTPlugin.ar(signal!2, 2, id: \convolution));
        }).add;

        SynthDef(\playBuf, { |bufnum, onsetBus, out=0, loop=1, amp=0.01, area=0.5, rate=1, pos, prevPos, gate, t_trig, del=0, att=5, dec=0.8, sus=0.8, rel=5, peak=0.2, grpAmp=1|
            var aOrB, crossfade, panAorB, pancrossfade, pos1, pos2;
            var d_rndPan, d_rndPanRange, rndPan, rndPanRange;
            var buf1, buf2, env, gen, sig;

            aOrB = ToggleFF.kr(t_trig);
            crossfade = Lag.ar(K2A.ar(aOrB), 5);

            panAorB = ToggleFF.kr(t_trig);
            pancrossfade = Lag.ar(K2A.ar(panAorB), 5);

            d_rndPan = Dwhite(0.01, 0.5, inf);
            d_rndPanRange = Dwhite(0.01, 0.05, inf);

            env = Env.dadsr(del, att, dec, sus, rel, peak, [0, 2, -4, 0]);
            gen = EnvGen.ar(env, gate);

            buf1 = PlayBuf.ar(
                numChannels: 1,
                bufnum: bufnum,
                rate: rate,
                loop: loop,
                // doneAction: 2,
            );

            buf2 = PlayBuf.ar(
                numChannels: 1,
                bufnum: bufnum,
                rate: rate,
                loop: loop,
                // doneAction: 2,
            );

            rndPan = Demand.kr(t_trig, 0, d_rndPan);
            rndPanRange = Demand.kr(t_trig, 0, d_rndPanRange);

            sig = (crossfade*buf1) + ((1-crossfade)*buf2) * gen;

            //  * LFSaw.kr(rndPan).range(1 - (rndPanRange/0.5), 1 + (rndPanRange/0.5))

            Out.ar(out, PanAz.ar(
                numChans: 4,
                in: sig,
                pos: (pancrossfade*pos) + ((1-pancrossfade) * prevPos),
                level: amp*grpAmp, // *2*smoothArea,
            ));

            Out.ar(onsetBus, sig*gate*grpAmp);
        }).add;

        SynthDef(\panningPlayBuf, { |bufnum, onsetBus, out=0, loop=1, amp=0.01, area=0.5, rate=1, gate=1, del=0, att=0.1, dec=0.8, sus=0.8, rel=5, peak=0.2, panRate, filtfreq=2500, rq=1, t_trig, grpAmp=1|
            var buf, env, gen, filter, sig;
            var frames, duration;

            SendTrig.kr(t_trig, -1, bufnum);

            rate = rate * BufRateScale.kr(bufnum);
            frames = BufFrames.kr(bufnum);
            duration = frames/rate.abs/44100;

            env = Env.perc(att, rel);
            gen = EnvGen.ar(env, gate, timeScale: duration, doneAction: 2);

            buf = PlayBuf.ar(
                numChannels: 1,
                bufnum: bufnum,
                rate: rate,
                loop: loop,
                doneAction: 2,
            );

            filter = RLPF.ar(buf * gen, filtfreq, rq);

            sig = filter;

            Out.ar(out, PanAz.ar(
                numChans: 4,
                in: sig,
                pos: LFSaw.kr(panRate),
                level: amp*grpAmp, // *2*smoothArea,
            ));

            Out.ar(onsetBus, sig*gate*grpAmp);
        }).add;

        SynthDef(\onsetDetector, { |in, id, thresh=0.04, mingap=50, odftype |
            var sig, chain, onsets, pips, trig;

            sig = In.ar(in, 2);
            chain = FFT(LocalBuf(512), sig);
            onsets = Onsets.kr(chain, thresh, odftype, relaxtime: 5, mingap: mingap);

            SendTrig.kr(onsets, id, id);
        }).add;

        ///////////////////////////////////////// FUNCTIONS /////////////////////////////////////////
        ~bus_ctrl = { |bus, newVal, fadeTime=5|
            bus.get({ |val| {
                var fade = EnvGen.kr(Env([val, newVal], [fadeTime], 'sin'), doneAction: 2);
                // Out.kr(bus, Ramp.kr(Env.linen(fadeTime)));
                Out.kr(bus, fade);
            }.play;
            });
        };

        ~createOnsetDetectors = { |bufnums|
            var onsetBuses = Array.fill(bufnums.size, { |id| Bus.audio(s, 1); });
            var sansula_mingaps = #[128, 128, 60, 60, 60, 60];

            onsetBuses.do({ |bus, i|
                var id = bufnums[i];

                Synth(\onsetDetector, [
                    in: bus,
                    id: id,
                    thresh: 0.12,
                    mingap: sansula_mingaps[i],
                    odftype: \rcomplex,
                ], ~onsetdetectors_group);
            });

            onsetBuses
        };

        ~pans = { |n, panCenter, panWidth|
            Pgauss(panCenter, panWidth/2, n).asStream.nextN(n);
            // Array.fill(n, { |i| (panCenter - panWidth / 2) + ((panWidth / (n-1)) * i) });
        };

        ///////////////////////////////////////// OSCDEFS ///////////////////////////////////////////
        OSCdef(\tr, { |msg|
            var id = msg[2];

            if (id == -1, {
                var bufnum = msg[3];
                ~color = ~color + rrand(0.2, 0.4) % 1;
                // targetServer.sendMsg("/color", ~color, 0.5);
            }, {
                // ripples
                onsetTrig = onsetTrig * (-1) + 1;

                if ((onsetTrig > 0) && (id >= 0) && (id < 7), {
                    var clippedAmp;

                    ~sansulas[id].get(\amp, { |amp|
                        clippedAmp = amp.linlin(0, ~sansula_amps.maxItem*2, 0, 1);

                        // NetAddr.localAddr.sendMsg("/ripple", id, clippedAmp);
                        // targetServer.sendMsg("/ripple", id, clippedAmp);
                    });
                });
            });

        },"/tr");

        OSCdef(\ripple, { |msg|
            msg.postln;
        }, "/ripple");

        OSCdef(\area, { |msg|
            ~bus_ctrl.(msg[1])
        });

        OSCdef(\blob, { |msg|
            ~blob_buffer[~blob_i] = msg[1];
            ~blob_i = (~blob_i + 1) % (~blob_buffer.size);

            ~cymbal_amp_ctrl.get({ |val|
                if ((val == 1) and: (~blob_buffer.detect({ |i| i == 0; }).isNil) and: (~blob_lock == 0), {
                    ~blob_lock = 1;
                    ~bus_ctrl.(~cymbal_amp_ctrl, 0);
                    ~bus_ctrl.(~sansula_amp_ctrl, 1, fadeTime: 8);

                    { 9.wait; ~blob_lock = 0; }.fork;
                });
            });

            ~sansula_amp_ctrl.get({ |val|
                if ((val == 1) and: (~blob_buffer.detect({ |i| i == 1; }).isNil) and: (~blob_lock == 0), {
                    ~blob_lock = 1;
                    ~bus_ctrl.(~sansula_amp_ctrl, 0);
                    ~bus_ctrl.(~cymbal_amp_ctrl, 1, fadeTime: 8);

                    { 9.wait; ~blob_lock = 0; }.fork;
                });
            });

        }, "/blob");

        ///////////////////////////////////////// GROUPS ////////////////////////////////////////
        ~src_group = Group(s);

        ~couscous_group = Group(~src_group);
        ~sansula_group = Group.after(~couscous_group);
        ~chess_group = Group.after(~sansula_group);
        ~cymbal_group = Group.after(~chess_group);

        ~onsetdetectors_group = Group.after(~src_group);

        ~fx_group = Group.after(~onsetdetectors_group);

        ~master_group = Group.after(~fx_group);

        ///////////////////////////////////////// BUSES /////////////////////////////////////////

        ~conv_bus = Bus.audio(s, 4);
        ~master_bus = Bus.audio(s, 4);

        ///////////////////////////////////////// VSTS /////////////////////////////////////////
        ~convolution0 = VSTPluginController(Synth(\convolution, [\in, ~conv_bus, \out, 0], ~fx_group), id: \convolution);
        ~convolution0.open(
            "Convology XT.vst3",
            editor: true,
            verbose: true,
            action: {
                ~convolution0.loadPreset("arundel");
            },
        );

        ~convolution2 = VSTPluginController(Synth(\convolution, [\in, ~conv_bus, \out, 2], ~fx_group), id: \convolution);
        ~convolution2.open(
            "Convology XT.vst3",
            editor: true,
            verbose: true,
            action: {
                ~convolution2.loadPreset("arundel");
            },
        );

        ///////////////////////////////////////// BUFNUMS ////////////////////////////////////
        ~couscous_bufnums = 0;
        ~sansula_bufnums = (1..6);
        ~chess_bufnums = (7..8);
        ~cymbal_bufnums = (9..14);

        //////////////////////////////////////// MISC ////////////////////////////////////////
        ~color = 1.0.rand;
        ~cymbal_durations = [8.5225850340136, 7.3956689342404, 11.750975056689, 17.512063492063, 13.389569160998, 11.853015873016];
        ~blob_buffer = Array.fill(120, { |i| 0 });
        ~blob_i = 0;
        ~cymbal_bufnum = 0;
        ~blob_lock = 0;

        //////////////////////////////////////// AMPS ////////////////////////////////////////
        ~couscous_amps = #[0.2];
        ~sansula_amps = #[0.2, 0.2, 0.14, 0.06, 0.02, 0.004] * 1.5;
        ~chess_amps = #[0.2, 0.3];
        ~cymbal_amps = #[0.05, 0.05, 0.05, 0.05, 0.05, 0.05];

        ///////////////////////////////////////// SYNTHS /////////////////////////////////////

        ~generate_playbufs = { |key, startId, amps, out, target, args |
            var dict = Dictionary();

            (amps.size).do({ |id|
                dict.put(id, Synth(key, args ++ [
                    bufnum: startId + id,
                    onsetBus: ~onset_buses[startId + id],
                    amp: amps[id],
                    out: out,
                ], target));
            });

            dict
        };
});
/*});*/

)

~convolution2.editor;

~convolution2.savePreset("arundel");


///////////////////////////////////////// PLAY /////////////////////////////////////////
(

~onset_buses = ~createOnsetDetectors.((0..14));

///////////////////////////////////////// CYMBALS //////////////////////////////////


~cymbal_bufnum = Pxrand(~cymbal_bufnums, inf);

Pdef(\cymbals,
    Pbind(
        \instrument, \panningPlayBuf,
        \bufnum, ~cymbal_bufnum,
        \amp, Pgauss(0.3, 0.1, inf),
        \grpAmp, ~cymbal_amp_ctrl.asMap,
        \rate, Pgauss(1.2, 0.6666, inf),
        \panRate, Pgauss(1, 0.6666, inf),
        \delta, Pgauss(20, 5, inf),
        \filtfreq, Pgauss(1500, 250, inf),
        \t_trig, 1,
        \callback, { ~send_color.(~cymbal_bufnum.asStream.next); },
    )
);

Pdef(\cymbals).play;

///////////////////////////////////////// SANSULAS //////////////////////////////////

~sansulas = ~generate_playbufs.(
    key: \playBuf,
    startId: 1,
    amps: ~sansula_amps,
    out: 0,
    target: ~sansula_group,
);

~random_play_sansulas = {
    var buffleShuffle = Pshuf(~sansula_bufnums, 1).asStream;
    var nakki = Pxrand([2, 3, 4, 5], 1).asStream;

    var n = nakki.next;
    var bufs = buffleShuffle.nextN(n);

    var pans = ~pans.(n, panCenter: 2.0.rand2, panWidth: 1.5);
    var atts = #[2.5, 2, 2, 1.5, 1.25, 1];
    var rndrat = 0.01;

    bufs.do({ |id|
        ~sansulas[id].get(\pos, { |prevPos|
            ~sansulas[id].set(\prevPos, prevPos);
            ~sansulas[id].set(\pos, pans[id]);
            ~sansulas[id].set(\amp, ~sansula_amps[id]*rrand(1, 2));
            ~sansulas[id].set(\del, exprand(0.5, 10));
            ~sansulas[id].set(\att, atts[id] + rrand(2, 5));
            ~sansulas[id].set(\dec, atts[id] + rrand(0.8, 3.2));
            ~sansulas[id].set(\rel, atts[id] + rrand(0.5, 1));
            ~sansulas[id].set(\rate, rrand(1-(rndrat*0.5), (1+(rndrat*0.5)).reciprocal));
            ~sansulas[id].set(\gate, 1);
            ~sansulas[id].set(\t_trig, 1);
        });
    });

    bufs
};

fork {
    ~currently_playing = ~random_play_sansulas.();
    loop {
        rrand(30.0, 50.0).yield;
        ~currently_playing.do({ |id| ~sansulas[id].set(\gate, 0) });
        rrand(3.5, 4).yield;
        ~currently_playing = ~random_play_sansulas.();
    }
};

/*~couscous = ~generate_playbufs.(
key: \playBuf,
startId: 0,
amps: ~couscous_amps,
out: 0,
target: ~couscous_group,
);*/

/*~chess = ~generate_playbufs.(
key: \playBuf,
startId: 7,
amps: ~chess_amps,
out: 0,
target: ~chess_group,
);
~cymbals = ~generate_playbufs.(
key: \panningPlayBuf,
startId: 9,
amps: ~cymbal_amps,
out: ~conv_bus,
target: ~cymbal_group,
args: [\panRate, 2],
);*/

)

(
///////////////////////////////////////// BUS CONTROL //////////////////////////////////

~sansula_area_ctrl = Bus.control(s);
~cymbal_area_ctrl = Bus.control(s);

~sansula_group.map(\area, ~sansula_area_ctrl);
~cymbal_group.map(\area, ~cymbal_area_ctrl);

~sansula_amp_ctrl = Bus.control(s);
~cymbal_amp_ctrl = Bus.control(s);

~sansula_group.map(\grpAmp, ~sansula_amp_ctrl);

~bus_ctrl.(~sansula_amp_ctrl, 0, 0.1);
~bus_ctrl.(~cymbal_amp_ctrl, 1, 0.1);
)

///////////////////////////////////////// END /////////////////////////////////////////

/*

// simulate color
x = {
    var sig = LFTri.kr(0.1);
    var random = Dwhite();
    var randomVal = Demand.kr(sig, 0, random);
    SendTrig.kr(sig, -1, randomVal);
}.play;

*/
