import 'package:flutter/material.dart';

// Stage definitions with colors
class StageConfig {
  static const List<String> stages = [
    'Lead',
    'PM Surya Ghar Application',
    'Loan Processing',
    'Installation',
    'RTS',
    'Subsidy',
    'Completed',
  ];

  static Color stageColor(String? stage) {
    switch (stage) {
      case 'Lead': return Colors.blue;
      case 'PM Surya Ghar Application': return Colors.indigo;
      case 'Loan Processing': return Colors.orange;
      case 'Installation': return Colors.green;
      case 'RTS': return Colors.teal;
      case 'Subsidy': return const Color(0xFFFBC02D);
      case 'Completed': return const Color(0xFF1B5E20); // Dark Green
      default: return Colors.grey;
    }
  }

  static String? nextStage(String? current, {bool loanRequired = false}) {
    if (current == null) return stages[0];
    if (current == 'PM Surya Ghar Application') {
      return loanRequired ? 'Loan Processing' : 'Installation';
    }
    if (current == 'Loan Processing') {
      return 'Installation';
    }
    if (current == 'Completed') return null;
    
    final idx = stages.indexOf(current);
    if (idx == -1 || idx >= stages.length - 1) return null;
    
    final next = stages[idx + 1];
    if (next == 'Loan Processing') {
      return loanRequired ? 'Loan Processing' : 'Installation';
    }
    return next;
  }

  static bool isCompleted(String? stage) => stage == 'Completed';
}
