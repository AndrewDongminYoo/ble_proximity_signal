import 'dart:async';
import 'dart:developer';
import 'package:ble_proximity_signal/ble_proximity_signal.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF3C5E57)),
      textTheme: Theme.of(context).textTheme.apply(
        bodyColor: const Color(0xFFE8F3EF),
        displayColor: const Color(0xFFE8F3EF),
      ),
    );
    return MaterialApp(
      theme: theme,
      home: const HomePage(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final BleProximitySignal _ble = BleProximitySignal();
  final TextEditingController _broadcastController = TextEditingController(text: 'a1b2c3d4');
  final TextEditingController _targetController = TextEditingController(text: 'a1b2c3d4');

  StreamSubscription<ProximityEvent>? _subscription;
  StreamSubscription<RawScanResult>? _rawSubscription;
  Timer? _beepTimer;
  Timer? _beepFlashTimer;

  ProximityEvent? _lastEvent;
  final List<RawScanResult> _rawLog = <RawScanResult>[];
  static const int _rawLogMax = 12;
  bool _scanning = false;
  bool _broadcasting = false;
  bool _beepOn = false;
  double _intensity = 0;
  int _beepIntervalMs = 0;
  ProximityLevel _level = ProximityLevel.far;
  bool _debugAllowAll = false;

  @override
  void dispose() {
    unawaited(_ble.dispose());
    unawaited(_subscription?.cancel());
    unawaited(_rawSubscription?.cancel());
    _beepTimer?.cancel();
    _beepFlashTimer?.cancel();
    _broadcastController.dispose();
    _targetController.dispose();
    super.dispose();
  }

  Future<void> _startBroadcast() async {
    final token = _broadcastController.text.trim();
    if (token.isEmpty) {
      _showError('Broadcast token is empty.');
      return;
    }
    try {
      await _ble.startBroadcast(token: token);
      setState(() => _broadcasting = true);
    } on Object catch (error) {
      _showError('Broadcast failed: $error');
    }
  }

  Future<void> _stopBroadcast() async {
    try {
      await _ble.stopBroadcast();
    } on Object catch (error) {
      _showError('Stop broadcast failed: $error');
    } finally {
      if (mounted) {
        setState(() => _broadcasting = false);
      }
    }
  }

  Future<void> _startScan() async {
    final token = _targetController.text.trim();
    if (!_debugAllowAll && token.isEmpty) {
      _showError('Target token is empty.');
      return;
    }

    final targets = _debugAllowAll ? <String>[] : <String>[token];

    await _subscription?.cancel();
    _subscription = _ble.events.listen(
      _handleEvent,
      onError: (Object? error) {
        _showError('Scan error: $error');
      },
    );
    await _rawSubscription?.cancel();
    _rawSubscription = _ble.rawScanResults.listen(
      _handleRaw,
      onError: (Object? error) {
        if (_debugAllowAll) {
          _showError('Raw scan error: $error');
        }
      },
    );

    _ble.rawScanLog(maxEntries: 50).listen((buffer) {
      if (buffer.isEmpty) return;
      log(buffer.first.toString());
    });

    try {
      await _ble.startScan(
        targetTokens: targets,
        config: ScanConfig(debugAllowAll: _debugAllowAll),
      );
      setState(() => _scanning = true);
    } on Object catch (error) {
      await _subscription?.cancel();
      _subscription = null;
      await _rawSubscription?.cancel();
      _rawSubscription = null;
      _showError('Start scan failed: $error');
    }
  }

  Future<void> _stopScan() async {
    try {
      await _ble.stopScan();
    } on Object catch (error) {
      _showError('Stop scan failed: $error');
    } finally {
      await _subscription?.cancel();
      _subscription = null;
      await _rawSubscription?.cancel();
      _rawSubscription = null;
      _beepTimer?.cancel();
      _beepFlashTimer?.cancel();
      if (mounted) {
        setState(() {
          _scanning = false;
          _beepOn = false;
          _intensity = 0;
          _beepIntervalMs = 0;
          _level = ProximityLevel.far;
          _lastEvent = null;
          _rawLog.clear();
        });
      }
    }
  }

  void _handleRaw(RawScanResult raw) {
    if (!_debugAllowAll) {
      return;
    }
    if (mounted) {
      setState(() {
        _rawLog.insert(0, raw);
        if (_rawLog.length > _rawLogMax) {
          _rawLog.removeRange(_rawLogMax, _rawLog.length);
        }
      });
    }
  }

  void _handleEvent(ProximityEvent event) {
    final intensity = event.intensity.clamp(0, 1).toDouble();
    final interval = _intervalForIntensity(intensity);
    if (interval == null) {
      _beepTimer?.cancel();
      _beepFlashTimer?.cancel();
      _beepTimer = null;
      _beepFlashTimer = null;
      _beepOn = false;
    } else if (interval != _beepIntervalMs) {
      _beepTimer?.cancel();
      _beepTimer = Timer.periodic(Duration(milliseconds: interval), (_) {
        _beepFlashTimer?.cancel();
        _beepFlashTimer = Timer(const Duration(milliseconds: 90), () {
          if (mounted) {
            setState(() => _beepOn = false);
          }
        });
        if (mounted) {
          unawaited(SystemSound.play(SystemSoundType.click));
          setState(() => _beepOn = true);
        }
      });
    }

    if (mounted) {
      setState(() {
        _lastEvent = event;
        _intensity = intensity;
        _beepIntervalMs = interval ?? 0;
        _level = event.level;
      });
    }
  }

  int? _intervalForIntensity(double intensity) {
    if (intensity <= 0) {
      return null;
    }
    const minMs = 140;
    const maxMs = 1200;

    // 12-step quantization
    const steps = 12;
    final stepped = (intensity * (steps - 1)).round() / (steps - 1);

    final t = (1 - stepped).clamp(0, 1);
    return (minMs + (maxMs - minMs) * t).round();
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final intensityColor = Color.lerp(
      const Color(0xFF28423B),
      const Color(0xFFFFC857),
      _intensity,
    );
    final signalLabel = _level.name.toUpperCase();

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF0D1C19), Color(0xFF1C2E28)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
            children: [
              const Text(
                'Metal Detector',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                _scanning ? 'Scanning…' : 'Idle',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.7),
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 24),
              _SignalCard(
                intensity: _intensity,
                levelLabel: signalLabel,
                color: intensityColor ?? Colors.white,
                beepOn: _beepOn,
                intervalMs: _beepIntervalMs,
                rssi: _lastEvent?.rssi,
                smoothRssi: _lastEvent?.smoothRssi,
                deviceId: _lastEvent?.deviceId,
                deviceName: _lastEvent?.deviceName,
                localName: _lastEvent?.localName,
                manufacturerDataLen: _lastEvent?.manufacturerDataLen,
              ),
              const SizedBox(height: 24),
              _DebugCard(
                enabled: _debugAllowAll,
                onChanged: _scanning ? null : (value) => setState(() => _debugAllowAll = value),
              ),
              if (_debugAllowAll) ...[
                const SizedBox(height: 12),
                _RawLogCard(entries: _rawLog),
              ],
              const SizedBox(height: 16),
              _TokenCard(
                title: 'Target Token',
                controller: _targetController,
                enabled: !_debugAllowAll,
                actionLabel: _scanning ? 'Stop Scan' : 'Start Scan',
                onAction: _scanning ? _stopScan : _startScan,
                active: _scanning,
              ),
              const SizedBox(height: 16),
              _TokenCard(
                title: 'Broadcast Token',
                controller: _broadcastController,
                actionLabel: _broadcasting ? 'Stop Broadcast' : 'Start Broadcast',
                onAction: _broadcasting ? _stopBroadcast : _startBroadcast,
                active: _broadcasting,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SignalCard extends StatelessWidget {
  const _SignalCard({
    required this.intensity,
    required this.levelLabel,
    required this.color,
    required this.beepOn,
    required this.intervalMs,
    required this.rssi,
    required this.smoothRssi,
    required this.deviceId,
    required this.deviceName,
    required this.localName,
    required this.manufacturerDataLen,
  });

  final double intensity;
  final String levelLabel;
  final Color color;
  final bool beepOn;
  final int intervalMs;
  final int? rssi;
  final double? smoothRssi;
  final String? deviceId;
  final String? deviceName;
  final String? localName;
  final int? manufacturerDataLen;

  @override
  Widget build(BuildContext context) {
    final textColor = Colors.white.withValues(alpha: 0.9);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF142320),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Signal',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: textColor,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  levelLabel,
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.1,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _IntensityBar(intensity: intensity, color: color),
          const SizedBox(height: 18),
          Row(
            children: [
              _BeepIndicator(beepOn: beepOn, color: color),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  intervalMs == 0 ? 'No signal' : 'Beep interval: ${intervalMs}ms',
                  style: TextStyle(color: textColor, fontSize: 14),
                ),
              ),
              Text(
                '${(intensity * 100).round()}%',
                style: TextStyle(
                  color: textColor,
                  fontWeight: FontWeight.w600,
                  fontSize: 16,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 16,
            runSpacing: 8,
            children: [
              _MetricChip(label: 'RSSI', value: rssi?.toString() ?? '--'),
              _MetricChip(
                label: 'Smooth',
                value: smoothRssi == null ? '--' : smoothRssi!.toStringAsFixed(1),
              ),
              if (deviceId != null) _MetricChip(label: 'Device ID', value: deviceId!),
              if (deviceName != null) _MetricChip(label: 'Device Name', value: deviceName!),
              if (localName != null) _MetricChip(label: 'Local Name', value: localName!),
              if (manufacturerDataLen != null)
                _MetricChip(
                  label: 'MFG Len',
                  value: manufacturerDataLen.toString(),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _IntensityBar extends StatelessWidget {
  const _IntensityBar({required this.intensity, required this.color});

  final double intensity;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final fillWidth = width * intensity;
        return Container(
          height: 28,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Stack(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOutCubic,
                width: fillWidth,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  gradient: LinearGradient(
                    colors: [
                      color.withValues(alpha: 0.4),
                      color,
                    ],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: color.withValues(alpha: 0.5),
                      blurRadius: 12,
                      spreadRadius: -2,
                    ),
                  ],
                ),
              ),
              Center(
                child: Text(
                  'INTENSITY',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.7),
                    letterSpacing: 2.2,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _BeepIndicator extends StatelessWidget {
  const _BeepIndicator({required this.beepOn, required this.color});

  final bool beepOn;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final size = beepOn ? 38.0 : 30.0;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: beepOn ? color : color.withValues(alpha: 0.2),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: beepOn ? 0.6 : 0.2),
            blurRadius: beepOn ? 16 : 6,
          ),
        ],
      ),
      child: Center(
        child: Icon(
          Icons.sensors,
          size: 18,
          color: beepOn ? Colors.black : Colors.white.withValues(alpha: 0.7),
        ),
      ),
    );
  }
}

class _MetricChip extends StatelessWidget {
  const _MetricChip({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        '$label: $value',
        style: TextStyle(color: Colors.white.withValues(alpha: 0.85)),
      ),
    );
  }
}

class _DebugCard extends StatelessWidget {
  const _DebugCard({
    required this.enabled,
    required this.onChanged,
  });

  final bool enabled;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF162723),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Debug: scan all peripherals',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.9),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Switch.adaptive(value: enabled, onChanged: onChanged),
        ],
      ),
    );
  }
}

class _RawLogCard extends StatelessWidget {
  const _RawLogCard({required this.entries});

  final List<RawScanResult> entries;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF142320),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Raw Scan Log',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.9),
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 10),
          if (entries.isEmpty)
            Text(
              'No raw scans yet.',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.6)),
            )
          else
            for (final entry in entries)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  _formatRawEntry(entry),
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.75),
                    fontSize: 12,
                  ),
                ),
              ),
        ],
      ),
    );
  }

  String _formatRawEntry(RawScanResult entry) {
    final label = entry.localName ?? entry.deviceName ?? entry.deviceId ?? entry.targetToken;
    final mfg = entry.manufacturerDataLen == null ? '' : ' • mfg:${entry.manufacturerDataLen}';
    final svcLen = entry.serviceDataLen == null ? '' : ' • svcLen:${entry.serviceDataLen}';
    final svcDataUuids = (entry.serviceDataUuids == null || entry.serviceDataUuids!.isEmpty)
        ? ''
        : ' • svcData:${entry.serviceDataUuids!.join(",")}';
    final svcUuids = (entry.serviceUuids == null || entry.serviceUuids!.isEmpty)
        ? ''
        : ' • svc:${entry.serviceUuids!.join(",")}';
    return '${entry.rssi}dBm • $label$mfg$svcLen$svcDataUuids$svcUuids';
  }
}

class _TokenCard extends StatelessWidget {
  const _TokenCard({
    required this.title,
    required this.controller,
    required this.actionLabel,
    required this.onAction,
    required this.active,
    this.enabled = true,
  });

  final String title;
  final TextEditingController controller;
  final String actionLabel;
  final VoidCallback onAction;
  final bool active;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF162723),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.9),
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: controller,
            enabled: enabled,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: 'hex or base64url',
              hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.4)),
              filled: true,
              fillColor: Colors.white.withValues(alpha: 0.05),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: onAction,
              style: FilledButton.styleFrom(
                backgroundColor: active ? const Color(0xFFFF6B5F) : const Color(0xFF66CDAA),
                foregroundColor: Colors.black,
              ),
              child: Text(actionLabel),
            ),
          ),
        ],
      ),
    );
  }
}
