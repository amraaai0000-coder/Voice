import 'dart:convert';
import 'dart:html' as html;
import 'dart:js' as js;
import 'dart:js_util' as js_util;
import 'dart:math' as math;
import 'package:flutter/material.dart';

void main() {
  runApp(const MaterialApp(
    debugShowCheckedModeBanner: false,
    home: VoiceChatScreen(),
  ));
}

enum VoiceState { idle, listening, thinking, speaking }

class VoiceChatScreen extends StatefulWidget {
  const VoiceChatScreen({super.key});
  @override
  State<VoiceChatScreen> createState() => _VoiceChatScreenState();
}

class _VoiceChatScreenState extends State<VoiceChatScreen>
    with TickerProviderStateMixin {
  VoiceState _voiceState = VoiceState.idle;

  late AnimationController _orbController;
  late AnimationController _breathController;
  late AnimationController _fadeController;
  late AnimationController _ringController;
  late Animation<double> _fadeAnim;

  static const String _backendUrl = 'https://amraa-voice.onrender.com/chat';

  @override
  void initState() {
    super.initState();

    _orbController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 60),
    )..repeat();

    _breathController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 4000),
    )..repeat(reverse: true);

    _ringController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3000),
    )..repeat(reverse: true);

    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _fadeAnim = CurvedAnimation(parent: _fadeController, curve: Curves.easeOut);
    _fadeController.forward();

    // Auto-start listening after a short delay
    Future.delayed(const Duration(milliseconds: 600), () {
      if (mounted) _startListening();
    });
  }

  // ── Web Speech Recognition ────────────────────────────────────────────────

  void _startListening() {
    if (!mounted) return;
    if (_voiceState == VoiceState.thinking || _voiceState == VoiceState.speaking) return;
    setState(() => _voiceState = VoiceState.listening);
    _startRecognition();
  }

  void _startRecognition() {
    // Get browser SpeechRecognition constructor
    final ctor = js.context['SpeechRecognition'] ?? js.context['webkitSpeechRecognition'];
    if (ctor == null) return;

    final recognition = js.JsObject(ctor);
    recognition['lang'] = 'en-IN';
    recognition['interimResults'] = false;
    recognition['maxAlternatives'] = 1;

    // Called when user finishes speaking — extract transcript and send
    recognition['onresult'] = js.allowInterop((dynamic event) {
      try {
        final results = js_util.getProperty<dynamic>(event, 'results');
        final first = js_util.callMethod<dynamic>(results, 'item', [0]);
        final alt = js_util.callMethod<dynamic>(first, 'item', [0]);
        final transcript = js_util.getProperty<String>(alt, 'transcript').trim();
        if (transcript.isNotEmpty && mounted) {
          _sendToBackend(transcript);
        }
      } catch (_) {}
    });

    // Auto-stop mic when speech ends
    recognition['onspeechend'] = js.allowInterop((dynamic _) {
      try { recognition.callMethod('stop'); } catch (_) {}
    });

    // When session ends — restart if still in listening state (no result came)
    recognition['onend'] = js.allowInterop((dynamic _) {
      if (mounted && _voiceState == VoiceState.listening) {
        Future.delayed(const Duration(milliseconds: 400), () {
          if (mounted && _voiceState == VoiceState.listening) {
            _startRecognition();
          }
        });
      }
    });

    // On error — retry after a moment
    recognition['onerror'] = js.allowInterop((dynamic event) {
      if (mounted && _voiceState == VoiceState.listening) {
        Future.delayed(const Duration(seconds: 1), () {
          if (mounted && _voiceState == VoiceState.listening) {
            _startRecognition();
          }
        });
      }
    });

    try { recognition.callMethod('start'); } catch (_) {}
  }

  // ── Backend Call ──────────────────────────────────────────────────────────

  Future<void> _sendToBackend(String text) async {
    if (!mounted) return;
    setState(() => _voiceState = VoiceState.thinking);

    try {
      final request = await html.HttpRequest.request(
        _backendUrl,
        method: 'POST',
        requestHeaders: {'Content-Type': 'application/json'},
        sendData: jsonEncode({'message': text}),
      );

      if (!mounted) return;

      if (request.status == 200) {
        final data = jsonDecode(request.responseText ?? '{}');
        final reply = (data['response'] ??
                data['message'] ??
                data['text'] ??
                data['reply'] ??
                '')
            .toString()
            .trim();

        if (reply.isNotEmpty) {
          setState(() => _voiceState = VoiceState.speaking);
          _webSpeak(reply);
        } else {
          _startListening();
        }
      } else {
        _startListening();
      }
    } catch (_) {
      if (mounted) _startListening();
    }
  }

  // ── Web TTS ───────────────────────────────────────────────────────────────

  void _webSpeak(String text) {
    // Cancel any previous speech
    html.window.speechSynthesis?.cancel();

    final utterance = html.SpeechSynthesisUtterance(text);
    utterance.lang = 'en-US';
    utterance.rate = 0.92;
    utterance.pitch = 1.0;

    // When speaking finishes → auto start listening again
    utterance.onEnd.listen((_) {
      if (mounted) _startListening();
    });

    html.window.speechSynthesis?.speak(utterance);
  }

  // ── Stop Everything ───────────────────────────────────────────────────────

  void _stopAll() {
    html.window.speechSynthesis?.cancel();
    setState(() => _voiceState = VoiceState.idle);
  }

  @override
  void dispose() {
    _orbController.dispose();
    _breathController.dispose();
    _fadeController.dispose();
    _ringController.dispose();
    html.window.speechSynthesis?.cancel();
    super.dispose();
  }

  void _setVoiceState(VoiceState s) => setState(() => _voiceState = s);

  String get _stateLabel {
    switch (_voiceState) {
      case VoiceState.idle:      return 'STANDBY';
      case VoiceState.listening: return 'LISTENING';
      case VoiceState.thinking:  return 'THINKING';
      case VoiceState.speaking:  return 'SPEAKING';
    }
  }

  void _cycleState() {
    final all = VoiceState.values;
    _setVoiceState(all[(_voiceState.index + 1) % all.length]);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF04030D),
      body: FadeTransition(
        opacity: _fadeAnim,
        child: Stack(
          children: [
            _AmbientGlow(breathAnim: _breathController),
            SafeArea(
              child: Column(
                children: [
                  // ── XPTVOICE Header ──────────────────────────────────────
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
                    child: Row(
                      children: const [
                        Text(
                          'XPTVOICE',
                          style: TextStyle(
                            fontFamily: 'serif',
                            fontSize: 22,
                            color: Color(0xE6DCE4FF),
                            fontWeight: FontWeight.w400,
                            letterSpacing: 1.2,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  _StatusBar(label: _stateLabel, state: _voiceState),
                  Expanded(
                    child: _OrbSection(
                      state: _voiceState,
                      orbAnim: _orbController,
                      ringAnim: _ringController,
                      breathAnim: _breathController,
                      onTap: _cycleState,
                    ),
                  ),
                  _StateChips(current: _voiceState, onSelect: _setVoiceState),
                  const SizedBox(height: 12),
                  // ── Controls (mic icon removed) ──────────────────────────
                  _Controls(
                    state: _voiceState,
                    onEndTap: _stopAll,
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Ambient Glow ─────────────────────────────────────────────────────────────
class _AmbientGlow extends StatelessWidget {
  final AnimationController breathAnim;
  const _AmbientGlow({required this.breathAnim});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: breathAnim,
      builder: (_, __) => Positioned.fill(
        child: Opacity(
          opacity: 0.5 + breathAnim.value * 0.5,
          child: Transform.scale(
            scale: 1.0 + breathAnim.value * 0.1,
            child: Container(
              decoration: const BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment(0, 0.15),
                  radius: 0.85,
                  colors: [Color(0x0DB4BEFF), Colors.transparent],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Status Bar ────────────────────────────────────────────────────────────────
class _StatusBar extends StatelessWidget {
  final String label;
  final VoiceState state;
  const _StatusBar({required this.label, required this.state});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _PulseDot(active: state != VoiceState.idle),
        const SizedBox(width: 8),
        Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            letterSpacing: 3.5,
            color: Color(0x80C8D5FF),
            fontWeight: FontWeight.w300,
          ),
        ),
      ],
    );
  }
}

class _PulseDot extends StatefulWidget {
  final bool active;
  const _PulseDot({required this.active});
  @override
  State<_PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<_PulseDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _c;
  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: const Duration(seconds: 2))
      ..repeat(reverse: true);
  }
  @override
  void dispose() { _c.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (_, __) => Container(
        width: 5, height: 5,
        decoration: BoxDecoration(
          color: const Color(0xFFC8D5FF),
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Color.fromRGBO(200, 213, 255, 0.6 * _c.value),
              blurRadius: 6,
              spreadRadius: _c.value * 3,
            ),
          ],
        ),
      ),
    );
  }
}

// ── Orb Section ───────────────────────────────────────────────────────────────
class _OrbSection extends StatelessWidget {
  final VoiceState state;
  final AnimationController orbAnim, ringAnim, breathAnim;
  final VoidCallback onTap;

  const _OrbSection({
    required this.state, required this.orbAnim,
    required this.ringAnim, required this.breathAnim,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SizedBox(
        width: 440, height: 440,
        child: Stack(
          alignment: Alignment.center,
          children: [
            _AnimatedRing(anim: ringAnim, size: 320, delay: 0.0),
            _AnimatedRing(anim: ringAnim, size: 380, delay: 0.16),
            _AnimatedRing(anim: ringAnim, size: 440, delay: 0.33),
            GestureDetector(
              onTap: onTap,
              child: AnimatedBuilder(
                animation: orbAnim,
                builder: (_, __) => CustomPaint(
                  size: const Size(280, 280),
                  painter: _OrbPainter(t: orbAnim.value * math.pi * 2, state: state),
                ),
              ),
            ),
            Positioned(
              bottom: 62,
              child: AnimatedBuilder(
                animation: breathAnim,
                builder: (_, __) => Opacity(
                  opacity: 0.5 + breathAnim.value * 0.5,
                  child: Container(
                    width: 160, height: 24,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(80),
                      boxShadow: const [
                        BoxShadow(color: Color(0x33B4BEFF), blurRadius: 18, spreadRadius: 4),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AnimatedRing extends StatelessWidget {
  final Animation<double> anim;
  final double size, delay;
  const _AnimatedRing({required this.anim, required this.size, required this.delay});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: anim,
      builder: (_, __) {
        final pulse = math.sin(((anim.value + delay) % 1.0) * math.pi * 2);
        return Transform.scale(
          scale: 1.0 + pulse * 0.04,
          child: Opacity(
            opacity: (0.6 + pulse * 0.4).clamp(0.0, 1.0),
            child: Container(
              width: size, height: size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: Color.fromRGBO(200, 210, 255, (0.09 * (1 - delay * 2)).clamp(0.0, 1.0)),
                  width: 1,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

// ── Orb Painter ───────────────────────────────────────────────────────────────
class _OrbPainter extends CustomPainter {
  final double t;
  final VoiceState state;

  static final _rng  = math.Random(42);
  static final _rng2 = math.Random(99);

  static final List<_BlobPoint> _blobs = List.generate(9, (i) => _BlobPoint(
    angle: (i / 9) * math.pi * 2,
    speed: 0.002 + _rng.nextDouble() * 0.003,
    off:   _rng.nextDouble() * math.pi * 2,
    amp:   10 + _rng.nextDouble() * 16,
  ));

  static final List<_ThinkLine> _thinkLines = List.generate(6, (i) {
    final r = math.Random(i * 17);
    return _ThinkLine(
      angle: (i / 6) * math.pi * 2,
      speed: 0.003 + r.nextDouble() * 0.003,
      phase: r.nextDouble() * math.pi * 2,
    );
  });

  static final List<_Particle> _particles = List.generate(55, (_) => _Particle.random(_rng2));
  static final List<_WaveRing> _waves = [];
  static double _waveT = 0;

  static const int    _nodeCount = 12;
  static const double _nodeR     = 0.82;

  _OrbPainter({required this.t, required this.state});

  double get _intensity => switch (state) {
    VoiceState.speaking  => 1.0,
    VoiceState.listening => 0.75,
    VoiceState.thinking  => 0.6,
    VoiceState.idle      => 0.3,
  };

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2, cy = size.height / 2, R = size.width / 2;
    canvas.clipPath(Path()..addOval(Rect.fromCircle(center: Offset(cx, cy), radius: R)));
    _drawBg(canvas, size, cx, cy, R);
    _drawGeometry(canvas, cx, cy, R);
    _drawBlob(canvas, cx, cy, R);
    if (state == VoiceState.speaking)  _drawWaves(canvas, cx, cy, R);
    if (state == VoiceState.listening) _drawListenRing(canvas, cx, cy, R);
    if (state == VoiceState.thinking)  _drawThinkLines(canvas, cx, cy, R);
    _drawParticles(canvas, cx, cy, R);
    _drawCoreGlow(canvas, cx, cy, R);
    _drawLens(canvas, cx, cy, R);
    _drawVignette(canvas, cx, cy, R);
  }

  void _drawBg(Canvas canvas, Size size, double cx, double cy, double R) {
    final i = _intensity;
    final cR = (20 + i * 55).round();
    final cG = (18 + i * 48).round();
    final cB = (38 + i * 80).round();
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..shader = RadialGradient(
        center: const Alignment(-0.28, -0.36), radius: 1.0,
        colors: [
          Color.fromRGBO(cR, cG, cB, 0.97),
          Color.fromRGBO((cR * 0.35).round(), (cG * 0.35).round(), (cB * 0.55).round(), 0.97),
          const Color(0xFF05040E), const Color(0xFF020108),
        ],
        stops: const [0.0, 0.35, 0.7, 1.0],
      ).createShader(Rect.fromCircle(center: Offset(cx, cy), radius: R)));
  }

  void _drawGeometry(Canvas canvas, double cx, double cy, double R) {
    final gA = switch (state) {
      VoiceState.thinking  => 0.55,
      VoiceState.listening => 0.35,
      VoiceState.speaking  => 0.28,
      VoiceState.idle      => 0.18,
    };
    final nr = R * _nodeR;
    canvas.save();
    canvas.translate(cx, cy);
    canvas.rotate(t * (state == VoiceState.thinking ? 0.008 : 0.002));
    canvas.translate(-cx, -cy);

    final pts = List.generate(_nodeCount, (i) {
      final a = (i / _nodeCount) * math.pi * 2 - math.pi / 2;
      return Offset(cx + math.cos(a) * nr, cy + math.sin(a) * nr);
    });

    for (final skip in [4, 5, 3]) {
      for (int i = 0; i < _nodeCount; i++) {
        final j = (i + skip) % _nodeCount;
        if (i >= j) continue;
        canvas.drawLine(pts[i], pts[j],
          Paint()..style = PaintingStyle.stroke..strokeWidth = 0.8
            ..shader = LinearGradient(colors: [
              const Color(0x00C8D5FF),
              Color.fromRGBO(220, 228, 255, gA),
              const Color(0x00C8D5FF),
            ]).createShader(Rect.fromPoints(pts[i], pts[j])));
      }
    }

    canvas.drawCircle(Offset(cx, cy), nr,
      Paint()..style = PaintingStyle.stroke..strokeWidth = 1.0
        ..color = Color.fromRGBO(200, 210, 255, gA * 0.6));
    canvas.drawCircle(Offset(cx, cy), nr * 0.45,
      Paint()..style = PaintingStyle.stroke..strokeWidth = 0.7
        ..color = Color.fromRGBO(200, 210, 255, gA * 0.4));

    final np = 0.7 + math.sin(t * 1.8) * 0.3;
    for (final pt in pts) {
      canvas.drawCircle(pt, 7,
        Paint()..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4)
          ..color = Color.fromRGBO(255, 255, 255, (gA * np * 1.4).clamp(0, 1)));
      canvas.drawCircle(pt, 2,
        Paint()..color = Color.fromRGBO(255, 255, 255, (gA * np * 2).clamp(0, 1)));
    }
    canvas.restore();
  }

  void _drawBlob(Canvas canvas, double cx, double cy, double R) {
    final offsets = _blobs.map((b) {
      final a = b.angle + t * b.speed;
      final r = R * 0.82 + math.sin(t * 0.6 + b.off) * b.amp;
      return Offset(cx + math.cos(a) * r, cy + math.sin(a) * r);
    }).toList();

    final path = Path()..moveTo(offsets[0].dx, offsets[0].dy);
    for (int i = 0; i < offsets.length; i++) {
      final c = offsets[i], n = offsets[(i + 1) % offsets.length];
      final a = math.atan2(n.dy - c.dy, n.dx - c.dx);
      final d = (c - Offset(cx, cy)).distance * 0.88;
      path.cubicTo(
        c.dx + math.cos(a + 0.35) * d, c.dy + math.sin(a + 0.35) * d,
        c.dx + math.cos(a + 0.35) * d, c.dy + math.sin(a + 0.35) * d,
        n.dx, n.dy,
      );
    }
    path.close();
    canvas.drawPath(path, Paint()
      ..color = Color.fromRGBO(160, 175, 255,
        0.06 + math.sin(t * (state == VoiceState.speaking ? 0.9 : 0.4)) * 0.03));
  }

  void _drawWaves(Canvas canvas, double cx, double cy, double R) {
    _waveT += 0.04;
    if (_waveT > 0.55) { _waves.add(_WaveRing(r: 8, life: 1)); _waveT = 0; }
    _waves.removeWhere((w) => w.life <= 0);
    for (final w in _waves) {
      w.r += 4; w.life -= 0.02;
      if (w.r > R * 0.88) w.life = 0;
      canvas.drawCircle(Offset(cx, cy), w.r,
        Paint()..style = PaintingStyle.stroke..strokeWidth = 1.5
          ..color = Color.fromRGBO(220, 228, 255, (w.life * 0.22).clamp(0, 1)));
    }
  }

  void _drawListenRing(Canvas canvas, double cx, double cy, double R) {
    canvas.drawCircle(Offset(cx, cy), R * (0.74 + math.sin(t * 1.3) * 0.07),
      Paint()..style = PaintingStyle.stroke..strokeWidth = 1.8
        ..color = Color.fromRGBO(220, 228, 255, 0.2 + math.sin(t * 1.3) * 0.12));
  }

  void _drawThinkLines(Canvas canvas, double cx, double cy, double R) {
    for (final l in _thinkLines) {
      l.angle += l.speed;
      final p1 = Offset(cx + math.cos(l.angle) * R * (0.12 + math.sin(t * 0.4 + l.phase) * 0.08),
                        cy + math.sin(l.angle) * R * (0.12 + math.sin(t * 0.4 + l.phase) * 0.08));
      final p2 = Offset(cx + math.cos(l.angle + math.pi) * R * (0.72 + math.sin(t * 0.3 + l.phase) * 0.1),
                        cy + math.sin(l.angle + math.pi) * R * (0.72 + math.sin(t * 0.3 + l.phase) * 0.1));
      canvas.drawLine(p1, p2,
        Paint()..style = PaintingStyle.stroke..strokeWidth = 1.0
          ..shader = LinearGradient(colors: const [
            Color(0x00DCE4FF), Color(0x6BF0F4FF), Color(0x00DCE4FF),
          ]).createShader(Rect.fromPoints(p1, p2)));
    }
  }

  void _drawParticles(Canvas canvas, double cx, double cy, double R) {
    final spd = switch (state) {
      VoiceState.idle      => 0.3,
      VoiceState.thinking  => 0.7,
      VoiceState.speaking  => 2.0,
      VoiceState.listening => 1.0,
    };
    for (final p in _particles) {
      p.x += p.vx * spd; p.y += p.vy * spd; p.life -= 0.004 * spd;
      if (p.life <= 0 || math.sqrt((p.x-cx)*(p.x-cx)+(p.y-cy)*(p.y-cy)) > R*0.9) {
        p.reset(_rng2, cx, cy, R);
      }
      final a = (math.max(0, p.life/p.maxLife) * (state==VoiceState.idle?0.22:0.52)).clamp(0.0,1.0);
      canvas.drawCircle(Offset(p.x, p.y), p.size,
        Paint()..color = HSVColor.fromAHSV(a, p.hue, 0.35, 0.92).toColor());
    }
  }

  void _drawCoreGlow(Canvas canvas, double cx, double cy, double R) {
    final i = _intensity;
    final cs = R * switch (state) {
      VoiceState.speaking  => 0.22,
      VoiceState.listening => 0.16,
      VoiceState.thinking  => 0.18,
      VoiceState.idle      => 0.12,
    };
    canvas.drawCircle(Offset(cx, cy), cs, Paint()
      ..shader = RadialGradient(colors: [
        Color.fromRGBO(255, 255, 255, i * 0.7),
        Color.fromRGBO(210, 220, 255, i * 0.35),
        const Color(0x00A0AFFF),
      ]).createShader(Rect.fromCircle(center: Offset(cx, cy), radius: cs)));
  }

  void _drawLens(Canvas canvas, double cx, double cy, double R) {
    canvas.drawRect(Rect.fromLTWH(0, 0, cx*2, cy*2), Paint()
      ..shader = const RadialGradient(
        center: Alignment(-0.4, -0.46), radius: 0.65,
        colors: [Color(0x14FFFFFF), Color(0x05FFFFFF), Color(0x00000000)],
        stops: [0.0, 0.4, 1.0],
      ).createShader(Rect.fromCircle(center: Offset.zero, radius: R)));
  }

  void _drawVignette(Canvas canvas, double cx, double cy, double R) {
    canvas.drawRect(Rect.fromLTWH(0, 0, cx*2, cy*2), Paint()
      ..shader = RadialGradient(
        radius: 1.0,
        colors: const [Color(0x00000000), Color(0xA6000000)],
        stops: const [0.38, 1.0],
      ).createShader(Rect.fromCircle(center: Offset(cx, cy), radius: R)));
  }

  @override
  bool shouldRepaint(_OrbPainter old) => old.t != t || old.state != state;
}

// ── State Chips ───────────────────────────────────────────────────────────────
class _StateChips extends StatelessWidget {
  final VoiceState current;
  final ValueChanged<VoiceState> onSelect;
  const _StateChips({required this.current, required this.onSelect});

  static const _labels = {
    VoiceState.idle:      'IDLE',
    VoiceState.listening: 'LISTEN',
    VoiceState.speaking:  'SPEAK',
    VoiceState.thinking:  'THINK',
  };

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: VoiceState.values.map((s) {
        final active = s == current;
        return GestureDetector(
          onTap: () => onSelect(s),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            margin: const EdgeInsets.symmetric(horizontal: 4),
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 5),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: active ? const Color(0x73C8D5FF) : Colors.white.withOpacity(0.1),
              ),
              color: active ? const Color(0x14B4BEFF) : Colors.transparent,
            ),
            child: Text(
              _labels[s]!,
              style: TextStyle(
                fontSize: 10, letterSpacing: 2, fontWeight: FontWeight.w300,
                color: active ? const Color(0xE6DCE4FF) : Colors.white.withOpacity(0.3),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

// ── Controls (mic icon removed) ───────────────────────────────────────────────
class _Controls extends StatelessWidget {
  final VoiceState state;
  final VoidCallback onEndTap;
  const _Controls({required this.state, required this.onEndTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 50),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _CtrlBtn(
            onTap: onEndTap, size: 60,
            bgColor: const Color(0x1AFF3C3C),
            borderColor: const Color(0x38FF3C3C),
            child: const Icon(Icons.call_end, color: Color(0xBFFF6464), size: 22),
          ),
          _CtrlBtn(
            size: 52,
            child: Icon(Icons.tune_rounded, color: Colors.white.withOpacity(0.4), size: 20),
          ),
        ],
      ),
    );
  }
}

class _CtrlBtn extends StatelessWidget {
  final double size;
  final Widget child;
  final VoidCallback? onTap;
  final bool active;
  final Color? bgColor, borderColor;

  const _CtrlBtn({
    required this.size, required this.child,
    this.onTap, this.active = false,
    this.bgColor, this.borderColor,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: size, height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: active ? const Color(0x1AC8D5FF) : (bgColor ?? Colors.white.withOpacity(0.04)),
          border: Border.all(
            color: active ? const Color(0x66C8D5FF) : (borderColor ?? Colors.white.withOpacity(0.08)),
          ),
        ),
        child: Center(child: child),
      ),
    );
  }
}

// ── Data Classes ──────────────────────────────────────────────────────────────
class _BlobPoint {
  double angle, speed, off, amp;
  _BlobPoint({required this.angle, required this.speed, required this.off, required this.amp});
}

class _WaveRing {
  double r, life;
  _WaveRing({required this.r, required this.life});
}

class _ThinkLine {
  double angle, speed, phase;
  _ThinkLine({required this.angle, required this.speed, required this.phase});
}

class _Particle {
  double x, y, vx, vy, life, maxLife, size, hue;
  _Particle({
    required this.x, required this.y, required this.vx, required this.vy,
    required this.life, required this.maxLife, required this.size, required this.hue,
  });

  factory _Particle.random(math.Random rng) {
    final a = rng.nextDouble() * math.pi * 2;
    final r = (0.08 + rng.nextDouble() * 0.75) * 140.0;
    return _Particle(
      x: 140 + math.cos(a) * r, y: 140 + math.sin(a) * r,
      vx: (rng.nextDouble() - 0.5) * 0.5, vy: (rng.nextDouble() - 0.5) * 0.5,
      life: rng.nextDouble(), maxLife: 0.5 + rng.nextDouble() * 0.5,
      size: 0.6 + rng.nextDouble() * 1.8, hue: 210 + rng.nextDouble() * 40,
    );
  }

  void reset(math.Random rng, double cx, double cy, double R) {
    final a = rng.nextDouble() * math.pi * 2;
    final r = (0.08 + rng.nextDouble() * 0.75) * R;
    x = cx + math.cos(a) * r; y = cy + math.sin(a) * r;
    vx = (rng.nextDouble() - 0.5) * 0.5; vy = (rng.nextDouble() - 0.5) * 0.5;
    life = rng.nextDouble(); maxLife = 0.5 + rng.nextDouble() * 0.5;
    size = 0.6 + rng.nextDouble() * 1.8; hue = 210 + rng.nextDouble() * 40;
  }
}
