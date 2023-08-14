import 'package:plang/src/ast.dart';
import 'package:plang/src/interpreter/interpreter.dart';
import 'package:plang/src/interpreter/runtime/callable.dart';
import 'package:plang/src/interpreter/scope.dart';

class PlangMethod implements PlangCallable {
  PlangMethod({
    required this.name,
    required Scope parentScope,
    required MethodDeclaration methodDeclaration,
  })  : _methodDeclaration = methodDeclaration,
        _parentScope = parentScope;

  final String name;
  final Scope _parentScope;
  final MethodDeclaration _methodDeclaration;

  @override
  int get arity => _methodDeclaration.parameters.length;

  @override
  Object? invoke(Interpreter interpreter, List<Object?> args) {
    final Scope scope = Scope(parent: _parentScope);

    for (var i = 0; i < _methodDeclaration.parameters.length; i += 1) {
      scope.declareAndAssign(
          _methodDeclaration.parameters[i].name.lexeme, args[i]);
    }

    interpreter.runBlock(scope, _methodDeclaration.block!);
    return null;
  }
}

class PlangNativeMethod implements PlangCallable {
  PlangNativeMethod({
    required this.name,
    required Scope parentScope,
    required this.arity,
    required this.callback,
  }) : scope = Scope(parent: parentScope);

  final String name;
  final Scope scope;

  @override
  final int arity;

  final Object? Function(Interpreter interpreter, List<Object?> args) callback;

  @override
  Object? invoke(Interpreter interpreter, List<Object?> args) {
    interpreter.runNativeMethod(
      scope,
      () => Interpreter.returnValue(callback(interpreter, args)),
    );
    return null;
  }
}
