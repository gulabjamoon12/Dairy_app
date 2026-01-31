import 'dart:io';
import 'dart:ui';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:gg/services/backup_service.dart';
import 'package:gg/services/google_drive_service.dart';
import 'package:gg/theme/app_theme.dart';
import 'package:gg/services/test_data_generator.dart';
import 'package:gg/screens/permission_setup_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _isExporting = false;
  bool _isImporting = false;
  bool _isGeneratingTestData = false;
  bool _isCreatingBackup = false;
  String _dbSize = 'Calculating...';

  final GoogleDriveService _driveService = GoogleDriveService();
  GoogleSignInAccount? _googleUser;
  bool _isDriveBackingUp = false;
  bool _isDriveRestoring = false;

  @override
  void initState() {
    super.initState();
    _loadDatabaseSize();
    _driveService.signInSilently().then((account) {
      if (mounted && account != null) {
        setState(() => _googleUser = account);
      }
    });
  }

  Future<void> _loadDatabaseSize() async {
    final size = await BackupService.getDatabaseSize();
    if (mounted) {
      setState(() {
        _dbSize = BackupService.formatBytes(size);
      });
    }
  }

  Future<void> _backupToDrive() async {
    if (_isDriveBackingUp) return;

    // Warning dialog before backup (multi-device risk)
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Backup to Drive?'),
        content: Text(
          'This will replace whatever is currently in the "Milk Delivery Backups" '
          'folder on Google Drive with this device\'s data.\n\n'
          'If you use the app on more than one device, make sure you are on the '
          'device that has the data you want to keep. Backing up from a device '
          'with no or old data will overwrite a good backup on Drive.\n\n'
          'Back up only from the device that has the most up-to-date data.\n\n'
          'This device has data ($_dbSize).',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Backup'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    setState(() => _isDriveBackingUp = true);
    try {
      final ok = await _driveService.uploadLatestBackup();
      if (!mounted) return;
      if (ok) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Backup saved to Google Drive successfully!'),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Failed to backup to Drive. Please try again.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isDriveBackingUp = false);
    }
  }

  Future<void> _restoreFromDrive() async {
    if (_isDriveRestoring) return;

    // Step 1: Warning dialog (multi-device / old backup risk)
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Restore from Drive?'),
        content: const Text(
          'The backup on Drive may be from another device or an older date. '
          'Restoring will replace this device\'s data with that backup.\n\n'
          'Restore only if you want this device to match the data from Drive. '
          'For safety, a local copy of this device\'s current data will be saved first.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Restore'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final messenger = ScaffoldMessenger.of(context);

    // Step 2: Safety backup
    setState(() => _isDriveRestoring = true);
    final safetyPath = await BackupService.createLocalBackup();
    if (mounted) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            safetyPath != null
                ? 'Safety backup created.'
                : 'Safety backup skipped (no data to back up).',
          ),
          backgroundColor: Colors.blue,
          duration: const Duration(seconds: 2),
        ),
      );
    }

    // Step 3: Perform restore
    try {
      final ok = await _driveService.restoreFromDrive();
      if (!mounted) return;
      if (ok) {
        await _loadDatabaseSize();
        if (!mounted) return;
        messenger.showSnackBar(
          const SnackBar(
            content: Text(
              'Data restored from Google Drive successfully! Please restart the app.',
            ),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Failed to restore from Drive. Please try again.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isDriveRestoring = false);
    }
  }

  Future<void> _exportDatabase() async {
    if (_isExporting) return;
    
    // Show options dialog
    final choice = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Export Backup'),
        content: const Text('How would you like to save the backup?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, 'save'),
            child: const Text('Save to Device'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, 'share'),
            child: const Text('Share'),
          ),
        ],
      ),
    );
    
    if (choice == null) return;
    
    setState(() => _isExporting = true);
    
    try {
      if (choice == 'save') {
        // Let user choose save location
        final path = await BackupService.saveToLocation();
        if (!mounted) return;
        
        if (path != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Backup saved successfully!'),
              backgroundColor: Colors.green,
            ),
          );
        } else {
          // User cancelled or error occurred
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Backup cancelled or failed.'),
              backgroundColor: Colors.orange,
            ),
          );
        }
      } else {
        // Share the backup file
        final result = await BackupService.exportDatabase();
        if (!mounted) return;
        
        if (result == true) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Backup ready! Save the file to transfer to another device.'),
              backgroundColor: Colors.green,
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Failed to create backup. Please try again.'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isExporting = false);
      }
    }
  }

  Future<void> _generateTestData() async {
    if (_isGeneratingTestData) return;
    
    // Show confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Generate Test Data'),
        content: const Text(
          'This will add:\n'
          '• 70 test customers\n'
          '• 2 months of milk entries\n'
          '• Dahi/Ghee entries for a few days\n'
          '• Some holidays (Sundays + random days)\n\n'
          'This will add data to your existing database. Continue?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Generate'),
          ),
        ],
      ),
    );
    
    if (confirmed != true) return;
    
    setState(() => _isGeneratingTestData = true);
    
    try {
      // Show progress dialog
      if (!mounted) return;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(
          child: Card(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Generating test data...\nThis may take a moment.'),
                ],
              ),
            ),
          ),
        ),
      );
      
      // Generate test data
      await TestDataGenerator.generateAllTestData();
      
      // Close progress dialog
      if (mounted) {
        Navigator.pop(context);
      }
      
      // Reload database size
      await _loadDatabaseSize();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Test data generated successfully!'),
            backgroundColor: Colors.green,
            duration: Duration(milliseconds: 2000),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context); // Close progress dialog
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error generating test data: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isGeneratingTestData = false);
      }
    }
  }

  Future<void> _createBackupNow() async {
    if (_isCreatingBackup) return;
    
    setState(() => _isCreatingBackup = true);
    
    try {
      final backupPath = await BackupService.createDailyBackup();
      
      if (!mounted) return;
      
      if (!mounted) return;
      
      if (backupPath != null) {
        // Reload database size
        await _loadDatabaseSize();
        
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Backup created successfully!\n'
              'Location: ${Platform.isAndroid ? "Downloads/MilkDeliveryBackups" : "Files app/MilkDeliveryBackups"}',
            ),
            backgroundColor: Colors.green,
            duration: Duration(milliseconds: 2000),
          ),
        );
      } else {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to create backup. Please try again.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isCreatingBackup = false);
      }
    }
  }

  Future<void> _importDatabase() async {
    if (_isImporting) return;

    // Show confirmation dialog
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Restore from Backup'),
        content: const Text(
          'This will replace ALL your current data with the data from the backup file.\n\n'
          'Are you sure you want to continue?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
              foregroundColor: Colors.white,
            ),
            child: const Text('Restore'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isImporting = true);

    try {
      // Open file picker to select the backup file
      final result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        allowMultiple: false,
      );

      if (result == null || result.files.isEmpty) {
        if (mounted) {
          setState(() => _isImporting = false);
        }
        return;
      }

      final filePath = result.files.first.path;
      if (filePath == null) {
        if (mounted) {
          setState(() => _isImporting = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Could not access the selected file.'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      final success = await BackupService.importDatabase(filePath);
      if (!mounted) return;

      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Data restored successfully! Please restart the app.'),
            backgroundColor: Colors.green,
          ),
        );
        // Reload database size
        _loadDatabaseSize();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to restore data. Make sure you selected a valid backup file.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isImporting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Theme.of(context).colorScheme.primary.withValues(alpha: 0.12),
              Theme.of(context).colorScheme.secondary.withValues(alpha: 0.08),
              Theme.of(context).scaffoldBackgroundColor,
            ],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // Header
              Container(
                padding: const EdgeInsets.all(24),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Theme.of(context).colorScheme.primary,
                            Theme.of(context).colorScheme.secondary,
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: [
                          BoxShadow(
                            color: Theme.of(context)
                                .colorScheme
                                .primary
                                .withValues(alpha: 0.2),
                            blurRadius: 12,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.settings_rounded,
                        color: Colors.white,
                        size: 28,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Settings',
                            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                          ),
                          Text(
                            'Manage app preferences',
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurface
                                      .withValues(alpha: 0.7),
                                ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              // Settings List
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.symmetric(horizontal: AppTheme.spacingLg),
                  children: [
                    _SettingsSection(
                      title: 'Cloud Backup',
                      items: _googleUser == null
                          ? [
                              _SettingsItem(
                                title: 'Connect Google Drive',
                                subtitle: 'Back up and restore from Google Drive',
                                icon: Icons.cloud_rounded,
                                iconColor: const Color(0xFF4285F4),
                                onTap: _isDriveBackingUp || _isDriveRestoring
                                    ? () {}
                                    : () async {
                                        final messenger = ScaffoldMessenger.of(context);
                                        final account = await _driveService.signIn();
                                        if (!mounted) return;
                                        if (account != null) {
                                          setState(() => _googleUser = account);
                                        } else {
                                          messenger.showSnackBar(
                                            const SnackBar(
                                              content: Text('Could not connect to Google Drive.'),
                                              backgroundColor: Colors.orange,
                                            ),
                                          );
                                        }
                                      },
                              ),
                            ]
                          : [
                              _SettingsItem(
                                title: 'Backup to Drive',
                                subtitle: _isDriveBackingUp
                                    ? 'Uploading...'
                                    : "Save to 'Milk Delivery Backups' folder",
                                icon: Icons.cloud_upload_rounded,
                                iconColor: const Color(0xFF4285F4),
                                onTap: _isDriveBackingUp ? () {} : _backupToDrive,
                                trailing: _isDriveBackingUp
                                    ? const SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(strokeWidth: 2),
                                      )
                                    : null,
                              ),
                              _SettingsItem(
                                title: 'Restore from Drive',
                                subtitle: _isDriveRestoring
                                    ? 'Restoring...'
                                    : 'Restore from backup in Drive',
                                icon: Icons.cloud_download_rounded,
                                iconColor: const Color(0xFF4285F4),
                                onTap: _isDriveRestoring ? () {} : _restoreFromDrive,
                                trailing: _isDriveRestoring
                                    ? const SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(strokeWidth: 2),
                                      )
                                    : null,
                              ),
                              _SettingsItem(
                                title: 'Disconnect Account',
                                subtitle: 'Sign out from Google Drive',
                                icon: Icons.link_off_rounded,
                                iconColor: const Color(0xFF64748B),
                                onTap: () async {
                                  await _driveService.signOut();
                                  if (mounted) setState(() => _googleUser = null);
                                },
                              ),
                            ],
                    ),
                    const SizedBox(height: 24),
                    _SettingsSection(
                      title: 'Pricing',
                      items: [
                        _SettingsItem(
                          title: 'Set Milk Price',
                          subtitle: 'Manage the price of milk with an effective date',
                          icon: Icons.price_change_rounded,
                          iconColor: const Color(0xFF64748B),
                          onTap: () {
                            Navigator.pushNamed(context, '/milkPrice');
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    _SettingsSection(
                      title: 'Data Management',
                      items: [
                        _SettingsItem(
                          title: 'Edit Entries',
                          subtitle: 'View and edit past milk entries',
                          icon: Icons.history_rounded,
                          iconColor: const Color(0xFFF59E0B),
                          onTap: () {
                            Navigator.pushNamed(context, '/editEntries');
                          },
                        ),
                        _SettingsItem(
                          title: 'Manage Dahi/Ghee',
                          subtitle: 'View and edit dahi and ghee entries',
                          icon: Icons.inventory_2_rounded,
                          iconColor: const Color(0xFFEC4899),
                          onTap: () {
                            Navigator.pushNamed(context, '/manageDahiGhee');
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    _SettingsSection(
                      title: 'Customer Management',
                      items: [
                        _SettingsItem(
                          title: 'Manage Customers',
                          subtitle: 'View, edit, and manage customer details',
                          icon: Icons.people_rounded,
                          iconColor: const Color(0xFF3B82F6),
                          onTap: () {
                            Navigator.pushNamed(context, '/manageCustomers');
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    _SettingsSection(
                      title: 'Backup & Restore',
                      items: [
                        _SettingsItem(
                          title: 'Backup Now',
                          subtitle: _isCreatingBackup 
                              ? 'Creating backup...' 
                              : 'Create backup in user-accessible folder ($_dbSize)',
                          icon: Icons.backup_rounded,
                          iconColor: const Color(0xFF6366F1),
                          onTap: _isCreatingBackup ? () {} : _createBackupNow,
                          trailing: _isCreatingBackup 
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : null,
                        ),
                        _SettingsItem(
                          title: 'Export Backup',
                          subtitle: _isExporting 
                              ? 'Creating backup...' 
                              : 'Save your data to transfer to another device ($_dbSize)',
                          icon: Icons.upload_rounded,
                          iconColor: const Color(0xFF10B981),
                          onTap: _isExporting ? () {} : _exportDatabase,
                          trailing: _isExporting 
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : null,
                        ),
                        _SettingsItem(
                          title: 'Restore from Backup',
                          subtitle: _isImporting 
                              ? 'Restoring data...' 
                              : 'Import data from a backup file',
                          icon: Icons.download_rounded,
                          iconColor: const Color(0xFFF59E0B),
                          onTap: _isImporting ? () {} : _importDatabase,
                          trailing: _isImporting 
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : null,
                        ),
                        _SettingsItem(
                          title: 'Manage Permissions',
                          subtitle: 'Grant SMS and Storage permissions for full functionality',
                          icon: Icons.security_rounded,
                          iconColor: const Color(0xFF6366F1),
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => const PermissionSetupScreen(),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    _SettingsSection(
                      title: 'Test Data',
                      items: [
                        _SettingsItem(
                          title: 'Generate Test Data',
                          subtitle: _isGeneratingTestData
                              ? 'Generating...'
                              : 'Add 70 test customers with 2 months of entries',
                          icon: Icons.data_object_rounded,
                          iconColor: const Color(0xFF8B5CF6),
                          onTap: _isGeneratingTestData ? () {} : _generateTestData,
                          trailing: _isGeneratingTestData
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : null,
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    // Info card about backups
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.2),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.info_outline_rounded,
                            color: Theme.of(context).colorScheme.primary,
                            size: 24,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Backups are saved in:\n'
                              '${Platform.isAndroid ? "Downloads/MilkDeliveryBackups" : "Files app/MilkDeliveryBackups"} folder\n'
                              '(Accessible via file manager)\n\n'
                              'To transfer data to a new device:\n'
                              '1. Use "Backup Now" or "Export Backup"\n'
                              '2. Copy the file to your new device\n'
                              '3. Install the app and use "Restore from Backup"',
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
                                    height: 1.5,
                                  ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SettingsSection extends StatelessWidget {
  final String title;
  final List<_SettingsItem> items;

  const _SettingsSection({
    required this.title,
    required this.items,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(
            left: AppTheme.spacingXs,
            bottom: AppTheme.spacingSm,
          ),
          child: Text(
            title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.75),
                ),
          ),
        ),
        ...items,
      ],
    );
  }
}

class _SettingsItem extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color iconColor;
  final VoidCallback onTap;
  final Widget? trailing;

  const _SettingsItem({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.iconColor,
    required this.onTap,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      color: Colors.transparent,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: AppTheme.spacingLg,
              vertical: AppTheme.spacingXs,
            ),
            tileColor: Theme.of(context).colorScheme.surface.withValues(alpha: 0.75),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
              side: BorderSide(
                color: Colors.white.withValues(alpha: 0.35),
              ),
            ),
            leading: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                icon,
                color: iconColor,
                size: 24,
              ),
            ),
            title: Text(
              title,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
            subtitle: Text(
              subtitle,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.65),
                  ),
            ),
            trailing: trailing ?? Icon(
              Icons.chevron_right_rounded,
              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.4),
            ),
            onTap: onTap,
          ),
        ),
      ),
    );
  }
}
