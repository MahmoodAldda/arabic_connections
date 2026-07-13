// Synthesizes the game's sound effects as small 16-bit PCM WAV files under
// assets/sfx/. Keeping generation in-repo means the audio is reproducible and
// tweakable without shipping opaque binaries we can't regenerate.
//
// Run from the project root:  dart run tool/generate_sounds.dart
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

const int _sampleRate = 22050;

/// One shaped segment: [ms] of `f(t)` with short attack/release ramps so the
/// tone starts and ends without an audible click.
List<double> _seg(
  int ms,
  double Function(double t) f, {
  double attackMs = 4,
  double releaseMs = 30,
}) {
  final n = (_sampleRate * ms / 1000).round();
  final a = _sampleRate * attackMs / 1000;
  final r = _sampleRate * releaseMs / 1000;
  final out = List<double>.filled(n, 0);
  for (var i = 0; i < n; i++) {
    final t = i / _sampleRate;
    var env = 1.0;
    if (i < a) env = i / a;
    if (i > n - r) env = max(0, (n - i) / r);
    out[i] = f(t) * env;
  }
  return out;
}

double _sine(double freq, double t) => sin(2 * pi * freq * t);

List<double> _tone(double freq, int ms, {double vol = 0.6}) =>
    _seg(ms, (t) => _sine(freq, t) * vol);

/// A gentle two-partial tone (fundamental + soft octave) for a warmer timbre.
List<double> _bell(double freq, int ms, {double vol = 0.6}) => _seg(
      ms,
      (t) => (_sine(freq, t) + 0.35 * _sine(freq * 2, t)) * vol * 0.75,
      releaseMs: ms * 0.6,
    );

List<double> _silence(int ms) => List<double>.filled((_sampleRate * ms / 1000).round(), 0);

void _writeWav(String path, List<double> samples) {
  final n = samples.length;
  final pcm = Uint8List(n * 2);
  final view = ByteData.view(pcm.buffer);
  for (var i = 0; i < n; i++) {
    final v = (samples[i].clamp(-1.0, 1.0) * 32767).round();
    view.setInt16(i * 2, v, Endian.little);
  }

  final header = BytesBuilder();
  void str(String s) => header.add(ascii.encode(s));
  void u32(int v) =>
      header.add((ByteData(4)..setUint32(0, v, Endian.little)).buffer.asUint8List());
  void u16(int v) =>
      header.add((ByteData(2)..setUint16(0, v, Endian.little)).buffer.asUint8List());

  str('RIFF');
  u32(36 + n * 2);
  str('WAVE');
  str('fmt ');
  u32(16); // PCM chunk size
  u16(1); // PCM format
  u16(1); // mono
  u32(_sampleRate);
  u32(_sampleRate * 2); // byte rate
  u16(2); // block align
  u16(16); // bits per sample
  str('data');
  u32(n * 2);

  File(path).writeAsBytesSync(header.toBytes() + pcm);
}

void main() {
  Directory('assets/sfx').createSync(recursive: true);
  final rng = Random(7);

  final effects = <String, List<double>>{
    // Crisp, quiet UI blips.
    'card_tap': _tone(880, 55, vol: 0.45),
    'card_move': _tone(620, 70, vol: 0.5),
    'button': _tone(1040, 45, vol: 0.4),
    // Rising two-note "correct" chime.
    'correct': [..._bell(660, 110, vol: 0.6), ..._bell(990, 170, vol: 0.6)],
    // Low, short descending buzz for a wrong move.
    'wrong': _seg(220, (t) => _sine(180 - 90 * t, t) * 0.5, releaseMs: 60),
    // Soft filtered-ish noise sweep for shuffling.
    'shuffle': _seg(260, (_) => (rng.nextDouble() * 2 - 1) * 0.25,
        attackMs: 20, releaseMs: 140),
    // Victory arpeggio C-E-G-C.
    'victory': [
      ..._bell(523.25, 120, vol: 0.6),
      ..._bell(659.25, 120, vol: 0.6),
      ..._bell(783.99, 120, vol: 0.6),
      ..._bell(1046.5, 260, vol: 0.65),
    ],
    // Bright coin double-blip.
    'coins': [
      ..._tone(1568, 60, vol: 0.5),
      ..._silence(20),
      ..._tone(2093, 90, vol: 0.5),
    ],
  };

  effects.forEach((name, samples) {
    _writeWav('assets/sfx/$name.wav', samples);
    stdout.writeln('Wrote assets/sfx/$name.wav (${samples.length} samples)');
  });
}
