import 'package:plang/src/ast.dart';
import 'package:plang/src/interpreter/interpreter.dart';
import 'package:plang/src/interpreter/runtime/callable.dart';
import 'package:plang/src/interpreter/scope.dart';

class PlangFunction implements PlangCallable {
  PlangFunction({
    required Scope parentScope,
    required FunctionDeclaration functionDeclaration,
  })  : _functionDeclaration = functionDeclaration,
        _parentScope = parentScope;

  final Scope _parentScope;
  final FunctionDeclaration _functionDeclaration;

  @override
  int get arity => _functionDeclaration.parameters.length;

  @override
  Object? invoke(Interpreter interpreter, List<Object?> args) {
    final scope = Scope(parent: _parentScope);

    for (var i = 0; i < _functionDeclaration.parameters.length; i += 1) {
      scope.declareAndAssign(
          _functionDeclaration.parameters[i].name.lexeme, args[i]);
    }

    return interpreter.runBlock(scope, _functionDeclaration.block!);
  }
}

class PlangAnonymousFunction implements PlangCallable {
  PlangAnonymousFunction({
    required Scope parentScope,
    required AnonymousCallbackDeclaration anonymousCallbackDeclaration,
  })  : _anonymousCallbackDeclaration = anonymousCallbackDeclaration,
        _parentScope = parentScope;

  final Scope _parentScope;
  final AnonymousCallbackDeclaration _anonymousCallbackDeclaration;

  @override
  // arity is provided as the first argument in [Invoke args]
  final int arity = 0;

  @override
  Object? invoke(Interpreter interpreter, List<Object?> args) {
    final Scope scope = Scope(parent: _parentScope);
    final int arity = args[0] as int;

    if (_anonymousCallbackDeclaration.parameters.isEmpty) {
      if (arity == 1) {
        scope.declareAndAssign('arg', args[1]);
      } else {
        for (var i = 1; i <= arity; i += 1) {
          scope.declareAndAssign('arg$i', args[i]);
        }
      }
    }

    for (var i = 0;
        i < _anonymousCallbackDeclaration.parameters.length;
        i += 1) {
      scope.declareAndAssign(
        _anonymousCallbackDeclaration.parameters[i].name,
        args[1 + i],
      );
    }

    return interpreter.runStatements(
      scope,
      _anonymousCallbackDeclaration.statements,
    );
  }
}

class PlangNativeFunction implements PlangCallable {
  PlangNativeFunction({
    required this.arity,
    required this.callback,
  });

  @override
  final int arity;

  final Object? Function(List<Object?> args) callback;

  @override
  Object? invoke(Interpreter interpreter, List<Object?> args) {
    callback(args);
    return null;
  }
}
