class WeekUtils {
  /// Returns the ISO week number for a given date (ISO 8601).
  static int isoWeekNumber(DateTime date) {
    // ISO 8601: week 1 is the week containing the first Thursday of the year
    final thursday = date.add(Duration(days: 4 - date.weekday));
    final firstDayOfYear = DateTime(thursday.year, 1, 1);
    return ((thursday.difference(firstDayOfYear).inDays) / 7).floor() + 1;
  }

  /// Returns the current ISO week number.
  static int get currentWeek => isoWeekNumber(DateTime.now());

  /// Returns the current year, adjusted for ISO week boundary.
  static int get currentYear {
    final now = DateTime.now();
    final week = isoWeekNumber(now);
    // Late December days can belong to week 1 of the next year
    if (week == 1 && now.month == 12) return now.year + 1;
    // Early January days can belong to week 52/53 of the previous year
    if (week >= 52 && now.month == 1) return now.year - 1;
    return now.year;
  }
}
