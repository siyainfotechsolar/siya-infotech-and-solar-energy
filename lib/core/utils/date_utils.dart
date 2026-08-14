import 'package:flutter/material.dart';

class AppDateUtils {
  static int applicationAgeDays(String? applicationDate) {
    if (applicationDate == null) return 0;
    try {
      final date = DateTime.parse(applicationDate);
      return DateTime.now().difference(date).inDays;
    } catch (_) {
      return 0;
    }
  }

  static String applicationAgeLabel(String? applicationDate) {
    final days = applicationAgeDays(applicationDate);
    if (days == 0) return 'Today';
    if (days == 1) return '1 day';
    return '$days days';
  }

  static String ageCategory(String? applicationDate) {
    final days = applicationAgeDays(applicationDate);
    if (days <= 7) return '0–7';
    if (days <= 14) return '8–14';
    if (days <= 29) return '15–29';
    return '30+';
  }

  static String customerPriorityLabel(String? applicationDate) {
    final days = applicationAgeDays(applicationDate);
    if (days <= 7) return 'Normal';
    if (days <= 14) return 'Attention';
    if (days <= 29) return 'Priority';
    return 'Critical';
  }

  static Color customerPriorityColor(String? applicationDate) {
    final days = applicationAgeDays(applicationDate);
    if (days <= 7) return Colors.green;
    if (days <= 14) return Colors.orange;
    if (days <= 29) return Colors.deepOrange;
    return Colors.red;
  }

  static String formatDate(String? date) {
    if (date == null) return 'N/A';
    try {
      final d = DateTime.parse(date);
      return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
    } catch (_) {
      return date;
    }
  }

  static String formatDateTime(String? dateTime) {
    if (dateTime == null) return 'N/A';
    try {
      final d = DateTime.parse(dateTime).toLocal();
      return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year} '
          '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return dateTime;
    }
  }
}
