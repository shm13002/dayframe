// Island sound cues. Inside Dayframe the page only names a cue and the app plays it
// natively (App/Dayflow/Island/IslandSound.swift): WebKit won't start Web Audio
// without a click. In a normal browser (dev preview) this Web Audio copy of the same
// recipes plays instead, after the first click.
import type { Cue } from "./types";

interface ToneOptions {
  to?: number;
  dur?: number;
  gain?: number;
  attack?: number;
  delay?: number;
}

export class WebAudioCues {
  private ctx: AudioContext | null = null;
  private master: GainNode | null = null;
  private noise: AudioBuffer | null = null;

  /** Must be called from a user gesture the first time. */
  unlock(): void {
    if (!this.ctx) {
      const ctx = new AudioContext();
      const comp = ctx.createDynamicsCompressor();
      const master = ctx.createGain();
      master.gain.value = 0.55;
      master.connect(comp);
      comp.connect(ctx.destination);
      const len = Math.floor(ctx.sampleRate * 1.5);
      const buf = ctx.createBuffer(1, len, ctx.sampleRate);
      const ch = buf.getChannelData(0);
      for (let i = 0; i < len; i++) ch[i] = Math.random() * 2 - 1;
      this.ctx = ctx;
      this.master = master;
      this.noise = buf;
    }
    if (this.ctx.state === "suspended") void this.ctx.resume();
  }

  private tone(freq: number, o: ToneOptions = {}): void {
    const { ctx, master } = this;
    if (!ctx || !master) return;
    const t0 = ctx.currentTime + (o.delay ?? 0);
    const dur = o.dur ?? 0.35;
    const osc = ctx.createOscillator();
    osc.frequency.setValueAtTime(freq, t0);
    if (o.to) osc.frequency.exponentialRampToValueAtTime(o.to, t0 + dur);
    const g = ctx.createGain();
    g.gain.setValueAtTime(0.0001, t0);
    g.gain.exponentialRampToValueAtTime(o.gain ?? 0.2, t0 + (o.attack ?? 0.005));
    g.gain.exponentialRampToValueAtTime(0.0001, t0 + dur);
    osc.connect(g);
    g.connect(master);
    osc.start(t0);
    osc.stop(t0 + dur + 0.05);
  }

  private tink(freq: number, gain: number, delay = 0): void {
    this.tone(freq, { gain, dur: 0.45, delay });
    this.tone(freq * 1.17, { gain: gain * 0.6, dur: 0.35, delay });
    this.tone(freq * 2.76, { gain: gain * 0.12, dur: 0.15, delay });
  }

  private whoosh(from: number, to: number, dur: number, gain: number): void {
    const { ctx, master, noise } = this;
    if (!ctx || !master || !noise) return;
    const t0 = ctx.currentTime;
    const src = ctx.createBufferSource();
    src.buffer = noise;
    const bp = ctx.createBiquadFilter();
    bp.type = "bandpass";
    bp.Q.value = 1.2;
    bp.frequency.setValueAtTime(from, t0);
    bp.frequency.exponentialRampToValueAtTime(to, t0 + dur);
    const g = ctx.createGain();
    g.gain.setValueAtTime(0.0001, t0);
    g.gain.exponentialRampToValueAtTime(gain, t0 + dur * 0.4);
    g.gain.exponentialRampToValueAtTime(0.0001, t0 + dur);
    src.connect(bp);
    bp.connect(g);
    g.connect(master);
    src.start(t0);
    src.stop(t0 + dur + 0.05);
  }

  play(cue: Cue, value = 0): void {
    if (!this.ctx) return;
    switch (cue) {
      case "drip":
        return this.whoosh(1200, 3000, 0.45, 0.22);
      case "pop":
        this.tink(1000, 0.25);
        return this.tone(160, { to: 55, dur: 0.3, gain: 0.45 });
      case "grain":
        return this.tone(2000 + Math.random() * 1600, { gain: 0.018, dur: 0.05 });
      case "bloop":
        return this.tone(2000, { to: 2900, dur: 0.12, gain: 0.08 });
      case "eyes":
        this.tink(900, 0.18);
        return this.tink(1200, 0.1, 0.04);
      case "ping1":
        return this.tone(3200, { gain: 0.07, dur: 0.15 });
      case "ping2":
        return this.tone(2900, { gain: 0.07, dur: 0.15 });
      case "ping3":
        this.tone(3300, { gain: 0.06, dur: 0.15 });
        return this.tone(2600, { gain: 0.05, dur: 0.2, delay: 0.08 });
      case "streamStart":
        return this.whoosh(800, 2800, 0.6, 0.15);
      case "count":
        return this.tone(1600 + value * 15, { to: 2100 + value * 15, dur: 0.07, gain: 0.05 });
      case "swoosh":
        return this.whoosh(3000, 900, 0.6, 0.2);
      case "finale":
        this.tink(1000, 0.25);
        this.tink(1600, 0.12, 0.03);
        this.tink(2400, 0.06, 0.06);
        return this.tone(350, { dur: 0.6, gain: 0.18, attack: 0.02 });
      case "settle":
        this.tone(3000, { gain: 0.05, dur: 0.2 });
        return this.tone(2400, { gain: 0.06, dur: 0.8, delay: 0.05 });
    }
  }
}
