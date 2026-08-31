import 'dart:async';
import 'package:flutter/material.dart';

import '../services/hub_ws_client.dart';
import '../generated/flatbuffers/WifiNetwork_open_shock.serialization.types_generated.dart';
import '../utils/logger.dart';
import '../widgets/custom_snackbar.dart';

class HubSetupScreen extends StatefulWidget {
  const HubSetupScreen({super.key});

  @override
  State<HubSetupScreen> createState() => _HubSetupScreenState();
}

enum _SetupStep { connectHub, pickWifi, done }

class _HubSetupScreenState extends State<HubSetupScreen> {
  final HubWebSocketClient _hubClient = HubWebSocketClient();

  StreamSubscription? _connSub;
  StreamSubscription? _wifiSub;

  bool _isConnecting = false;
  bool _isScanning = false;

  String _connectionState = 'disconnected';

  List<WifiNetwork> _availableNetworks = [];
  String? _selectedSsid;

  // UI helpers
  final TextEditingController _searchController = TextEditingController();
  String _search = '';

  _SetupStep get _step {
    if (_connectionState != 'connected') return _SetupStep.connectHub;
    if (_selectedSsid == null) return _SetupStep.pickWifi;
    return _SetupStep.done;
  }

  @override
  void initState() {
    super.initState();
    _setupListeners();
    _searchController.addListener(() {
      setState(() => _search = _searchController.text.trim());
    });
  }

  void _setupListeners() {
    _connSub = _hubClient.connectionState.listen((state) {
      if (!mounted) return;
      setState(() => _connectionState = state);

      if (state == 'connected') {
        _startWifiScan();
      }
    });

    _wifiSub = _hubClient.wifiNetworks.listen((networks) {
      if (!mounted) return;

      // Filter out invalid SSIDs and keep strongest per SSID
      final Map<String, WifiNetwork> unique = {};
      for (final n in networks) {
        final ssid = n.ssid;
        if (ssid == null || ssid.isEmpty) continue;

        final current = unique[ssid];
        if (current == null || n.rssi > current.rssi) unique[ssid] = n;
      }

      final list = unique.values.toList()
        ..sort((a, b) => b.rssi.compareTo(a.rssi)); // strongest first

      setState(() {
        _availableNetworks = list;
        _isScanning = false;
      });

      Logger.log(
        'Received ${networks.length} networks, filtered to ${_availableNetworks.length} unique',
        tag: 'HubSetup',
      );
    });
  }

  @override
  void dispose() {
    _connSub?.cancel();
    _wifiSub?.cancel();
    _hubClient.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _connectToHub() async {
    setState(() => _isConnecting = true);
    try {
      final success = await _hubClient.connect();
      if (!success && mounted) {
        CustomSnackbar.error(
          context,
          title: 'Connection Failed',
          description:
              'Make sure you are connected to the OpenShock WiFi network.',
        );
      }
    } finally {
      if (mounted) setState(() => _isConnecting = false);
    }
  }

  Future<void> _startWifiScan() async {
    setState(() => _isScanning = true);

    final success = await _hubClient.startWifiScan();
    if (!success && mounted) {
      setState(() => _isScanning = false);
      CustomSnackbar.error(
        context,
        title: 'Scan Failed',
        description: 'Could not start WiFi scan.',
      );
    }
  }

  Future<void> _openPasswordSheet(WifiNetwork network) async {
    final ssid = network.ssid;
    if (ssid == null || ssid.isEmpty) return;

    setState(() => _selectedSsid = ssid);

    final passController = TextEditingController();
    bool obscure = true;

    final result = await showModalBottomSheet<String?>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF141414),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        final bottomInset = MediaQuery.of(ctx).viewInsets.bottom;
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            return Padding(
              padding: EdgeInsets.fromLTRB(20, 16, 20, bottomInset + 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 44,
                    height: 5,
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Icon(Icons.wifi, color: _signalColor(network.rssi)),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          ssid,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      _authChip(network),
                    ],
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: passController,
                    obscureText: obscure,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'WiFi password',
                      hintStyle: const TextStyle(color: Colors.white38),
                      filled: true,
                      fillColor: Colors.white.withValues(alpha: 0.06),
                      prefixIcon: const Icon(Icons.key, color: Colors.white54),
                      suffixIcon: IconButton(
                        onPressed: () => setLocal(() => obscure = !obscure),
                        icon: Icon(
                          obscure ? Icons.visibility : Icons.visibility_off,
                          color: Colors.white54,
                        ),
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () => Navigator.pop(ctx, passController.text),
                      icon: const Icon(Icons.link),
                      label: const Text('Connect hub'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );

    passController.dispose();

    // result is password (or null if cancelled)
    if (result == null) return;

    await _connectToNetwork(ssid, result);
  }

  Future<void> _connectToNetwork(String ssid, String password) async {
    // NOTE: Your HubWebSocketClient currently does NOT send password.
    // I'm keeping the UI ready for it, but this call still only sends ssid.
    // You should add password support in the flatbuffer command if required.
    final success = await _hubClient.connectToNetwork(ssid);

    if (!mounted) return;

    if (success) {
      CustomSnackbar.success(
        context,
        title: 'Connecting',
        description: 'Hub is connecting to $ssid',
      );

      await Future.delayed(const Duration(seconds: 2));
      if (mounted) Navigator.of(context).pop();
    } else {
      CustomSnackbar.error(
        context,
        title: 'Failed',
        description: 'Could not connect to network.',
      );
    }
  }

  List<WifiNetwork> get _filteredNetworks {
    if (_search.isEmpty) return _availableNetworks;
    final q = _search.toLowerCase();
    return _availableNetworks
        .where((n) => (n.ssid ?? '').toLowerCase().contains(q))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF101010),
        elevation: 0,
        title: const Text('Hub Setup', style: TextStyle(color: Colors.white)),
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            _header(),
            Expanded(child: _content()),
          ],
        ),
      ),
    );
  }

  Widget _header() {
    final stepIndex = switch (_step) {
      _SetupStep.connectHub => 0,
      _SetupStep.pickWifi => 1,
      _SetupStep.done => 2,
    };

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Progress
          Row(
            children: [
              _progressDot(active: stepIndex >= 0),
              _progressLine(active: stepIndex >= 1),
              _progressDot(active: stepIndex >= 1),
              _progressLine(active: stepIndex >= 2),
              _progressDot(active: stepIndex >= 2),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            switch (_step) {
              _SetupStep.connectHub => 'Step 1 • Connect to the hub',
              _SetupStep.pickWifi => 'Step 2 • Choose your WiFi',
              _SetupStep.done => 'Step 3 • Finish',
            },
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(switch (_step) {
            _SetupStep.connectHub =>
              'Connect to the temporary OpenShock WiFi, then tap continue.',
            _SetupStep.pickWifi =>
              'Pick your home WiFi and enter the password.',
            _SetupStep.done => 'All set — the hub will join your WiFi network.',
          }, style: const TextStyle(color: Colors.white54, height: 1.25)),
        ],
      ),
    );
  }

  Widget _content() {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      child: switch (_step) {
        _SetupStep.connectHub => _connectCard(key: const ValueKey('connect')),
        _SetupStep.pickWifi => _wifiPicker(key: const ValueKey('wifi')),
        _SetupStep.done => _doneCard(key: const ValueKey('done')),
      },
    );
  }

  Widget _connectCard({Key? key}) {
    return Padding(
      key: key,
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: _card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _pillRow(
              icon: Icons.wifi_tethering,
              title: 'Join the hub WiFi',
              subtitle: 'In your phone’s WiFi settings, connect to:',
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.white10),
              ),
              child: const Row(
                children: [
                  Icon(Icons.router, color: Colors.white70),
                  SizedBox(width: 10),
                  Text(
                    'OpenShock-XXXXXX',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isConnecting ? null : _connectToHub,
                icon: _isConnecting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            Colors.white,
                          ),
                        ),
                      )
                    : const Icon(Icons.arrow_forward),
                label: Text(
                  _isConnecting ? 'Connecting…' : 'I’m connected, continue',
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            _statusLine(),
          ],
        ),
      ),
    );
  }

  Widget _wifiPicker({Key? key}) {
    final networks = _filteredNetworks;

    return Padding(
      key: key,
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: _card(
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'Search networks',
                      hintStyle: const TextStyle(color: Colors.white38),
                      filled: true,
                      fillColor: Colors.white.withValues(alpha: 0.06),
                      prefixIcon: const Icon(
                        Icons.search,
                        color: Colors.white54,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                IconButton(
                  onPressed: _isScanning ? null : _startWifiScan,
                  icon: _isScanning
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              Colors.white,
                            ),
                          ),
                        )
                      : const Icon(Icons.refresh, color: Colors.white),
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.white.withValues(alpha: 0.06),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),

            if (networks.isEmpty && !_isScanning)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 28),
                child: Column(
                  children: const [
                    Icon(Icons.wifi_off, color: Colors.white24, size: 40),
                    SizedBox(height: 10),
                    Text(
                      'No networks found yet.\nTap refresh to scan again.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white38, height: 1.3),
                    ),
                  ],
                ),
              )
            else
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: networks.length,
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (_, i) => _networkTile(networks[i]),
              ),
          ],
        ),
      ),
    );
  }

  Widget _doneCard({Key? key}) {
    return Padding(
      key: key,
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: _card(
        child: Column(
          children: [
            const Icon(Icons.check_circle, color: Colors.green, size: 44),
            const SizedBox(height: 10),
            const Text(
              'Ready to connect',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Selected: ${_selectedSsid ?? ''}',
              style: const TextStyle(color: Colors.white54),
            ),
          ],
        ),
      ),
    );
  }

  Widget _networkTile(WifiNetwork network) {
    final ssid = network.ssid ?? 'Unknown';
    final secure = network.authMode.value > 0;
    final bars = _signalBars(network.rssi);

    return InkWell(
      onTap: () => _openPasswordSheet(network),
      borderRadius: BorderRadius.circular(16),
      child: Ink(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white10),
        ),
        child: Row(
          children: [
            Icon(Icons.wifi, color: _signalColor(network.rssi)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    ssid,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      _miniChip('$bars bars'),
                      const SizedBox(width: 8),
                      if (secure) _miniChip('Secure', icon: Icons.lock),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            const Icon(Icons.chevron_right, color: Colors.white38),
          ],
        ),
      ),
    );
  }

  // ---------- Small UI pieces ----------

  Widget _card({required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white10),
      ),
      child: child,
    );
  }

  Widget _statusLine() {
    final (icon, text, color) = switch (_connectionState) {
      'connecting' => (Icons.sync, 'Connecting…', Colors.white54),
      'connected' => (Icons.check_circle, 'Connected', Colors.green),
      'error' => (Icons.error, 'Connection error', Colors.redAccent),
      _ => (Icons.circle_outlined, 'Not connected', Colors.white38),
    };

    return Row(
      children: [
        Icon(icon, color: color, size: 16),
        const SizedBox(width: 8),
        Text(text, style: TextStyle(color: color)),
      ],
    );
  }

  Widget _pillRow({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white10),
          ),
          child: Icon(icon, color: Colors.white70),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 2),
              Text(subtitle, style: const TextStyle(color: Colors.white54)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _progressDot({required bool active}) {
    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(
        color: active ? Colors.blue : Colors.white24,
        shape: BoxShape.circle,
      ),
    );
  }

  Widget _progressLine({required bool active}) {
    return Expanded(
      child: Container(
        height: 2,
        margin: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: active ? Colors.blue : Colors.white24,
          borderRadius: BorderRadius.circular(99),
        ),
      ),
    );
  }

  Widget _miniChip(String text, {IconData? icon}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: Colors.white10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: Colors.white54),
            const SizedBox(width: 6),
          ],
          Text(
            text,
            style: const TextStyle(color: Colors.white54, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _authChip(WifiNetwork network) {
    final secure = network.authMode.value > 0;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: secure
            ? Colors.white.withValues(alpha: 0.06)
            : Colors.green.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: Colors.white10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            secure ? Icons.lock : Icons.lock_open,
            size: 14,
            color: secure ? Colors.white54 : Colors.green,
          ),
          const SizedBox(width: 6),
          Text(
            secure ? 'Secure' : 'Open',
            style: TextStyle(
              color: secure ? Colors.white54 : Colors.green,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  int _signalBars(int rssi) {
    if (rssi >= -50) return 4;
    if (rssi >= -60) return 3;
    if (rssi >= -70) return 2;
    if (rssi >= -80) return 1;
    return 0;
  }

  Color _signalColor(int rssi) {
    if (rssi >= -50) return Colors.green;
    if (rssi >= -60) return Colors.lightGreen;
    if (rssi >= -70) return Colors.orange;
    return Colors.redAccent;
  }
}
