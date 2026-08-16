import 'package:flutter/material.dart';

// Stage definitions with colors
class StageConfig {
  static const List<String> stages = [
    'Lead',
    'PM Surya Ghar Application',
    'Loan Processing',
    'Material Required',
    'Material Dispatched',
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
      case 'Material Required': return Colors.deepOrange;
      case 'Material Dispatched': return Colors.purple;
      case 'Installation': return Colors.green;
      case 'RTS': return Colors.teal;
      case 'Subsidy': return const Color(0xFFFBC02D);
      case 'Completed': return const Color(0xFF1B5E20);
      default: return Colors.grey;
    }
  }

  static String? nextStage(String? current, {bool loanRequired = false}) {
    if (current == null) return stages[0];
    if (current == 'Lead') return 'PM Surya Ghar Application';
    if (current == 'PM Surya Ghar Application') {
      return loanRequired ? 'Loan Processing' : 'Material Required';
    }
    if (current == 'Loan Processing') {
      return 'Material Required';
    }
    if (current == 'Material Required') {
      return 'Material Dispatched';
    }
    if (current == 'Material Dispatched') {
      return 'Installation';
    }
    if (current == 'Installation') {
      return 'RTS';
    }
    if (current == 'RTS') {
      return 'Subsidy';
    }
    if (current == 'Subsidy') {
      return 'Completed';
    }
    if (current == 'Completed') return null;
    
    final idx = stages.indexOf(current);
    if (idx == -1 || idx >= stages.length - 1) return null;
    return stages[idx + 1];
  }

  static bool isCompleted(String? stage) => stage == 'Completed';
}
