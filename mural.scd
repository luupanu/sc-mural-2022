~buffers = SoundFile.collectIntoBuffers(thisProcess.nowExecutingPath.dirname +/+ "sounds" +/+ "*";, s).do { |f| f.path.postln; };

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
        var targetPort = 57120;
        var targetServer = NetAddr(targetAddress, targetPort);

        var onsetTrig = 0;

        ///////////////////////////////////////// FUNCTIONS /////////////////////////////////////////
        ~createPlayBufs = { |bufs, amps, pans, panCenter=0, panWidth=0.5, onsetBuses, target|
            var n, synths;

            n = bufs.size;
            synths = Array(n);
            if (pans.isNil, {
                pans = Array.fill(n, { |i| (panCenter - panWidth / 2) + ((panWidth / (n-1)) * i) });
            });

            bufs.do({ |b, i|
                synths.add(
                    Synth(\playBuf, [
                        bufnum: bufs[i],
                        onsetBus: onsetBuses[bufs[i]],
                        amp: amps.wrapAt(i),
                        pos: pans.wrapAt(i),
                    ], target)
                );
            });

            synths
        };

        ~createOnsetBuses = { |bufnums|
            var onsetBuses = Array(bufnums.size);

            bufnums.do({ |id|
                onsetBuses.add(Bus.audio(s, 1));
            });

            onsetBuses
        };

        ~createOnsetDetectors = { |bufnums|
            var onsetBuses;

            onsetBuses = ~createOnsetBuses.(bufnums);

            onsetBuses.do({ |bus, i|
                var id = bufnums[i];

                Synth(\onsetDetector, [
                    in: bus,
                    id: id,
                ], ~onsetdetectors_group);
            });

            onsetBuses
        };

        ~pans = { |n, panCenter, panWidth|
            Pgauss(panCenter, panWidth/2, n).asStream.nextN(n);
            // Array.fill(n, { |i| (panCenter - panWidth / 2) + ((panWidth / (n-1)) * i) });
        };

        ////////////////////////////////////////// SLIDERS //////////////////////////////////////////
        /*window = Window.new.front;
        window.view.decorator=FlowLayout(window.view.bounds);
        window.view.decorator.gap=2@2;
        distanceSlider = EZSlider(
        parent: window,
        bounds: 392@16,
        label: " distance ",
        unitWidth: 30,
        numberWidth: 60,
        action: { |ez|
        NetAddr.localAddr.sendMsg("/distance", ez.value);
        },
        );
        colorSlider = EZSlider(
        parent: window,
        bounds: 392@16,
        label: " color ",
        unitWidth: 30,
        numberWidth: 60,
        action: { |ez|
        targetServer.sendMsg("/color", ez.value);
        },
        );*/

        ///////////////////////////////////////// OSCDEFS ///////////////////////////////////////////
        OSCdef(\tr, { |msg|
            var id = msg[2];

            // color
            if (id == -1, {
                var value = msg[3];
                var rampTime = 5.0; // rrand(0.5, 1.0);
                targetServer.sendMsg("/color", value, rampTime);
            },
            // ripples
            {
                onsetTrig = onsetTrig * (-1) + 1;
                if (onsetTrig > 0, {
                    var clippedAmp;

                    ~sansulas[id].get(\amp, { |amp|
                        clippedAmp = amp.linlin(0, ~amp_max, 0, 1);

                        // NetAddr.localAddr.sendMsg("/ripple", id, clippedAmp);
                        targetServer.sendMsg("/ripple", id, clippedAmp);
                    });
                });
            })

        },"/tr");

        OSCdef(\ripple, { |msg|
            msg.postln;
        }, "/ripple");

        OSCdef(\area, { |msg|
            var val = (1-(msg[1].clip(0, 1)));
            // var clippedArea = val.linlin(0, 1, 0, 1);
            var clippedArea = val;

            ~sansula_group.set(\area, clippedArea);
        }, "/area");

        OSCdef(\color, { |msg|
            targetServer.sendMsg("/color", msg[1]);
            // colorSlider.value = msg[1];
        }, "/color");

        ///////////////////////////////////////// GROUPS ////////////////////////////////////////
        ~src_group = Group(s);
        ~sansula_group = Group(~src_group);
        ~onsetdetectors_group = Group.after(~sansula_group);

        ~fx_group = Group.after(~src_group);

        ~master_group = Group.after(~fx_group);

        ///////////////////////////////////////// BUSES /////////////////////////////////////////
        ~master_bus = Bus.audio(s, 4);

        ///////////////////////////////////////// SYNTHDEFS /////////////////////////////////////
        SynthDef(\playBuf, { |bufnum, onsetBus, out=0, loop=1, amp=0.01, area=0.5, rate=1, pos, prevPos, gate, t_trig, del=0, att=5, dec=0.8, sus=0.8, rel=5, peak=0.2|
            var aOrB, crossfade, panAorB, pancrossfade, pos1, pos2;
            var d_rndPan, d_rndPanRange, rndPan, rndPanRange;
            var buf1, buf2, env, gen, sig;

            aOrB = ToggleFF.kr(t_trig);
            crossfade = Lag.ar(K2A.ar(aOrB), 5);

            panAorB = ToggleFF.kr(t_trig);
            pancrossfade = Lag3.ar(K2A.ar(panAorB), 5);

            d_rndPan = Dwhite(0.01, 0.5, inf);
            d_rndPanRange = Dwhite(0.01, 0.05, inf);

            env = Env.dadsr(del, att, dec, sus, rel, peak, [0, 2, -4, 0]);
            gen = EnvGen.kr(env, gate);

            buf1 = PlayBuf.ar(
                numChannels: 1,
                bufnum: bufnum,
                rate: rate,
                loop: loop,
                doneAction: 2,
            );

            buf2 = PlayBuf.ar(
                numChannels: 1,
                bufnum: bufnum,
                rate: rate,
                loop: loop,
                doneAction: 2,
            );

            rndPan = Demand.kr(t_trig, 0, d_rndPan);
            rndPanRange = Demand.kr(t_trig, 0, d_rndPanRange);

            sig = (crossfade*buf1) + ((1-crossfade)*buf2) * gen;

            //  * LFSaw.kr(rndPan).range(1 - (rndPanRange/0.5), 1 + (rndPanRange/0.5))

            Out.ar(out, PanAz.ar(
                numChans: 4,
                in: sig,
                pos: (pancrossfade*pos) + ((1-pancrossfade) * prevPos),
                level: amp // *2*smoothArea,
            ));

            Out.ar(onsetBus, sig*amp*gate);
        }).add;

        SynthDef(\onsetDetector, { |in, id, thresh=0.04, mingap=50 |
            var sig, chain, onsets, pips, trig;

            sig = In.ar(in, 2);
            chain = FFT(LocalBuf(512), sig);
            onsets = Onsets.kr(chain, thresh, relaxtime: 5, mingap: mingap);

            SendTrig.kr(onsets, id, id);
        }).add;
});
/*});*/

)

///////////////////////////////////////// PLAY /////////////////////////////////////////
(

var bufnums = (1..6);
var amps = #[0.2, 0.2, 0.14, 0.06, 0.02, 0.004];
~amp_max = amps.maxItem * 2;

~onset_buses = ~createOnsetDetectors.(bufnums);
~sansulas = Dictionary(6);

~generate_sansulas = { |n|
    (n+1).do({ |id|
        ~sansulas.put(id, Synth(\playBuf, [
            bufnum: id+1,
            onsetBus: ~onset_buses[id],
            amp: amps[id],
        ], ~sansula_group));
    });
}.(bufnums.size);

~random_play_sansulas = { |bufnums|
    var buffleShuffle = Pshuf(bufnums - 1, 1).asStream;
    var nakki = Pxrand([2, 3, 4, 5], 1).asStream;

    var n = nakki.next;
    var bufs = buffleShuffle.nextN(n);

    var pans = ~pans.(n, panCenter: 2.0.rand2, panWidth: 1.5);
    var amps = #[0.2, 0.2, 0.14, 0.06, 0.02, 0.004];
    var atts = #[2.5, 2, 2, 1.5, 1.25, 1];
    var rndrat = 0.01;

    [bufs, pans].postln;

    bufs.do({ |id|
        ~sansulas[id].get(\pos, { |prevPos|
            ~sansulas[id].set(\prevPos, prevPos);
            ~sansulas[id].set(\pos, pans[id]);
            ~sansulas[id].set(\amp, amps[id]*rrand(1, 2));
            ~sansulas[id].set(\del, rrand(0.5, 10));
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
    ~currently_playing = ~random_play_sansulas.(bufnums);
    loop {
        rrand(30.0, 50.0).yield;
        ~currently_playing.do({ |id| ~sansulas[id].set(\gate, 0) });
        rrand(3.5, 6.5).yield;
        ~currently_playing = ~random_play_sansulas.(bufnums);
    }
};

/*~generate_sansulas = { |n, ids|
    var pans = ~pans.(n, panCenter: 2.0.rand2, panWidth: 2);
    var amps = #[0.1, 0.1, 0.07, 0.03, 0.01, 0.002];

    ids.do({ |id|
        ~sansulas.put(id, Synth(\playBuf, [
            bufnum: id+1,
            onsetBus: ~onset_buses[id],
            amp: amps[id] * 2.0.rand,
            pos: pans[id],
            gate: 1,
        ], ~sansula_group));
    });
};*/

/*{
    var shuffled = Pshuf(bufnums, inf).asStream;
    var n = Pxrand([2, 3, 4, 5], inf).asStream;
    {
        var current, next;

        current = ~generate_sansulas.(n.next, shuffled.nextN(n));
        10.wait;
        current.do({ |id|
            ~sansulas[id].set(\gate, 0);
        })
        next = ~generate_sansulas.(n.next, shuffed.nextN(n));
    }.();
}.();*/

// simulate color
x = {
    var sig = LFTri.kr(0.1);
    var random = Dwhite();
    var randomVal = Demand.kr(sig, 0, random);
    SendTrig.kr(sig, -1, randomVal);
}.play;

)

(
var bufnums = (1..6);
~generate_sansulas = { |n|
    var amps = #[0.2, 0.2, 0.14, 0.06, 0.02, 0.004];
    (n+1).do({ |id|
        ~sansulas.put(id, Synth(\playBuf, [
            bufnum: id+1,
            onsetBus: ~onset_buses[id],
            amp: amps[id],
        ], ~sansula_group));
    });
}.(bufnums.size);
)

~sansulas[0].set(\gate, 1)
~sansulas[0].set(\pos, -0.25)
~sansulas[0].set(\t_trig, 1)

///////////////////////////////////////// END /////////////////////////////////////////




(
Pdef(\hi,
    Pbind(
        \instrument, \playBuf,
        \bufnum, 1,
        \rate, 2,
        \pos, 1,
        \dur, 5,
    )
)
)

Pdef(\hi).play;
Pdef(\hi).freeAll;



