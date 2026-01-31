import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gg/screens/daily_milk_entry_screen.dart';
import 'package:gg/screens/report/report_main_screen.dart';
import 'package:gg/screens/settings_screen.dart';
import 'package:gg/services/backup_service.dart';
import 'package:gg/services/database_helper.dart';
import 'package:gg/services/google_drive_service.dart';
import 'package:gg/theme/app_theme.dart';

class MainNavigation extends StatefulWidget {
  final int initialIndex;
  
  const MainNavigation({
    super.key,
    this.initialIndex = 0,
  });

  @override
  State<MainNavigation> createState() => _MainNavigationState();
}

class _MainNavigationState extends State<MainNavigation> with WidgetsBindingObserver {
  late int _currentIndex;
  late PageController _pageController;
  Timer? _backupCheckTimer;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
    
    // Add lifecycle observer to detect app state changes
    WidgetsBinding.instance.addObserver(this);
    
    // Defer backup check so HomeDashboard's initial DB access (addMissingEntries) completes first.
    // createDailyBackup() closes the DB; running it immediately races with HomeDashboard and can cause database_closed on iOS/Android.
    Future.delayed(const Duration(seconds: 3), () {
      if (!mounted) return;
      _checkAndCreateBackup();
    });
    
    // Set up periodic check (every hour) to catch day changes
    _backupCheckTimer = Timer.periodic(const Duration(hours: 1), (_) {
      _checkAndCreateBackup();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _backupCheckTimer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    // When app comes to foreground, check if backup is needed
    if (state == AppLifecycleState.resumed) {
      _checkAndCreateBackup();
    }
  }

  /// Check if backup is needed and create it automatically (local + Drive if signed in)
  Future<void> _checkAndCreateBackup() async {
    try {
      final isNeeded = await BackupService.isBackupNeeded();
      if (isNeeded) {
        // Create local backup in background (don't block UI)
        BackupService.createDailyBackup().then((backupPath) {
          if (backupPath != null) {
            debugPrint('Automatic daily backup created: $backupPath');
          }
        });
      }
      // Automatic daily Drive backup (unawaited, runs in background if user is signed in)
      GoogleDriveService().checkAndAutoBackup();
    } catch (e) {
      debugPrint('Error checking/creating automatic backup: $e');
    }
  }

  void navigateToTab(int index) {
    setState(() {
      _currentIndex = index;
    });
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeOutCubic,
    );
  }

  void _onItemTapped(int index) {
    HapticFeedback.lightImpact();
    navigateToTab(index);
  }

  static const double _kNavBarHeight = 64;
  static const double _kNavIconSize = 24;
  static const double _kNavLabelFontSize = 12;
  static const List<({IconData icon, String label})> _kNavItems = [
    (icon: Icons.home_rounded, label: 'Home'),
    (icon: Icons.add_chart_rounded, label: 'Daily Entry'),
    (icon: Icons.analytics_rounded, label: 'Reports'),
    (icon: Icons.settings_rounded, label: 'Settings'),
  ];

  @override
  Widget build(BuildContext context) {
    // OPTIMIZATION: Cache theme values at start of build
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    
    return Scaffold(
      extendBody: true,
      body: PageView(
        controller: _pageController,
        physics: const PageScrollPhysics(), // Enable swipe gestures
        onPageChanged: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
        children: const [
          HomeDashboard(),
          _DailyEntryWrapper(),
          _ReportsWrapper(),
          _SettingsWrapper(),
        ],
      ),
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
        child: SizedBox(
          height: _kNavBarHeight,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(22),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      colors.surface.withValues(alpha: 0.35),
                      colors.surface.withValues(alpha: 0.2),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.5)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.08),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: List.generate(_kNavItems.length, (index) {
                    final item = _kNavItems[index];
                    final selected = _currentIndex == index;
                    final color = selected
                        ? colors.primary
                        : colors.onSurface.withValues(alpha: 0.6);
                    return Expanded(
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: () => _onItemTapped(index),
                          borderRadius: BorderRadius.circular(22),
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(minHeight: 48),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const SizedBox(height: 6),
                                Icon(
                                  item.icon,
                                  size: _kNavIconSize,
                                  color: color,
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  item.label,
                                  style: TextStyle(
                                    fontSize: _kNavLabelFontSize,
                                    fontWeight:
                                        selected ? FontWeight.w600 : FontWeight.w500,
                                    color: color,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                SizedBox(
                                  height: 5,
                                  child: selected
                                      ? Center(
                                          child: Container(
                                            width: 4,
                                            height: 4,
                                            decoration: BoxDecoration(
                                              color: colors.primary,
                                              shape: BoxShape.circle,
                                            ),
                                          ),
                                        )
                                      : const SizedBox.shrink(),
                                ),
                                const SizedBox(height: 6),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  }),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// Wrapper widgets to remove Scaffold from embedded screens
class _DailyEntryWrapper extends StatelessWidget {
  const _DailyEntryWrapper();

  @override
  Widget build(BuildContext context) {
    return const DailyMilkEntryScreen();
  }
}

class _ReportsWrapper extends StatelessWidget {
  const _ReportsWrapper();

  @override
  Widget build(BuildContext context) {
    return const ReportMainScreen();
  }
}

class _SettingsWrapper extends StatelessWidget {
  const _SettingsWrapper();

  @override
  Widget build(BuildContext context) {
    return const SettingsScreen();
  }
}

class HomeDashboard extends StatefulWidget {
  const HomeDashboard({super.key});

  @override
  State<HomeDashboard> createState() => _HomeDashboardState();
}

class _HomeDashboardState extends State<HomeDashboard> {
  late Future<void> _initFuture;

  final List<Map<String, dynamic>> _quickActions = const [
    {
      'title': 'Add Customer',
      'icon': Icons.person_add_rounded,
      'route': '/addCustomer',
      'color': 0xFF22C55E,
    },
    {
      'title': 'Dahi/Ghee',
      'icon': Icons.opacity_rounded,
      'route': '/dahiGhee',
      'color': 0xFF10B981,
    },
    {
      'title': 'Manage Customers',
      'icon': Icons.people_rounded,
      'route': '/manageCustomers',
      'color': 0xFF0EA5E9,
    },
    {
      'title': 'Edit Entries',
      'icon': Icons.history_rounded,
      'route': '/editEntries',
      'color': 0xFFF59E0B,
    },
    {
      'title': 'Manage Dahi/Ghee',
      'icon': Icons.inventory_2_rounded,
      'route': '/manageDahiGhee',
      'color': 0xFF14B8A6,
    },
    {
      'title': 'Set Milk Price',
      'icon': Icons.price_change_rounded,
      'route': '/milkPrice',
      'color': 0xFF64748B,
    },
  ];

  @override
  void initState() {
    super.initState();
    _initFuture = _initializeDatabase();
  }

  Future<void> _initializeDatabase() async {
    try {
      await DatabaseHelper.instance.addMissingEntries();
    } catch (e, st) {
      debugPrint('HomeDashboard init: addMissingEntries failed: $e');
      debugPrint('$st');
    }
  }

  @override
  Widget build(BuildContext context) {
    // OPTIMIZATION: Cache theme values at start of build
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final textTheme = theme.textTheme;
    
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            colors.primary.withValues(alpha: 0.12),
            colors.secondary.withValues(alpha: 0.08),
            theme.scaffoldBackgroundColor,
          ],
        ),
      ),
      child: SafeArea(
        child: FutureBuilder<void>(
          future: _initFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(
                child: CircularProgressIndicator(),
              );
            }

            if (snapshot.hasError) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.error_outline, size: 48, color: Colors.red),
                    const SizedBox(height: 16),
                    Text('Error: ${snapshot.error}'),
                  ],
                ),
              );
            }

            return CustomScrollView(
              slivers: [
                // Header
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppTheme.spacingXl,
                      AppTheme.spacingLg,
                      AppTheme.spacingXl,
                      AppTheme.spacingSm,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    colors.primary,
                                    colors.secondary,
                                  ],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                                borderRadius: BorderRadius.circular(14),
                                boxShadow: [
                                  BoxShadow(
                                    color: colors.primary.withValues(alpha: 0.2),
                                    blurRadius: 12,
                                    offset: const Offset(0, 6),
                                  ),
                                ],
                              ),
                              child: const Icon(
                                Icons.local_drink_rounded,
                                color: Colors.white,
                                size: 26,
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Welcome back',
                                    style: textTheme.bodyMedium?.copyWith(
                                          color: colors.primary,
                                          fontWeight: FontWeight.w600,
                                        ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Milk Delivery Hub',
                                    style: textTheme.headlineSmall?.copyWith(
                                          fontWeight: FontWeight.bold,
                                        ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(20),
                          child: BackdropFilter(
                            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                            child: Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: colors.surface.withValues(alpha: 0.75),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.3),
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.05),
                                    blurRadius: 18,
                                    offset: const Offset(0, 10),
                                  ),
                                ],
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: colors.primary.withValues(alpha: 0.12),
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                    child: Icon(
                                      Icons.flash_on_rounded,
                                      color: colors.primary,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Fast daily operations',
                                          style: textTheme.titleMedium?.copyWith(
                                                fontWeight: FontWeight.w600,
                                              ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          'Add entries, manage customers, and track reports.',
                                          style: textTheme.bodyMedium,
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Quick Actions',
                              style: textTheme.titleLarge?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: colors.primary.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                'Today',
                                style: textTheme.labelMedium?.copyWith(
                                      color: colors.primary,
                                      fontWeight: FontWeight.w600,
                                    ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                // Quick Actions Grid
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(
                    AppTheme.spacingLg,
                    0,
                    AppTheme.spacingLg,
                    AppTheme.spacingLg,
                  ),
                  sliver: SliverGrid(
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      crossAxisSpacing: 14,
                      mainAxisSpacing: 14,
                      childAspectRatio: 1.05,
                    ),
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final item = _quickActions[index];
                        return _QuickActionCard(
                          title: item['title'] as String,
                          icon: item['icon'] as IconData,
                          route: item['route'] as String,
                          color: Color(item['color'] as int),
                          index: index,
                        );
                      },
                      childCount: _quickActions.length,
                    ),
                  ),
                ),
              ],
            );
            },
          ),
        ),
      );
  }
}

class _QuickActionCard extends StatefulWidget {
  final String title;
  final IconData icon;
  final String route;
  final Color color;
  final int index;

  const _QuickActionCard({
    required this.title,
    required this.icon,
    required this.route,
    required this.color,
    required this.index,
  });

  @override
  State<_QuickActionCard> createState() => _QuickActionCardState();
}

class _QuickActionCardState extends State<_QuickActionCard> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed == value) {
      return;
    }
    setState(() {
      _pressed = value;
    });
  }

  @override
  Widget build(BuildContext context) {
    // OPTIMIZATION: Cache theme values
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final start = (widget.index * 0.07).clamp(0.0, 0.6);
    final textColor = colors.onSurface;
    // OPTIMIZATION: Add key to prevent animation restart on parent rebuild
    return TweenAnimationBuilder<double>(
      key: ValueKey('quick_action_${widget.title}'),
      tween: Tween(begin: 0.0, end: 1.0),
      duration: const Duration(milliseconds: 500),
      curve: Interval(start, 1.0, curve: Curves.easeOut),
      builder: (context, value, child) {
        return Transform.translate(
          offset: Offset(0, 12 * (1 - value)),
          child: Opacity(opacity: value, child: child),
        );
      },
      child: GestureDetector(
        onTapDown: (_) => _setPressed(true),
        onTapUp: (_) => _setPressed(false),
        onTapCancel: () => _setPressed(false),
        child: AnimatedScale(
          scale: _pressed ? 0.98 : 1.0,
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
          child: InkWell(
            onTap: () => Navigator.pushNamed(context, widget.route),
            borderRadius: BorderRadius.circular(18),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        colors.surface.withValues(alpha: 0.85),
                        colors.surface.withValues(alpha: 0.6),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.35),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.06),
                        blurRadius: 18,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: widget.color.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: widget.color.withValues(alpha: 0.2),
                          ),
                        ),
                        child: Icon(
                          widget.icon,
                          size: 26,
                          color: widget.color,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Text(
                          widget.title,
                          textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: textColor,
                        ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
