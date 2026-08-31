import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../utils/logger.dart';
import '../widgets/custom_snackbar.dart';
import 'login_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _isLoggingOut = false;

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);
    final selfUser = authProvider.selfUser;

    return Stack(
      children: [
        Scaffold(
          backgroundColor: const Color(0xFF0A0A0A),
          appBar: AppBar(
            backgroundColor: const Color(0xFF1A1A1A),
            elevation: 0,
            title: const Text(
              'Settings',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
            leading: IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              onPressed: _isLoggingOut
                  ? null
                  : () => Navigator.of(context).pop(),
            ),
          ),
          body: AbsorbPointer(
            absorbing: _isLoggingOut,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // User Info Section
                _buildUserInfoSection(context, selfUser),
                const SizedBox(height: 24),

                // Server Section
                _buildServerSection(context, authProvider),
                const SizedBox(height: 24),

                // Account Actions Section
                _buildAccountActionsSection(context),
              ],
            ),
          ),
        ),
        if (_isLoggingOut)
          Container(
            color: Colors.black.withValues(alpha: 0.7),
            child: const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 3,
                  ),
                  SizedBox(height: 16),
                  Text(
                    'Logging out...',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 16,
                      decoration: TextDecoration.none,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildUserInfoSection(BuildContext context, selfUser) {
    if (selfUser == null) {
      return Card(
        color: const Color(0xFF1A1A1A),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'User Information',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              const Center(
                child: Text(
                  'Loading user information...',
                  style: TextStyle(color: Colors.white70),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Card(
      color: const Color(0xFF1A1A1A),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'User Information',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),

            // Profile Image
            Center(
              child: CircleAvatar(
                radius: 50,
                backgroundColor: Colors.white.withValues(alpha: 0.1),
                backgroundImage: selfUser.image.isNotEmpty
                    ? NetworkImage(selfUser.image)
                    : null,
                child: selfUser.image.isEmpty
                    ? const Icon(Icons.person, size: 50, color: Colors.white70)
                    : null,
              ),
            ),
            const SizedBox(height: 24),

            // Name
            _buildInfoRow(
              icon: Icons.person_outline,
              label: 'Name',
              value: selfUser.name,
            ),
            const SizedBox(height: 12),

            // Email
            _buildInfoRow(
              icon: Icons.email_outlined,
              label: 'Email',
              value: selfUser.email,
            ),
            const SizedBox(height: 12),

            // User ID
            _buildInfoRow(
              icon: Icons.fingerprint,
              label: 'User ID',
              value: selfUser.id,
              isMonospace: true,
            ),
            const SizedBox(height: 12),

            // Rank
            _buildInfoRow(
              icon: Icons.military_tech_outlined,
              label: 'Rank',
              value: selfUser.rank,
            ),

            // Roles (if any)
            if (selfUser.roles.isNotEmpty) ...[
              const SizedBox(height: 12),
              _buildRolesRow(selfUser.roles),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow({
    required IconData icon,
    required String label,
    required String value,
    bool isMonospace = false,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: Colors.white70, size: 20),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(color: Colors.white54, fontSize: 12),
              ),
              const SizedBox(height: 4),
              Text(
                value,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontFamily: isMonospace ? 'monospace' : null,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildRolesRow(List roles) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(
          Icons.admin_panel_settings_outlined,
          color: Colors.white70,
          size: 20,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Roles',
                style: TextStyle(color: Colors.white54, fontSize: 12),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: roles.map((role) {
                  return Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: _getRoleColor(role.toString()),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(
                      role.toString(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Color _getRoleColor(String role) {
    switch (role.toLowerCase()) {
      case 'admin':
        return Colors.red.withValues(alpha: 0.3);
      case 'system':
        return Colors.purple.withValues(alpha: 0.3);
      case 'staff':
        return Colors.blue.withValues(alpha: 0.3);
      case 'support':
        return Colors.green.withValues(alpha: 0.3);
      default:
        return Colors.grey.withValues(alpha: 0.3);
    }
  }

  Widget _buildServerSection(BuildContext context, AuthProvider authProvider) {
    return Card(
      color: const Color(0xFF1A1A1A),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Server',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),
                _buildInfoRow(
                  icon: Icons.cloud_outlined,
                  label: 'Server URL',
                  value: authProvider.currentHost,
                ),
              ],
            ),
          ),
          const Divider(color: Colors.white12, height: 1),
          ListTile(
            leading: const Icon(Icons.edit, color: Colors.white70),
            title: const Text(
              'Change Server URL',
              style: TextStyle(color: Colors.white),
            ),
            trailing: const Icon(
              Icons.arrow_forward_ios,
              color: Colors.white30,
              size: 16,
            ),
            onTap: () => _showChangeServerDialog(context, authProvider),
          ),
        ],
      ),
    );
  }

  Widget _buildAccountActionsSection(BuildContext context) {
    return Card(
      color: const Color(0xFF1A1A1A),
      child: Column(
        children: [
          ListTile(
            leading: const Icon(Icons.logout, color: Colors.red),
            title: const Text('Logout', style: TextStyle(color: Colors.red)),
            onTap: () => _showLogoutDialog(context),
          ),
        ],
      ),
    );
  }

  void _showChangeServerDialog(
    BuildContext context,
    AuthProvider authProvider,
  ) {
    final TextEditingController urlController = TextEditingController(
      text: authProvider.currentHost,
    );
    bool isLoading = false;
    String? error;

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          backgroundColor: const Color(0xFF1A1A1A),
          title: const Text(
            'Change Server URL',
            style: TextStyle(color: Colors.white),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Enter the new server URL:',
                style: TextStyle(color: Colors.white70),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: urlController,
                enabled: !isLoading,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'https://api.openshock.app',
                  hintStyle: const TextStyle(color: Colors.white30),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: Colors.white30),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: Colors.white30),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: Colors.blue),
                  ),
                  errorBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: Colors.red),
                  ),
                  errorText: error,
                ),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: Colors.orange.withValues(alpha: 0.3),
                  ),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.warning_amber, color: Colors.orange, size: 20),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Changing the server will log you out.',
                        style: TextStyle(color: Colors.orange, fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
              if (isLoading) ...[
                const SizedBox(height: 16),
                const Center(
                  child: CircularProgressIndicator(color: Colors.blue),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: isLoading
                  ? null
                  : () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: isLoading
                  ? null
                  : () async {
                      final newUrl = urlController.text.trim();

                      if (newUrl.isEmpty) {
                        setState(() {
                          error = 'URL cannot be empty';
                        });
                        return;
                      }

                      if (!newUrl.startsWith('http://') &&
                          !newUrl.startsWith('https://')) {
                        setState(() {
                          error = 'URL must start with http:// or https://';
                        });
                        return;
                      }

                      setState(() {
                        isLoading = true;
                        error = null;
                      });

                      // Show loading snackbar
                      if (context.mounted) {
                        CustomSnackbar.loading(
                          context,
                          title: 'Changing Server',
                          description: 'Please wait...',
                          key: 'server_change',
                        );
                      }

                      try {
                        await authProvider.setCustomHost(newUrl);
                        await authProvider.logout();

                        if (!context.mounted) return;

                        Navigator.of(dialogContext).pop();
                        Logger.log(
                          'Server URL changed, navigating to login',
                          tag: 'SettingsScreen',
                        );

                        // Dismiss loading, show success
                        CustomSnackbar.dismiss('server_change');
                        CustomSnackbar.success(
                          context,
                          title: 'Server Changed',
                          description: 'Successfully changed to $newUrl',
                        );

                        Navigator.of(context).pushAndRemoveUntil(
                          MaterialPageRoute(
                            builder: (_) => const LoginScreen(),
                          ),
                          (route) => false,
                        );
                      } catch (e) {
                        setState(() {
                          isLoading = false;
                          error = 'Failed to change server: $e';
                        });
                        if (context.mounted) {
                          // Dismiss loading, show error
                          CustomSnackbar.dismiss('server_change');
                          CustomSnackbar.error(
                            context,
                            title: 'Failed to Change Server',
                            description: e.toString(),
                          );
                        }
                      }
                    },
              child: const Text('Change & Logout'),
            ),
          ],
        ),
      ),
    );
  }

  void _showLogoutDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: const Text('Logout', style: TextStyle(color: Colors.white)),
        content: const Text(
          'Are you sure you want to logout?',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.of(dialogContext).pop();
              await _handleLogout(context);
            },
            child: const Text('Logout', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  Future<void> _handleLogout(BuildContext context) async {
    setState(() {
      _isLoggingOut = true;
    });

    // Show loading snackbar
    CustomSnackbar.loading(
      context,
      title: 'Logging Out',
      description: 'Please wait...',
      key: 'logout',
    );

    Logger.log('User initiated logout from settings', tag: 'SettingsScreen');
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    await authProvider.logout();

    if (!context.mounted) return;

    // Dismiss loading snackbar
    CustomSnackbar.dismiss('logout');

    Logger.log('Navigating to login screen', tag: 'SettingsScreen');
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }
}
