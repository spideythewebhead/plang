import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:plang/plang.dart';
import 'package:plang/src/extensions.dart';
import 'package:plang/src/interpreter/interpreter.dart';
import 'package:plang/src/models/analysis_error.dart';
import 'package:plang/src/visitors/basic_syntax_analysis.dart';
import 'package:plang/src/visitors/semantic_tokens_from_unit.dart';
import 'package:plang/src/visitors/type_checking/basic_type_checking_analysis.dart';

void main(List<String> arguments) async {
  try {
    if (arguments.elementAtOrNull(0) == 'json_tokens') {
      StringBuffer buffer = StringBuffer();
      stdin.transform(utf8.decoder).listen(
        buffer.write,
        onDone: () {
          final PlangScanner scanner = PlangScanner(buffer.toString());
          final List<Token> tokens = scanner.scan();
          try {
            final ParseResult parseResult =
                PlangParser(tokens, filePath: '').parse();
            stdout.writeln(jsonEncode(
                SemanticTokensFromUnit(parseResult.compilationUnit).execute()));
          } on ParserException catch (_) {
            stdout.writeln('$_');
            // stdout.writeln();
          }
        },
      );
      return;
    } else {
      String executableFile = path.basename(arguments[0]);
      Directory.current = path.dirname(path.absolute(arguments[0]));

      final Set<String> visited = <String>{};
      final Map<String, CompilationUnit> compilationUnits =
          <String, CompilationUnit>{};

      final List<ParserError> parsingErrors = <ParserError>[];

      void parseFile(String filePath) {
        if (visited.contains(filePath)) {
          return;
        }
        visited.add(filePath);

        final PlangScanner scanner =
            PlangScanner(File(filePath).readAsStringSync());
        final PlangParser parser =
            PlangParser(scanner.scan(), filePath: filePath);

        final ParseResult parseResult = parser.parse();

        if (parseResult.errors.isNotEmpty) {
          parsingErrors.addAll(parseResult.errors);
        }

        for (final IncludeDirective include
            in parseResult.compilationUnit.includes) {
          parseFile(
              path.canonicalize(path.absolute(include.pathLiteral.value)));
        }

        compilationUnits[filePath] = parseResult.compilationUnit;
      }

      final Stopwatch stopwatch = Stopwatch();

      stopwatch.start();
      parseFile(executableFile.canonicalizedAbsolutePath());
      stopwatch.stop();

      print('Parsing time: ~${stopwatch.elapsedMilliseconds}ms');

      stopwatch
        ..reset()
        ..start();
      if (parsingErrors.isNotEmpty) {
        for (final ParserError error in parsingErrors) {
          stderr.writeln(
              '${error.message} ${error.filePath}:${1 + error.token.line}:${1 + error.token.column}');
        }

        exit(1);
      }

      final CompilationUnit mainUnit =
          compilationUnits[executableFile.canonicalizedAbsolutePath()]!;

      final List<AnalysisError> basicSyntaxAnalysisErrors =
          BasicSyntaxAnalysis(compilationUnits).analyze(mainUnit);

      if (basicSyntaxAnalysisErrors.isNotEmpty) {
        for (final AnalysisError error in basicSyntaxAnalysisErrors) {
          stderr.writeln(
              '${error.message} ${error.node.compilationFile}:${1 + error.node.token.line}:${1 + error.node.token.column}');
        }
      }

      final List<AnalysisError> basicTypeCheckingAnalysisErrors =
          BasicTypeCheckingAnalysis(compilationUnits).analyze(mainUnit);

      if (basicTypeCheckingAnalysisErrors.isNotEmpty) {
        for (final AnalysisError error in basicTypeCheckingAnalysisErrors) {
          stderr.writeln(
              '${error.message} ${error.node.compilationFile}:${1 + error.node.token.line}:${1 + error.node.token.column}');
        }
      }

      stopwatch.stop();

      print('Static analysis time: ~${stopwatch.elapsedMilliseconds}ms');

      if (basicSyntaxAnalysisErrors.isNotEmpty ||
          basicTypeCheckingAnalysisErrors.isNotEmpty) {
        exit(1);
      }

      final Interpreter interpreter = Interpreter();
      interpreter.run(mainUnit, compilationUnits);
    }
  } on InterpreterException catch (e, st) {
    stderr.writeln(e.toString());
    stderr.writeln('\n$st');
  } catch (e, st) {
    stderr.writeln(e.toString());
    stderr.writeln('\n$st');
  }
}

// class CompilationUnitsGraph {
//   final Map<String, List<String>> _unitDeps = <String, List<String>>{};

//   void addDep(CompilationUnit unit, String dep) {
//     (_unitDeps[unit.filePath] ??= <String>[]).add(dep);
//   }

//   List<(String, String)> calculateCyclicImports() {
//     final List<(String, String)> cycleImports = <(String, String)>[];

//     for (final MapEntry<String, List<String>> entry in _unitDeps.entries) {
//       for (final String dep in entry.value) {
//         if (_unitDeps[dep]?.contains(entry.key) ?? false) {
//           cycleImports.add((entry.key, dep));
//         }
//       }
//     }

//     return cycleImports;
//   }

//   @override
//   String toString() {
//     final StringBuffer buffer = StringBuffer();
//     for (final MapEntry<String, List<String>> entry in _unitDeps.entries) {
//       buffer.writeln(entry.key);
//       for (final String dep in entry.value) {
//         buffer.writeln('  $dep');
//       }
//     }
//     return buffer.toString();
//   }
// }
