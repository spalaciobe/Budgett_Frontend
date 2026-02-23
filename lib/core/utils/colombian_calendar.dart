
class ColombianCalendar {
  // Fixed holidays (Month, Day)
  static final List<DateTime> _fixedHolidays = [
    DateTime(0, 1, 1), // New Year
    DateTime(0, 5, 1), // Labor Day
    DateTime(0, 7, 20), // Independence Day
    DateTime(0, 8, 7), // Battle of Boyaca
    DateTime(0, 12, 8), // Immaculate Conception
    DateTime(0, 12, 25), // Christmas
  ];

  // Emiliani Law Holidays (Month, Day) - Move to next Monday
  static final List<DateTime> _emilianiHolidays = [
    DateTime(0, 1, 6), // Epiphany
    DateTime(0, 3, 19), // St. Joseph
    DateTime(0, 6, 29), // St. Peter and St. Paul
    DateTime(0, 8, 15), // Assumption
    DateTime(0, 10, 12), // Columbus Day
    DateTime(0, 11, 1), // All Saints
    DateTime(0, 11, 11), // Independence of Cartagena
  ];

  /// Calculates Easter Sunday for a given year using Meeus/Jones/Butcher's algorithm
  static DateTime calculateEasterSunday(int year) {
    int a = year % 19;
    int b = year ~/ 100;
    int c = year % 100;
    int d = b ~/ 4;
    int e = b % 4;
    int f = (b + 8) ~/ 25;
    int g = (b - f + 1) ~/ 3;
    int h = (19 * a + b - d - g + 15) % 30;
    int i = c ~/ 4;
    int k = c % 4;
    int l = (32 + 2 * e + 2 * i - h - k) % 7;
    int m = (a + 11 * h + 22 * l) ~/ 451;
    int month = (h + l - 7 * m + 114) ~/ 31;
    int day = ((h + l - 7 * m + 114) % 31) + 1;

    return DateTime(year, month, day);
  }

  /// Calculates related holidays based on Easter (Variable holidays)
  static Map<String, DateTime> calculateEasterHolidays(int year) {
    DateTime easter = calculateEasterSunday(year);
    return {
      'Jueves Santo': easter.subtract(const Duration(days: 3)),
      'Viernes Santo': easter.subtract(const Duration(days: 2)),
      'Ascensión del Señor': _moveToMonday(easter.add(const Duration(days: 39))),
      'Corpus Christi': _moveToMonday(easter.add(const Duration(days: 60))),
      'Sagrado Corazón': _moveToMonday(easter.add(const Duration(days: 68))),
    };
  }

  /// Moves a date to the next Monday if it's not already on a Monday
  /// Used for Emiliani Law holidays and some Easter holidays
  static DateTime _moveToMonday(DateTime date) {
    if (date.weekday == DateTime.monday) return date;
    int daysUntilMonday = (8 - date.weekday) % 7;
    if (daysUntilMonday == 0) daysUntilMonday = 7; // Should be handled by first check, but safe guard
    return date.add(Duration(days: daysUntilMonday));
  }
  
  /// Handles Emiliani Law specifically:
  /// "If the holiday falls on a Monday, it stays. Otherwise, it moves to the next Monday."
  static DateTime _applyEmiliani(DateTime date) {
     if (date.weekday == DateTime.monday) return date;
     return _moveToMonday(date);
  }

  /// Returns true if the given date is a holiday in Colombia
  static bool isHoliday(DateTime date) {
    // 1. Check fixed holidays
    for (var holiday in _fixedHolidays) {
      if (holiday.month == date.month && holiday.day == date.day) {
        return true;
      }
    }

    // 2. Check Emiliani holidays
    for (var holiday in _emilianiHolidays) {
      DateTime originalDate = DateTime(date.year, holiday.month, holiday.day);
      DateTime movedDate = _applyEmiliani(originalDate);
      if (movedDate.month == date.month && movedDate.day == date.day) {
        return true;
      }
    }

    // 3. Check Easter-based holidays
    Map<String, DateTime> easterHolidays = calculateEasterHolidays(date.year);
    for (var holidayDate in easterHolidays.values) {
      if (holidayDate.month == date.month && holidayDate.day == date.day) {
        return true;
      }
    }

    return false;
  }

  static bool isWeekend(DateTime date) {
    return date.weekday == DateTime.saturday || date.weekday == DateTime.sunday;
  }

  static bool isBusinessDay(DateTime date) {
    return !isWeekend(date) && !isHoliday(date);
  }

  static DateTime getNextBusinessDay(DateTime date) {
    DateTime current = date.add(const Duration(days: 1));
    while (!isBusinessDay(current)) {
      current = current.add(const Duration(days: 1));
    }
    return current;
  }

  static DateTime getPreviousBusinessDay(DateTime date) {
    DateTime current = date.subtract(const Duration(days: 1));
    while (!isBusinessDay(current)) {
      current = current.subtract(const Duration(days: 1));
    }
    return current;
  }

  /// Returns a list of business days for a specific month
  static List<DateTime> getBusinessDaysInMonth(int year, int month) {
    List<DateTime> businessDays = [];
    DateTime date = DateTime(year, month, 1);
    while (date.month == month) {
      if (isBusinessDay(date)) {
        businessDays.add(date);
      }
      date = date.add(const Duration(days: 1));
    }
    return businessDays;
  }
}
