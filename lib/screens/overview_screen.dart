import 'package:flutter/material.dart';
import '../services/api_client.dart';
import '../services/storage_service.dart';
import '../services/ws_client.dart';
import '../models/device_with_shockers.dart';
import '../models/shared_user.dart';
import '../models/device_status.dart';
import '../utils/logger.dart';
import '../widgets/custom_snackbar.dart';
import '../widgets/loading_state.dart';
import '../widgets/overview/search_bar_widget.dart';
import '../widgets/overview/filter_bar_widget.dart';
import '../widgets/overview/shocker_card_widget.dart';
import '../widgets/overview/empty_state_widget.dart';
import '../widgets/overview/error_state_widget.dart';
import 'settings_screen.dart';
import 'hub_setup_screen.dart';

class OverviewScreen extends StatefulWidget {
  const OverviewScreen({super.key});

  @override
  State<OverviewScreen> createState() => _OverviewScreenState();
}

class _OverviewScreenState extends State<OverviewScreen> {
  final ApiClient _apiClient = ApiClient();
  OpenShockClient? _wsClient;
  List<DeviceWithShockers> _devices = [];
  List<SharedUser> _sharedUsers = [];
  bool _isLoading = true;
  String? _error;
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();
  Set<ShockerFilter> _activeFilters = {ShockerFilter.all};

  // Store device statuses that arrive before devices are loaded
  final Map<String, DeviceStatus> _pendingDeviceStatuses = {};

  @override
  void initState() {
    super.initState();
    _initializeAndLoadData();
  }

  Future<void> _initializeAndLoadData() async {
    Logger.log('Initializing overview screen', tag: 'OverviewScreen');
    // Configure API client with current host
    final customHost = await StorageService().getCustomHost();
    if (customHost != null && customHost.isNotEmpty) {
      Logger.log('Using custom host: $customHost', tag: 'OverviewScreen');
      await _apiClient.setBaseUrl(customHost);
    }

    _loadShockers();
    _connectWebSocket();
  }

  Future<void> _connectWebSocket() async {
    try {
      // The hub is authenticated with the session cookie set at login.
      final sessionKey = await _apiClient.getSessionKey();
      if (!mounted) return;
      if (sessionKey == null) {
        Logger.error(
          'No session key available for WebSocket',
          tag: 'OverviewScreen',
        );
        CustomSnackbar.error(
          context,
          title: 'WebSocket Connection Failed',
          description: 'No session key available.',
        );

        return;
      }

      final apiHost = _apiClient.baseUrl;

      // Initialize WebSocket client
      _wsClient = OpenShockClient(
        apiHost: apiHost,
        sessionKey: sessionKey,
        userAgent: ApiClient.userAgent,
      );

      // Register for DeviceStatus events
      await _wsClient!.start();
      _wsClient!.registerForwarder('DeviceStatus');

      // Listen for DeviceStatus events
      _wsClient!.onMethod('DeviceStatus').listen((event) {
        Logger.log(
          'DeviceStatus event received: ${event.args}',
          tag: 'OverviewScreen',
        );
        _handleDeviceStatusUpdate(event.args);
      });

      if (!mounted) return;
      CustomSnackbar.success(
        context,
        title: 'WebSocket Connected',
        description: 'Real-time updates are now enabled.',
      );
    } catch (e, stackTrace) {
      Logger.error(
        'Failed to connect WebSocket',
        tag: 'OverviewScreen',
        error: e,
        stackTrace: stackTrace,
      );

      if (!mounted) return;
      CustomSnackbar.error(
        context,
        title: 'WebSocket Connection Failed',
        description: e.toString(),
      );
    }
  }

  void _handleDeviceStatusUpdate(List<Object?>? args) {
    try {
      // Args is a list containing a single element which is the device status list
      if (args == null || args.isEmpty || args[0] is! List) {
        Logger.error(
          'Invalid DeviceStatus format: expected List<dynamic> with nested list',
          tag: 'OverviewScreen',
        );
        return;
      }

      final statusList = args[0] as List<dynamic>;
      final deviceStatuses = statusList
          .whereType<Map<String, dynamic>>()
          .map((json) => DeviceStatus.fromJson(json))
          .toList();

      Logger.log(
        'Processing ${deviceStatuses.length} device status updates',
        tag: 'OverviewScreen',
      );

      // Store statuses and update devices
      for (final status in deviceStatuses) {
        _pendingDeviceStatuses[status.deviceId] = status;
      }

      // Update device online status if devices are already loaded
      if (_devices.isNotEmpty) {
        setState(() {
          for (final status in deviceStatuses) {
            Logger.log(
              'Looking for device with ID: ${status.deviceId}',
              tag: 'OverviewScreen',
            );
            Logger.log(
              'Available device IDs: ${_devices.map((d) => d.id).join(", ")}',
              tag: 'OverviewScreen',
            );

            final deviceIndex =
                _devices.indexWhere((device) => device.id == status.deviceId);

            if (deviceIndex != -1) {
              _devices[deviceIndex] = _devices[deviceIndex].copyWith(
                isOnline: status.online,
                firmwareVersion: status.firmwareVersion,
              );
              Logger.log(
                'Updated device ${_devices[deviceIndex].name}: online=${status.online}, fw=${status.firmwareVersion}',
                tag: 'OverviewScreen',
              );
            } else {
              Logger.log(
                'Device not yet loaded, status stored for later: ${status.deviceId}',
                tag: 'OverviewScreen',
              );
            }
          }
        });
      } else {
        Logger.log(
          'Devices not loaded yet, storing ${deviceStatuses.length} status updates for later',
          tag: 'OverviewScreen',
        );
      }
    } catch (e, stackTrace) {
      Logger.error(
        'Failed to process DeviceStatus update',
        tag: 'OverviewScreen',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  Future<void> _loadShockers() async {
    Logger.log('Loading shockers', tag: 'OverviewScreen');
    setState(() {
      _isLoading = true;
      _error = null;
    });

    // Load both own and shared shockers in parallel
    final ownResponse = await _apiClient.getOwnShockers();
    final sharedResponse = await _apiClient.getSharedShockers();

    if (mounted) {
      setState(() {
        _isLoading = false;
        if (ownResponse.isSuccess && sharedResponse.isSuccess) {
          _devices = ownResponse.data ?? [];
          _sharedUsers = sharedResponse.data ?? [];

          // Apply any pending device statuses that arrived before devices were loaded
          if (_pendingDeviceStatuses.isNotEmpty) {
            Logger.log(
              'Applying ${_pendingDeviceStatuses.length} pending device status updates',
              tag: 'OverviewScreen',
            );

            for (var i = 0; i < _devices.length; i++) {
              final status = _pendingDeviceStatuses[_devices[i].id];
              if (status != null) {
                _devices[i] = _devices[i].copyWith(
                  isOnline: status.online,
                  firmwareVersion: status.firmwareVersion,
                );
                Logger.log(
                  'Applied pending status to device ${_devices[i].name}: online=${status.online}',
                  tag: 'OverviewScreen',
                );
              }
            }
          }

          Logger.log(
            'Loaded ${_devices.length} own devices and ${_sharedUsers.length} shared users',
            tag: 'OverviewScreen',
          );
        } else {
          _error = ownResponse.error ?? sharedResponse.error;
          Logger.error(
            'Failed to load shockers: $_error',
            tag: 'OverviewScreen',
          );
          CustomSnackbar.error(
            context,
            title: 'Failed to Load Shockers',
            description: _error ?? 'Unknown error occurred',
          );
        }
      });
    }
  }

  List<Map<String, dynamic>> _getFilteredShockers() {
    // Combine own and shared shockers with device info
    final ownShockers = _devices.expand((device) {
      return device.shockers.map((shocker) => {
            'shocker': shocker,
            'device': device,
            'isShared': false,
          });
    }).toList();

    final sharedShockers = _sharedUsers
        .expand((user) => user.devices)
        .expand((device) {
      return device.shockers.map((shocker) => {
            'shocker': shocker,
            'device': null, // Shared devices don't expose device info
            'isShared': true,
          });
    }).toList();

    List<Map<String, dynamic>> allShockers = [...ownShockers, ...sharedShockers];

    // Apply filters
    if (!_activeFilters.contains(ShockerFilter.all)) {
      allShockers = allShockers.where((item) {
        final shocker = item['shocker'];
        final isShared = item['isShared'] as bool;
        final isPaused = shocker.isPaused as bool;

        // Check ownership filter
        if (_activeFilters.contains(ShockerFilter.own) && isShared) {
          return false;
        }
        if (_activeFilters.contains(ShockerFilter.shared) && !isShared) {
          return false;
        }

        // Check status filter
        if (_activeFilters.contains(ShockerFilter.active) && isPaused) {
          return false;
        }
        if (_activeFilters.contains(ShockerFilter.paused) && !isPaused) {
          return false;
        }

        return true;
      }).toList();
    }

    // Apply search query
    if (_searchQuery.isNotEmpty) {
      allShockers = allShockers
          .where(
            (item) => item['shocker']
                .name
                .toLowerCase()
                .contains(_searchQuery.toLowerCase()),
          )
          .toList();
    }

    return allShockers;
  }

  @override
  void dispose() {
    _searchController.dispose();
    _wsClient?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => const HubSetupScreen(),
            ),
          );
        },
        backgroundColor: Colors.blue,
        tooltip: 'Add Hub',
        child: const Icon(Icons.add, color: Colors.white),
      ),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A1A1A),
        elevation: 0,
        title: Row(
          children: [
            Image.asset('assets/os/Icon64.png', width: 32, height: 32),
            const SizedBox(width: 12),
            const Text(
              'OpenShock',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings, color: Colors.white70),
            onPressed: () {
              Navigator.of(
                context,
              ).push(MaterialPageRoute(builder: (_) => const SettingsScreen()));
            },
            tooltip: 'Settings',
          ),
        ],
      ),
      body: Column(
        children: [
          if (_devices.isNotEmpty || _sharedUsers.isNotEmpty) ...[
            SearchBarWidget(
              controller: _searchController,
              searchQuery: _searchQuery,
              onChanged: (value) {
                setState(() {
                  _searchQuery = value;
                });
              },
              onClear: () {
                setState(() {
                  _searchQuery = '';
                  _searchController.clear();
                });
              },
            ),
            FilterBarWidget(
              activeFilters: _activeFilters,
              onToggleFilter: _toggleFilter,
            ),
          ],
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  void _toggleFilter(ShockerFilter filter) {
    setState(() {
      if (filter == ShockerFilter.all) {
        _activeFilters = {ShockerFilter.all};
      } else {
        _activeFilters.remove(ShockerFilter.all);
        if (_activeFilters.contains(filter)) {
          _activeFilters.remove(filter);
          if (_activeFilters.isEmpty) {
            _activeFilters = {ShockerFilter.all};
          }
        } else {
          _activeFilters.add(filter);
        }
      }
    });
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const LoadingState(message: 'Loading shockers...');
    }

    if (_error != null) {
      return ErrorStateWidget(error: _error!, onRetry: _loadShockers);
    }

    if (_devices.isEmpty && _sharedUsers.isEmpty) {
      return EmptyStateWidget(onRefresh: _loadShockers);
    }

    final filteredShockers = _getFilteredShockers();

    return RefreshIndicator(
      onRefresh: _loadShockers,
      color: Colors.white,
      backgroundColor: const Color(0xFF1A1A1A),
      child: filteredShockers.isEmpty
          ? ListView(
              children: const [
                SizedBox(height: 100),
                Center(
                  child: Column(
                    children: [
                      Icon(Icons.search_off, color: Colors.white30, size: 64),
                      SizedBox(height: 16),
                      Text(
                        'No shockers match your search',
                        style: TextStyle(color: Colors.white70),
                      ),
                    ],
                  ),
                ),
              ],
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: filteredShockers.length,
              itemBuilder: (context, index) {
                final item = filteredShockers[index];
                return ShockerCardWidget(
                  shocker: item['shocker'],
                  device: item['device'],
                  wsClient: _wsClient,
                );
              },
            ),
    );
  }
}
