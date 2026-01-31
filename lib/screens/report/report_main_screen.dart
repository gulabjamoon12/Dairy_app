import 'package:flutter/material.dart';
import 'package:gg/screens/report/payment_tracking_tab.dart';
import 'package:gg/screens/report/billing_tab.dart';
import 'package:gg/screens/report/customer_stats_tab.dart';
import 'package:gg/screens/report/export_tab.dart';

class ReportMainScreen extends StatefulWidget {
  const ReportMainScreen({super.key});

  @override
  State<ReportMainScreen> createState() => _ReportMainScreenState();
}

class _ReportMainScreenState extends State<ReportMainScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late PageController _pageController;
  int _currentPage = 0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _pageController = PageController();
    
    // Sync TabController with PageController
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        _pageController.jumpToPage(_tabController.index);
        setState(() {
          _currentPage = _tabController.index;
        });
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
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
              // Header with Back Button
              Container(
                padding: const EdgeInsets.all(20),
                child: Row(
                  children: [
                    if (Navigator.canPop(context))
                      IconButton(
                        icon: const Icon(Icons.arrow_back),
                        onPressed: () => Navigator.pop(context),
                      ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Reports & Finance',
                        style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 4),
              // TabBar with pill-style container to align with main nav
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Container(
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.08),
                    ),
                  ),
                  child: TabBar(
                    controller: _tabController,
                    labelColor: Theme.of(context).colorScheme.primary,
                    unselectedLabelColor: Colors.grey[600],
                    indicator: BoxDecoration(
                      color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    indicatorSize: TabBarIndicatorSize.tab,
                    splashBorderRadius: BorderRadius.circular(16),
                    dividerColor: Colors.transparent,
                    padding: const EdgeInsets.all(4),
                    tabs: const [
                      Tab(
                        icon: Icon(Icons.account_balance_wallet),
                        text: 'Payments',
                      ),
                      Tab(
                        icon: Icon(Icons.receipt_long),
                        text: 'Billing',
                      ),
                      Tab(
                        icon: Icon(Icons.analytics),
                        text: 'Customer Data',
                      ),
                      Tab(
                        icon: Icon(Icons.file_download),
                        text: 'Export',
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              // PageView instead of TabBarView to allow edge swipes to pass through
              Expanded(
                child: _EdgeSwipePageView(
                  pageController: _pageController,
                  tabController: _tabController,
                  currentPage: _currentPage,
                  onPageChanged: (index) {
                    setState(() {
                      _currentPage = index;
                    });
                    _tabController.animateTo(index);
                  },
                  children: const [
                    // Tab 1: Payments
                    PaymentTrackingTab(),
                    // Tab 2: Billing
                    BillingTab(),
                    // Tab 3: Customer Data
                    CustomerStatsTab(),
                    // Tab 4: Export
                    ExportTab(),
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

/// Custom PageView that allows edge swipes to pass through to parent PageView
class _EdgeSwipePageView extends StatelessWidget {
  final PageController pageController;
  final TabController tabController;
  final int currentPage;
  final ValueChanged<int> onPageChanged;
  final List<Widget> children;

  const _EdgeSwipePageView({
    required this.pageController,
    required this.tabController,
    required this.currentPage,
    required this.onPageChanged,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    final isAtFirstPage = currentPage == 0;
    final isAtLastPage = currentPage == 3;

    return PageView(
      controller: pageController,
      physics: _EdgeAwarePageScrollPhysics(
        currentPage,
        isAtFirstPage,
        isAtLastPage,
        const ScrollPhysics(),
      ),
      onPageChanged: onPageChanged,
      children: children,
    );
  }
}

/// Custom ScrollPhysics that prevents scrolling at edges in specific directions
class _EdgeAwarePageScrollPhysics extends PageScrollPhysics {
  final int currentPage;
  final bool isAtFirstPage;
  final bool isAtLastPage;

  // ignore: prefer_const_constructors_in_immutables - parent is not always const (e.g. from buildParent)
  _EdgeAwarePageScrollPhysics(
    this.currentPage,
    this.isAtFirstPage,
    this.isAtLastPage,
    ScrollPhysics? parent,
  ) : super(parent: parent);

  @override
  _EdgeAwarePageScrollPhysics applyTo(ScrollPhysics? ancestor) {
    return _EdgeAwarePageScrollPhysics(
      currentPage,
      isAtFirstPage,
      isAtLastPage,
      buildParent(ancestor),
    );
  }

  @override
  bool shouldAcceptUserOffset(ScrollMetrics position) {
    // Check if we're at boundaries
    final tolerance = 0.5;
    final isAtStart = position.pixels <= position.minScrollExtent + tolerance;
    final isAtEnd = position.pixels >= position.maxScrollExtent - tolerance;
    
    // If at first page and at start, or at last page and at end
    // Don't accept offset to allow parent PageView to handle edge swipes
    if ((isAtFirstPage && isAtStart) || (isAtLastPage && isAtEnd)) {
      return false; // Let parent handle it
    }
    
    return super.shouldAcceptUserOffset(position);
  }
}


