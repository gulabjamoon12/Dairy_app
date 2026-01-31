import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:gg/services/backup_service.dart';
import 'package:gg/services/database_helper.dart';
import 'package:gg/screens/permission_setup_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    try {
      // Initialize database
      await DatabaseHelper.instance.database;
      
      // Check if permissions setup is complete
      final prefs = await SharedPreferences.getInstance();
      final permissionsSetupComplete = prefs.getBool('permissions_setup_complete') ?? false;
      
      // Only check for restore and create backup AFTER permissions are granted
      // This prevents trying to access storage before permission is given
      if (permissionsSetupComplete) {
        // Check if we have existing data
        final hasData = await BackupService.hasExistingData();
        
        if (!hasData) {
          // No data exists, try to restore from latest backup (now we have permission)
          debugPrint('No existing data found, attempting to restore from backup...');
          final restored = await BackupService.restoreFromLatestBackup();
          if (restored) {
            debugPrint('Successfully restored data from backup');
          } else {
            debugPrint('No backup found or restore failed');
          }
        }
        // Do not start createDailyBackup here: it closes the DB and races with MainNavigation/HomeDashboard.
        // MainNavigation runs the first backup check after a 3s delay so initial DB use completes first.
      }
      
      // Wait minimum 2 seconds for splash screen
      await Future.delayed(const Duration(seconds: 2));
      
      if (!mounted) return;
      
      // Navigate to permission setup if not completed, otherwise go to home
      if (!permissionsSetupComplete) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (context) => const PermissionSetupScreen()),
        );
      } else {
        Navigator.of(context).pushReplacementNamed('/home');
      }
    } catch (e) {
      debugPrint('Error initializing app: $e');
      // Still navigate to home even if there's an error
      await Future.delayed(const Duration(seconds: 2));
      if (!mounted) return;
      Navigator.of(context).pushReplacementNamed('/home');
    }
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
              colors.primary.withValues(alpha: 0.2),
              colors.secondary.withValues(alpha: 0.15),
              colors.surface,
            ],
          ),
        ),
        child: Stack(
          children: [
            Positioned(
              top: -120,
              right: -80,
              child: Container(
                height: 220,
                width: 220,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: colors.primary.withValues(alpha: 0.18),
                ),
              ),
            ),
            Positioned(
              bottom: -140,
              left: -80,
              child: Container(
                height: 260,
                width: 260,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: colors.secondary.withValues(alpha: 0.12),
                ),
              ),
            ),
            Center(
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0.9, end: 1.0),
                duration: const Duration(milliseconds: 600),
                curve: Curves.easeOut,
                builder: (context, value, child) {
                  return Transform.scale(
                    scale: value,
                    child: Opacity(
                      opacity: value,
                      child: child,
                    ),
                  );
                },
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(28),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                    child: Container(
                      padding: const EdgeInsets.all(28),
                      decoration: BoxDecoration(
                        color: colors.surface.withValues(alpha: 0.8),
                        borderRadius: BorderRadius.circular(28),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.35),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.08),
                            blurRadius: 20,
                            offset: const Offset(0, 12),
                          ),
                        ],
                      ),
                      child: Image.asset(
                        'assets/images/logo.png',
                        width: 160,
                        fit: BoxFit.contain,
                        errorBuilder: (context, error, stackTrace) {
                          debugPrint('Error loading logo: $error');
                          return const Icon(Icons.local_drink,
                              size: 100, color: Colors.deepPurple);
                        },
                      ),
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
