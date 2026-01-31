import 'dart:io';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:gg/services/backup_service.dart';

class PermissionSetupScreen extends StatefulWidget {
  const PermissionSetupScreen({super.key});

  @override
  State<PermissionSetupScreen> createState() => _PermissionSetupScreenState();
}

class _PermissionSetupScreenState extends State<PermissionSetupScreen> {
  bool _smsPermissionGranted = false;
  bool _storagePermissionGranted = false;
  bool _isChecking = true;

  @override
  void initState() {
    super.initState();
    _checkPermissions();
  }

  Future<void> _checkPermissions() async {
    if (Platform.isAndroid) {
      final smsStatus = await Permission.sms.status;
      final storageStatus = await Permission.storage.status;
      final manageStorageStatus = await Permission.manageExternalStorage.status;
      
      setState(() {
        _smsPermissionGranted = smsStatus.isGranted;
        _storagePermissionGranted = storageStatus.isGranted || manageStorageStatus.isGranted;
        _isChecking = false;
      });
    } else {
      setState(() {
        _smsPermissionGranted = true; // iOS handles SMS differently
        _storagePermissionGranted = true; // iOS has different storage model
        _isChecking = false;
      });
    }
  }

  Future<void> _requestSMSPermission() async {
    if (!Platform.isAndroid) return;
    
    final status = await Permission.sms.request();
    setState(() {
      _smsPermissionGranted = status.isGranted;
    });
  }

  Future<void> _requestStoragePermission() async {
    if (!Platform.isAndroid) return;
    
    // Try regular storage permission first
    var status = await Permission.storage.request();
    if (status.isGranted) {
      setState(() {
        _storagePermissionGranted = true;
      });
      return;
    }
    
    // Try manage external storage for Android 11+
    final manageStatus = await Permission.manageExternalStorage.request();
    setState(() {
      _storagePermissionGranted = manageStatus.isGranted;
    });
  }

  Future<void> _openSettings() async {
    await openAppSettings();
  }

  Future<void> _continue() async {
    // Mark that permissions have been set up
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('permissions_setup_complete', true);
    
    // Now that permissions are granted, try to restore from backup if no data exists
    if (_storagePermissionGranted) {
      final hasData = await BackupService.hasExistingData();
      if (!hasData) {
        // Show loading indicator while restoring
        if (mounted) {
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
                      Text('Checking for previous backup...'),
                    ],
                  ),
                ),
              ),
            ),
          );
        }
        
        // Try to restore from backup
        final restored = await BackupService.restoreFromLatestBackup();
        
        if (mounted) {
          Navigator.pop(context); // Close loading dialog
        }
        
        if (restored && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Data restored from backup successfully!'),
              backgroundColor: Colors.green,
              duration: Duration(milliseconds: 1500),
            ),
          );
        }
      }
    }
    
    if (!mounted) return;
    Navigator.of(context).pushReplacementNamed('/home');
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              colors.primary.withValues(alpha: 0.1),
              colors.secondary.withValues(alpha: 0.05),
              colors.surface,
            ],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                const SizedBox(height: 20),
                // App Logo/Icon
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: colors.primary.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.security,
                    size: 48,
                    color: colors.primary,
                  ),
                ),
                const SizedBox(height: 20),
                
                // Title
                Text(
                  'Permissions Required',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                
                // Description
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Text(
                    'To use all features of the app, please grant the following permissions:',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colors.onSurface.withValues(alpha: 0.7),
                        ),
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: 20),
                
                if (_isChecking)
                  const Expanded(
                    child: Center(child: CircularProgressIndicator()),
                  )
                else
                  Expanded(
                    child: SingleChildScrollView(
                      child: Column(
                        children: [
                          // SMS Permission Card
                          _PermissionCard(
                            icon: Icons.sms,
                            title: 'SMS Permission',
                            description: 'Required to send bill messages to customers',
                            isGranted: _smsPermissionGranted,
                            onRequest: _requestSMSPermission,
                            onOpenSettings: _openSettings,
                          ),
                          const SizedBox(height: 16),
                          
                          // Storage Permission Card
                          _PermissionCard(
                            icon: Icons.folder,
                            title: 'Storage Permission',
                            description: 'Required for daily automatic backups that survive app reinstall',
                            isGranted: _storagePermissionGranted,
                            onRequest: _requestStoragePermission,
                            onOpenSettings: _openSettings,
                          ),
                        ],
                      ),
                    ),
                  ),
                
                const SizedBox(height: 16),
                
                // Continue Button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _continue,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      backgroundColor: colors.primary,
                      foregroundColor: Colors.white,
                    ),
                    child: const Text(
                      'Continue',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                
                // Skip for now
                TextButton(
                  onPressed: _continue,
                  child: Text(
                    'Skip for now',
                    style: TextStyle(
                      color: colors.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PermissionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;
  final bool isGranted;
  final VoidCallback onRequest;
  final VoidCallback onOpenSettings;

  const _PermissionCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.isGranted,
    required this.onRequest,
    required this.onOpenSettings,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isGranted 
            ? colors.primary.withValues(alpha: 0.1)
            : colors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isGranted 
              ? colors.primary.withValues(alpha: 0.3)
              : colors.outline.withValues(alpha: 0.2),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: isGranted 
                  ? colors.primary.withValues(alpha: 0.2)
                  : colors.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              icon,
              color: isGranted ? colors.primary : colors.onSurface.withValues(alpha: 0.6),
              size: 24,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: isGranted ? colors.primary : null,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colors.onSurface.withValues(alpha: 0.7),
                      ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (isGranted)
            Icon(
              Icons.check_circle,
              color: Colors.green,
              size: 24,
            )
          else
            TextButton(
              onPressed: onRequest,
              child: const Text('Grant'),
            ),
        ],
      ),
    );
  }
}
