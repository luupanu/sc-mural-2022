////////////////////////////////////// BUFFER SETUP //////////////////////////////////////
(

~buffers = SoundFile.collectIntoBuffers(thisProcess.nowExecutingPath.dirname +/+ "sounds" +/+ "*";, s).do { |f| f.path.postln; };

)

///////////////////////////////////////// SETUP /////////////////////////////////////////
(

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
~createPlayBufs = { |bufs, amps, pans∂, panCenter=0, panWidth=0.5, onsetBuses, target|
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
    var onsetBuses = Dictionary(bufnums.size);

    bufnums.do({ |id|
        onsetBuses.put(id, Bus.audio(s, 1));
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

///////////////////////////////////////// SLIDERS /////////////////////////////////////////
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

///////////////////////////////////////// OSCDEFS /////////////////////////////////////////
OSCdef(\tr, { |msg|
    var id = msg[2];

    // color
    if (id == -1, {
        var value = msg[3];
        var rampTime = 5.0; // rrand(0.5, 1.0);
        [value, rampTime].postln;
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

///////////////////////////////////////// GROUPS /////////////////////////////////////////
~src_group = Group(s);
~sansula_group = Group(~src_group);
~onsetdetectors_group = Group.after(~sansula_group);

~fx_group = Group.after(~src_group);

~master_group = Group.after(~fx_group);

///////////////////////////////////////// BUSES /////////////////////////////////////////
~master_bus = Bus.audio(s, 4);

///////////////////////////////////////// SYNTHDEFS /////////////////////////////////////////
SynthDef(\playBuf, { |bufnum, onsetBus, out=0, loop=1, amp=0.01, area=0.5, rate=1, pos=0|
    var sig = PlayBuf.ar(
        numChannels: 1,
        bufnum: bufnum,
        rate: rate,
        loop: loop,
        doneAction: 2,
    );

    var smoothArea = Lag3.kr(area, 1);

    smoothArea.poll.postln;

    Out.ar(out, PanAz.ar(
        numChans: 4,
        in: sig,
        pos: pos,
        level: amp*2*smoothArea,
    ));

    Out.ar(onsetBus, sig*amp);
}).add;

SynthDef(\onsetDetector, { |in, id, thresh=0.05, mingap=50 |
    var sig, chain, onsets, pips, trig;

    sig = In.ar(in, 2);
    chain = FFT(LocalBuf(512), sig);
    onsets = Onsets.kr(chain, thresh, relaxtime: 5, mingap: mingap);

    SendTrig.kr(onsets, id, id);
}).add;

)

///////////////////////////////////////// PLAY /////////////////////////////////////////
(

var bufnums = (0..5);
var amps = #[0.1, 0.1, 0.07, 0.03, 0.01, 0.002];

~onset_buses = ~createOnsetDetectors.(bufnums);
~amp_max = amps.maxItem * 2;

~sansulas = ~createPlayBufs.(
    bufs: bufnums,
    onsetBuses: ~onset_buses,
    amps: amps,
    panWidth: 0.25,
    /*pans: [-0.2, -0.05, 0.02, 0.1, 0.2, 0.3],*/
    target: ~sansula_group,
);

// simulate color
x = {
    var sig = LFTri.kr(0.1);
    var random = Dwhite();
    var randomVal = Demand.kr(sig, 0, random);
    SendTrig.kr(sig, -1, randomVal);
}.play;

)


///////////////////////////////////////// END /////////////////////////////////////////












