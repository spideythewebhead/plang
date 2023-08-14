import 'dart:io';

import 'package:plang/src/ast.dart';

enum AnalysisErrorType {
  warning,
  error,
}

class AnalysisError {
  AnalysisError({
    required this.type,
    required this.message,
    required this.node,
    int? line,
    int? column,
  })  : line = line ?? node.token.line,
        column = column ?? node.token.column;

  final AnalysisErrorType type;
  final String message;
  final AstNode node;
  final int line;
  final int column;

  void print() {
    stderr.writeln(
        '$message ${node.compilationFile}:${1 + node.token.line}:${1 + node.token.column}');
  }
}
