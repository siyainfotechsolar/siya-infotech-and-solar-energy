class PriorityCalculator {
  static String calculateAutomatic({
    required DateTime? createdAt,
    required DateTime? lastMeaningfulUpdate,
    required String? loanIssueStatus,
    required List<dynamic> tasks,
  }) {
    final now = DateTime.now();
    final lastUpdate = lastMeaningfulUpdate ?? createdAt ?? now;
    final daysSinceUpdate = now.difference(lastUpdate).inDays;

    // Check High Priority Rules
    final hasOpenLoanProblem = loanIssueStatus == 'OPEN PROBLEM';
    final hasIncompleteTask = tasks.any((t) {
      final status = (t['status'] as String? ?? '').toLowerCase();
      return status == 'not_completed' || status == 'incomplete';
    });

    if (daysSinceUpdate >= 15 || hasOpenLoanProblem || hasIncompleteTask) {
      return 'HIGH';
    }

    // Check Medium Priority Rules
    final hasPendingTask = tasks.any((t) {
      final status = (t['status'] as String? ?? '').toLowerCase();
      return status == 'pending' || status == 'in_progress';
    });

    if (daysSinceUpdate >= 7 || hasPendingTask) {
      return 'MEDIUM';
    }

    return 'NORMAL';
  }

  static String calculateFinal({
    required String automatic,
    required String? manual,
  }) {
    final m = manual ?? 'NORMAL';
    if (automatic == 'HIGH' || m == 'HIGH') {
      return 'HIGH';
    }
    if (automatic == 'MEDIUM' || m == 'MEDIUM') {
      return 'MEDIUM';
    }
    return 'NORMAL';
  }

  static int priorityValue(String priority) {
    switch (priority.toUpperCase()) {
      case 'HIGH':
        return 3;
      case 'MEDIUM':
        return 2;
      case 'NORMAL':
      default:
        return 1;
    }
  }

  static String getPriorityEmoji(String priority) {
    switch (priority.toUpperCase()) {
      case 'HIGH':
        return '🔴';
      case 'MEDIUM':
        return '🟠';
      case 'NORMAL':
      default:
        return '🟢';
    }
  }

  static int getDaysSinceUpdate(DateTime? lastMeaningfulUpdate, DateTime? createdAt) {
    final now = DateTime.now();
    final lastUpdate = lastMeaningfulUpdate ?? createdAt ?? now;
    return now.difference(lastUpdate).inDays;
  }

  static String getLastUpdateLabel(DateTime? lastMeaningfulUpdate, DateTime? createdAt) {
    final days = getDaysSinceUpdate(lastMeaningfulUpdate, createdAt);
    if (days == 0) return 'Today';
    return '$days Days Ago';
  }

  static int getCustomerAge(DateTime? createdAt) {
    if (createdAt == null) return 0;
    return DateTime.now().difference(createdAt).inDays;
  }
}
