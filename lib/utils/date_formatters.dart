import 'package:intl/intl.dart';

/// Centralized date formatters to avoid creating new instances on every build.
/// These are expensive to create, so we cache them as static finals.
class DateFormatters {
  DateFormatters._();

  /// Format: "EEEE, dd MMM yyyy" (e.g., "Monday, 24 Jan 2026")
  static final DateFormat fullDate = DateFormat('EEEE, dd MMM yyyy');

  /// Format: "dd MMM, yyyy" (e.g., "24 Jan, 2026")
  static final DateFormat mediumDate = DateFormat('dd MMM, yyyy');

  /// Format: "dd MMM" (e.g., "24 Jan")
  static final DateFormat shortDate = DateFormat('dd MMM');

  /// Format: "MMM yyyy" (e.g., "Jan 2026")
  static final DateFormat monthYear = DateFormat('MMM yyyy');

  /// Format: "MMMM yyyy" (e.g., "January 2026")
  static final DateFormat fullMonthYear = DateFormat('MMMM yyyy');

  /// Format: "dd/MM/yyyy" (e.g., "24/01/2026")
  static final DateFormat slashDate = DateFormat('dd/MM/yyyy');

  /// Format: "yyyy-MM-dd" (e.g., "2026-01-24") - for database storage
  static final DateFormat isoDate = DateFormat('yyyy-MM-dd');

  /// Format: "dd MMM yyyy" (e.g., "24 Jan 2026")
  static final DateFormat dayMonthYear = DateFormat('dd MMM yyyy');
}
