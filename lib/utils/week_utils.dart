class WeekUtils {
  static int getCurrentWeekNumber() {
    final now = DateTime.now();
    final startOfYear = DateTime(now.year, 1, 1);
    final firstMonday = startOfYear.weekday <= 4
        ? startOfYear.subtract(Duration(days: startOfYear.weekday - 1))
        : startOfYear.add(Duration(days: 8 - startOfYear.weekday));
    if (now.isBefore(firstMonday)) {
      return getWeekNumber(DateTime(now.year - 1, 12, 31));
    }
    return ((now.difference(firstMonday).inDays) / 7).floor() + 1;
  }

  static int getCurrentYear() => DateTime.now().year;

  static int getWeekNumber(DateTime date) {
    final startOfYear = DateTime(date.year, 1, 1);
    final firstMonday = startOfYear.weekday <= 4
        ? startOfYear.subtract(Duration(days: startOfYear.weekday - 1))
        : startOfYear.add(Duration(days: 8 - startOfYear.weekday));
    if (date.isBefore(firstMonday)) {
      return getWeekNumber(DateTime(date.year - 1, 12, 31));
    }
    return ((date.difference(firstMonday).inDays) / 7).floor() + 1;
  }
}
