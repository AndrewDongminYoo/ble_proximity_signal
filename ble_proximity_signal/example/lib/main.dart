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
  Timer? _deviceRefreshTimer;

  ProximityEvent? _lastEvent;
  final Map<String, RawScanResult> _deviceCache = <String, RawScanResult>{};
  final Map<String, String> _lastDiscoveryDumpByDeviceId = {};
  final Map<String, int> _lastDiscoveryLoggedAtMsByDeviceId = {};
  static const int _discoveryLogDedupeWindowMs = 1500;
  List<RawScanResult> _visibleDevices = <RawScanResult>[];
  final Set<String> _connectingDeviceIds = <String>{};
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
    _deviceRefreshTimer?.cancel();
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
    _deviceCache.clear();
    _visibleDevices = <RawScanResult>[];
    _deviceRefreshTimer?.cancel();

    try {
      await _ble.startScan(
        targetTokens: targets,
        config: ScanConfig(debugAllowAll: _debugAllowAll),
      );
      if (_debugAllowAll) {
        _startDeviceRefreshTimer();
      }
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
      _deviceRefreshTimer?.cancel();
      if (mounted) {
        setState(() {
          _scanning = false;
          _beepOn = false;
          _intensity = 0;
          _beepIntervalMs = 0;
          _level = ProximityLevel.far;
          _lastEvent = null;
          _deviceCache.clear();
          _visibleDevices = <RawScanResult>[];
          _connectingDeviceIds.clear();
        });
      }
    }
  }

  void _handleRaw(RawScanResult raw) {
    if (!_debugAllowAll) {
      return;
    }
    final key = raw.deviceId ?? raw.targetToken;
    if (key.isEmpty) {
      return;
    }
    _deviceCache[key] = raw;
  }

  void _startDeviceRefreshTimer() {
    _deviceRefreshTimer?.cancel();
    _deviceRefreshTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _refreshVisibleDevices();
    });
    _refreshVisibleDevices();
  }

  void _refreshVisibleDevices() {
    if (!mounted) return;
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    const visibleWindowMs = 2000;
    _deviceCache.removeWhere((_, entry) => nowMs - entry.timestampMs > visibleWindowMs);
    final next = _deviceCache.values.toList()
      ..sort((a, b) {
        final byRssi = b.rssi.compareTo(a.rssi);
        if (byRssi != 0) return byRssi;
        return b.timestampMs.compareTo(a.timestampMs);
      });
    setState(() => _visibleDevices = next);
  }

  Future<void> _discoverServices(RawScanResult entry) async {
    final deviceId = entry.deviceId;
    if (deviceId == null || deviceId.isEmpty) {
      _showError('No deviceId available for this device.');
      return;
    }
    if (_connectingDeviceIds.contains(deviceId)) {
      return;
    }
    setState(() => _connectingDeviceIds.add(deviceId));
    try {
      final dump = await _ble.debugDiscoverServices(deviceId: deviceId);
      if (!mounted) return;

      // ✅ Dedupe logging
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      final prevDump = _lastDiscoveryDumpByDeviceId[deviceId];
      final prevLoggedAt = _lastDiscoveryLoggedAtMsByDeviceId[deviceId] ?? 0;

      final shouldLog = prevDump != dump || (nowMs - prevLoggedAt) > _discoveryLogDedupeWindowMs;

      if (shouldLog) {
        log(dump);
        _lastDiscoveryDumpByDeviceId[deviceId] = dump;
        _lastDiscoveryLoggedAtMsByDeviceId[deviceId] = nowMs;
      }

      await showDialog<void>(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: const Text('Discover Services'),
            content: SingleChildScrollView(
              child: SelectableText(dump),
            ),
            backgroundColor: const Color(0xFF3C5E57),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Close'),
              ),
            ],
          );
        },
      );
    } on Object catch (error) {
      _showError('Discover services failed: $error');
    } finally {
      if (mounted) {
        setState(() => _connectingDeviceIds.remove(deviceId));
      }
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
          unawaited(SystemSound.play(SystemSoundType.tick));
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
                _DeviceListCard(
                  entries: _visibleDevices,
                  connectingDeviceIds: _connectingDeviceIds,
                  onTap: _discoverServices,
                ),
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
              _MetricChip(label: 'Smooth', value: smoothRssi?.toStringAsFixed(1) ?? '--'),
              _MetricChip(label: 'Device ID', value: deviceId ?? '--'),
              _MetricChip(label: 'Device Name', value: deviceName ?? '--'),
              _MetricChip(label: 'Local Name', value: localName ?? '--'),
              _MetricChip(label: 'MFG Len', value: manufacturerDataLen?.toString() ?? '--'),
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

class _DeviceListCard extends StatelessWidget {
  const _DeviceListCard({
    required this.entries,
    required this.connectingDeviceIds,
    required this.onTap,
  });

  final List<RawScanResult> entries;
  final Set<String> connectingDeviceIds;
  final ValueChanged<RawScanResult> onTap;

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
            'Visible Devices (refresh 1s)',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.9),
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 10),
          if (entries.isEmpty)
            Text(
              'No devices yet.',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.6)),
            )
          else
            for (var i = 0; i < entries.length; i++)
              _DeviceRow(
                index: i,
                data: entries[i],
                connectingDeviceIds: connectingDeviceIds,
                onTap: onTap,
              ),
        ],
      ),
    );
  }
}

class _DeviceRow extends StatelessWidget {
  const _DeviceRow({
    required this.index,
    required this.data,
    required this.connectingDeviceIds,
    required this.onTap,
  });

  final int index;
  final RawScanResult data;
  final Set<String> connectingDeviceIds;
  final ValueChanged<RawScanResult> onTap;

  @override
  Widget build(BuildContext context) {
    final canTap = index < 3 && (data.deviceId?.isNotEmpty ?? false);
    final isConnecting = data.deviceId != null && connectingDeviceIds.contains(data.deviceId);
    final othersConnecting = connectingDeviceIds.isNotEmpty && !connectingDeviceIds.contains(data.deviceId);
    final label = data.localName ?? data.deviceName ?? data.deviceId ?? data.targetToken;
    final ageMs = DateTime.now().millisecondsSinceEpoch - data.timestampMs;
    final ageLabel = '${(ageMs / 1000).toStringAsFixed(1)}s';
    final headerColor = index < 3 ? const Color(0xFFFFC857) : Colors.white;

    final localHexLine = data.localNameHex == null ? null : 'localHex: ${data.localNameHex}';
    final serviceDataHexLine = _formatServiceDataHex(data.serviceDataHex);
    final mfgHexLine = data.manufacturerDataHex == null ? null : 'mfgHex: ${data.manufacturerDataHex}';
    final serviceDataUuidLine = (data.serviceDataUuids == null || data.serviceDataUuids!.isEmpty)
        ? null
        : 'svcDataUuids: ${data.serviceDataUuids!.join(",")}';
    final serviceUuidLine = (data.serviceUuids == null || data.serviceUuids!.isEmpty)
        ? null
        : 'svcUuids: ${data.serviceUuids!.join(",")}';

    final lines = <String>[
      if (data.deviceId != null) 'deviceId: ${data.deviceId}',
      ?localHexLine,
      ?serviceDataHexLine,
      ?serviceDataUuidLine,
      ?serviceUuidLine,
      ?mfgHexLine,
    ];

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: canTap && !isConnecting && !othersConnecting ? () => onTap(data) : null,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: Colors.white.withValues(alpha: canTap ? 0.2 : 0.08),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '$label • ${data.rssi}dBm • $ageLabel',
                      style: TextStyle(
                        color: headerColor.withValues(alpha: 0.9),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (canTap && !isConnecting && !othersConnecting)
                    Text(
                      'Tap to probe',
                      style: TextStyle(
                        color: headerColor.withValues(alpha: 0.8),
                        fontSize: 12,
                      ),
                    )
                  else if (isConnecting)
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  else
                    const SizedBox.shrink(),
                ],
              ),
              const SizedBox(height: 6),
              for (final line in lines)
                Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Text(
                    line,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.75),
                      fontSize: 11,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  String? _formatServiceDataHex(Map<String, String>? data) {
    if (data == null || data.isEmpty) return null;
    final entries = data.entries.map((entry) => '${entry.key}:${entry.value}').join(', ');
    return 'svcDataHex: $entries';
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
