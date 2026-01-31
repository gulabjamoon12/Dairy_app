import 'package:flutter/material.dart';
import 'package:gg/screens/add_customer_screen.dart';
import 'package:gg/screens/daily_milk_entry_screen.dart';
import 'package:gg/screens/dahi_ghee_screen.dart';
import 'package:gg/screens/manage_customers_screen.dart';
import 'package:gg/screens/edit_entries_screen.dart';
import 'package:gg/screens/manage_dahi_ghee_screen.dart';
import 'package:gg/screens/settings_screen.dart';
import 'package:gg/screens/milk_price_screen.dart';
import 'package:gg/screens/report/report_main_screen.dart';
import 'package:gg/screens/splash_screen.dart';
import 'package:gg/theme/app_theme.dart';
import 'package:gg/widgets/main_navigation.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Shyam',
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.system,
      routes: {
        '/': (context) => const SplashScreen(),
        '/home': (context) => const MainNavigation(initialIndex: 0),
        '/addCustomer': (context) => const AddCustomerScreen(),
        '/dailyEntry': (context) => const DailyMilkEntryScreen(),
        '/dahiGhee': (context) => const DahiGheeScreen(),
        '/manageCustomers': (context) => const ManageCustomersScreen(),
        '/editEntries': (context) => const EditEntriesScreen(),
        '/manageDahiGhee': (context) => const ManageDahiGheeScreen(),
        '/settings': (context) => const SettingsScreen(),
        '/milkPrice': (context) => const MilkPriceScreen(),
        '/report': (context) => const ReportMainScreen(),
      },
      initialRoute: '/',
    );
  }
}

