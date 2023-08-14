import 'dart:collection';
import 'dart:io';

import 'package:plang/src/ast.dart';
import 'package:plang/src/extensions.dart';
import 'package:plang/src/interpreter/mixin.dart';
import 'package:plang/src/interpreter/runtime/callable.dart';
import 'package:plang/src/interpreter/runtime/class.dart';
import 'package:plang/src/interpreter/runtime/function.dart';
import 'package:plang/src/interpreter/runtime/instance.dart';
import 'package:plang/src/interpreter/runtime/method.dart';
import 'package:plang/src/interpreter/scope.dart';
import 'package:plang/src/token_type.dart';
import 'package:plang/src/type_names.dart';
import 'package:plang/src/visitor.dart';

enum _Pass {
  declaration,
  topLevelAssignment,
  run,
}

class Interpreter implements RecursiveVisitor<Object?> {
  Interpreter() {
    _scopes.add(_globalScope);

    _globalScope.declareAndAssign(
      'println',
      PlangNativeFunction(
        arity: 0,
        callback: (args) => stdout.writeln(stringify(args[0])),
      ),
    );

    _globalScope.declareAndAssign(
      'print',
      PlangNativeFunction(
        arity: 1,
        callback: (args) => stdout.write(stringify(args[0])),
      ),
    );

    _globalScope.declareAndAssign(
      'clock',
      PlangNativeFunction(
        arity: 1,
        callback: (_) => DateTime.now().millisecondsSinceEpoch,
      ),
    );
  }

  final Scope _globalScope = Scope();
  final Queue<Scope> _scopes = ListQueue<Scope>();

  final Map<String, CompilationUnit> _units = <String, CompilationUnit>{};
  final Set<String> _visitedUnits = <String>{};

  _Pass _pass = _Pass.declaration;

  Scope get _currentScope => _scopes.last;

  void run(CompilationUnit main, Map<String, CompilationUnit> units) {
    _units.addAll(units);

    for (var i = 0; i < _Pass.values.length; i += 1) {
      _pass = _Pass.values[i];
      _visitedUnits.clear();
      _visitedUnits.add(main.resolvedFilePath);
      _visit(main);
    }
  }

  Object? runBlock(Scope scope, Block node) {
    return runStatements(scope, node.statements);
  }

  Object? runSingle(Scope scope, AstNode node) {
    try {
      _pushScope(scope: scope);
      return _evaluate(node);
    } on InterpreterReturnException catch (e) {
      return e.value;
    } finally {
      _popScope();
    }
  }

  Object? runStatements(Scope scope, List<AstNode> statements) {
    try {
      _pushScope(scope: scope);
      for (var i = 0; i < statements.length; i += 1) {
        final AstNode statement = statements[i];
        if (1 + i == statements.length) {
          return _evaluate(statement);
        }
        _visit(statement);
      }
    } finally {
      _popScope();
    }
    return null;
  }

  Object? runNativeMethod(Scope scope, Object? Function() execute) {
    try {
      _pushScope(scope: scope);
      return execute();
    } finally {
      _popScope();
    }
  }

  @pragma('vm:prefer-inline')
  void _visit(AstNode? node) => node?.accept(this);

  @pragma('vm:prefer-inline')
  Object? _evaluate(AstNode? node) => node?.accept(this);

  @pragma('vm:prefer-inline')
  void _pushScope({Scope? scope}) =>
      _scopes.addLast(scope ?? Scope(parent: _currentScope));

  @pragma('vm:prefer-inline')
  void _popScope() => _scopes.removeLast();

  bool isTruthy(Object? value) {
    if (value is! bool) {
      return false;
    }
    return value;
  }

  String stringify(Object? value) {
    switch (value) {
      case PlangInstanceBase():
        if (value.get('toString') case PlangCallable callable) {
          try {
            return callable.invoke(this, []).toString();
          } on InterpreterReturnException catch (e) {
            return e.value.toString();
          }
        }
        return value.toString();
      case String():
        return value;
      case null:
        return 'nil';
      case _:
        return value.toString();
    }
  }

  static Never returnValue(Object? value) {
    throw InterpreterReturnException(value);
  }

  @override
  Object? visitAssignment(AssignmentExpression node) {
    if (_pass == _Pass.declaration) {
      return null;
    }

    final Object? newValue = _evaluate(node.right);
    if (node.left case Identifier id) {
      _currentScope.assign(id.name, newValue);
    } else {
      if (node.left case GetExpression access) {
        if (_evaluate(access.left) case PlangInstanceBase instance) {
          instance.set((access.right as Identifier).name, newValue);
        }
      }

      throw InterpreterException(
        message: 'LHS is not assignable.',
        node: node.left,
      );
    }

    return newValue;
  }

  @override
  Object? visitBinaryExpression(BinaryExpression node) {
    final Object? leftValue = _evaluate(node.left);
    final Object? rightValue = _evaluate(node.right);

    switch (node.token.type) {
      case TokenType.plus:
      case TokenType.plusEqual:
        if (leftValue is num && rightValue is num) {
          return leftValue + rightValue;
        }
        return stringify(leftValue) + stringify(rightValue);
      case TokenType.minus:
      case TokenType.minusEqual:
        if (leftValue is num && rightValue is num) {
          return leftValue - rightValue;
        }
        break;
      case TokenType.star:
        if (leftValue is num && rightValue is num) {
          return leftValue * rightValue;
        }
        if (leftValue is PlangStringInstance && rightValue is int) {
          return leftValue.raw * rightValue;
        }
        break;
      case TokenType.slash:
        if (leftValue is num && rightValue is num) {
          return leftValue / rightValue;
        }
        break;
      case TokenType.lt:
        if (leftValue is num && rightValue is num) {
          return leftValue < rightValue;
        }
        break;
      case TokenType.lte:
        if (leftValue is num && rightValue is num) {
          return leftValue <= rightValue;
        }
        break;
      case TokenType.gt:
        if (leftValue is num && rightValue is num) {
          return leftValue > rightValue;
        }
        break;
      case TokenType.gte:
        if (leftValue is num && rightValue is num) {
          return leftValue >= rightValue;
        }
        break;
      case TokenType.equalEqual:
        return leftValue == rightValue;
      case TokenType.bangEqual:
        return leftValue != rightValue;
      case TokenType.and:
        return isTruthy(leftValue) && isTruthy(rightValue);
      case TokenType.or:
        return isTruthy(leftValue) || isTruthy(rightValue);
      default:
        throw UnimplementedError();
    }

    return null;
  }

  @override
  Object? visitBlock(Block node) {
    return null;
    // for (var i = 0; i < node.statements.length; i += 1) {
    //   final AstNode statement = node.statements[i];
    //   if (1 + i == node.statements.length) {
    //     return _evaluate(statement);
    //   }
    //   _visit(statement);
    // }
    // return null;
  }

  @override
  Object? visitExpressionStatement(ExpressionStatement node) {
    return _evaluate(node.expression);
  }

  @override
  Object? visitFor(ForStatement node) {
    if (_pass == _Pass.declaration) {
      return null;
    }

    if (_pass == _Pass.run && _currentScope == _globalScope) {
      return null;
    }

    _pushScope();

    _visit(node.initializer);

    while (node.condition == null || isTruthy(_evaluate(node.condition))) {
      runBlock(Scope(parent: _currentScope), node.block);
      _visit(node.increment);
    }

    _popScope();
    return null;
  }

  @override
  Object? visitCallExpression(CallExpression node) {
    if (_pass == _Pass.declaration ||
        _pass == _Pass.run && _currentScope == _globalScope) {
      return null;
    }

    switch (_evaluate(node.callee)) {
      case PlangCallable fn:
        _pushScope();

        final List<Object?> arguments = <Object?>[];

        if (fn is PlangAnonymousFunction) {
          arguments.add(fn.arity);
        }

        for (final AstNode arg in node.arguments) {
          arguments.add(_evaluate(arg));
        }

        try {
          return fn.invoke(this, arguments);
        } on InterpreterReturnException catch (e) {
          return e.value;
        } finally {
          _popScope();
        }

      default:
        throw InterpreterException(message: 'Not callable.', node: node.callee);
    }
  }

  @override
  Object? visitFunctionDeclaration(FunctionDeclaration node) {
    if (_pass == _Pass.declaration) {
      _currentScope.declareAndAssign(
        node.name.lexeme,
        PlangFunction(
          parentScope: _currentScope,
          functionDeclaration: node,
        ),
      );
      return null;
    }
    // if (_currentScope.declare(node.name.lexeme)
    //     case VariableStateAlreadyDeclared()) {
    //   throw InterpreterException(
    //       message: 'Function name already exists.', node: node);
    // }

    // if (_pass == _Pass.assignment) {
    //   _currentScope.declareAndAssign(
    //     node.name.lexeme,
    //     PlangFunction(
    //       parentScope: _currentScope,
    //       functionDeclaration: node,
    //     ),
    //   );
    //   return null;
    // }

    if (_globalScope == _currentScope) {
      return null;
    }

    final PlangFunction function = PlangFunction(
      parentScope: _currentScope,
      functionDeclaration: node,
    );
    _currentScope.declareAndAssign(node.name.lexeme, function);

    return function;
  }

  @override
  Object? visitGroupExpression(GroupExpression node) {
    return _evaluate(node.expression);
  }

  @override
  Object? visitIdentifier(Identifier node) {
    if (_pass == _Pass.declaration) {
      return null;
    }

    switch (_currentScope.get(node.name)) {
      case VariableStateGet state:
        return state.value;
      default:
        throw InterpreterException(
            message: 'Variable "${node.name}" is not declared.', node: node);
    }
  }

  @override
  Object? visitIf(IfStatement node) {
    if (_pass == _Pass.declaration ||
        _pass == _Pass.run && _globalScope == _currentScope) {
      return null;
    }

    if (isTruthy(_evaluate(node.condition))) {
      return runBlock(Scope(parent: _currentScope), node.block);
    }

    for (final ElseStatement elseBranch in node.elseBranches) {
      if (elseBranch.ifBranch != null) {
        if (isTruthy(_evaluate(elseBranch.ifBranch!.condition))) {
          return runBlock(
              Scope(parent: _currentScope), elseBranch.ifBranch!.block);
        }
      } else if (elseBranch.block != null) {
        return runBlock(Scope(parent: _currentScope), elseBranch.block!);
      }
    }

    return null;
  }

  @override
  Object? visitElse(ElseStatement node) {
    if (node.block != null) {
      return runBlock(Scope(parent: _currentScope), node.block!);
    }

    return _evaluate(node.ifBranch!);
  }

  @override
  Object? visitLiteralBoolean(LiteralBoolean node) {
    return node.value;
  }

  @override
  Object? visitLiteralNil(LiteralNil node) {
    return null;
  }

  @override
  Object? visitLiteralNumber(LiteralNumber node) {
    return node.value;
  }

  @override
  Object? visitLiteralString(LiteralString node) {
    _pushScope();

    try {
      if (_currentScope.get(kStringType) case VariableStateGet(:final value)
          when value is PlangClass) {
        return value.invoke(this, [node.value]);
      }
    } on InterpreterReturnException catch (e) {
      return e.value;
    } finally {
      _popScope();
    }

    throw UnimplementedError('Should not reach');
  }

  @override
  Object? visitReturn(ReturnStatement node) {
    if (_pass == _Pass.declaration) {
      return null;
    }
    Interpreter.returnValue(_evaluate(node.value));
  }

  @override
  Object? visitVariableDeclaration(VariableDeclaration node) {
    if (_pass == _Pass.declaration) {
      _currentScope.declare(node.name.name);
      return null;
    }

    if (_pass == _Pass.topLevelAssignment) {
      final Object? value = _evaluate(node.initializer);
      if (_currentScope == _globalScope) {
        _currentScope.assign(node.name.name, value);
      } else {
        _currentScope.declareAndAssign(node.name.name, value);
      }
      return value;
    }

    if (_currentScope == _globalScope) {
      return 0;
    }

    if (_currentScope.declare(node.name.name)
        case VariableStateAlreadyDeclared()) {
      throw InterpreterException(
        message: 'Variable already exists.',
        node: node.name,
      );
    }
    _currentScope.assign(node.name.name, _evaluate(node.initializer));
    return null;
  }

  @override
  Object? visitClassDeclaration(ClassDeclaration node) {
    if (_pass == _Pass.declaration) {
      if (node.externalKeyword != null) {
        final PlangNativeClass kclass = PlangNativeClass(
            classDeclaration: node, parentScope: _currentScope);

        if (_currentScope.declareAndAssign(node.name.name, kclass)
            case VariableStateAlreadyDeclared()) {
          throw InterpreterException(
            message: 'Class name "${node.name.name}" already exists.',
            node: node.name,
          );
        }

        return null;
      }

      PlangClass? superClass;

      if (node.superType?.name case String superClassName) {
        if (_currentScope.get(superClassName)
            case VariableStateGet(:final value) when value is PlangClass) {
          superClass = value;
        }
      }

      final PlangClass kclass = PlangClass(
        classDeclaration: node,
        superClassDeclaration: superClass?.classDeclaration,
        parentScope: _currentScope,
      );

      if (_currentScope.declareAndAssign(node.name.name, kclass)
          case VariableStateAlreadyDeclared()) {
        throw InterpreterException(
          message: 'Class name "${node.name.name}" already exists.',
          node: node.name,
        );
      }
    }
    return null;
  }

  @override
  Object? visitMethodDeclaration(MethodDeclaration node) {
    throw UnimplementedError();
  }

  @override
  Object? visitThisExpression(ThisExpression node) {
    return (_currentScope.get(node.name) as VariableStateGet).value;
  }

  @override
  Object? visitGetExpression(GetExpression node) {
    if (_pass == _Pass.declaration) {
      return null;
    }

    final Object? object = _evaluate(node.left);

    if (object case PlangInstanceBase instance) {
      switch (instance.get((node.right as Identifier).name)) {
        case VariableStateGet(:final value):
          return value;
        case PlangMethod method:
          return method;
        case PlangNativeMethod method:
          return method;
        case PlangClass kclass:
          return kclass;
        default:
          throw InterpreterException(
            message: 'Field "${node.right.lexeme}" does not exist.',
            node: node.right,
          );
      }
    }

    if (node.accessor.type == TokenType.questionMarkDot) {
      return null;
    }

    if (object == null) {
      if (node.left case GetExpression left) {
        throw InterpreterException(
          message:
              '"${left.right.lexeme}" is nil. Try using "?." instead of "." when a variable or field might be nil.',
          node: left.right,
        );
      }
    }

    throw InterpreterException(
      message:
          '"${node.left.lexeme}" is nil. Try using "?." instead of "." when a variable or field might be nil.',
      node: node.left,
    );
  }

  @override
  Object? visitSetExpression(SetExpression node) {
    if (_pass == _Pass.declaration) {
      return null;
    }
    if (_evaluate(node.left) case PlangInstanceBase instance) {
      final Object? value = _evaluate(node.value);
      instance.set((node.field as Identifier).name, value);
      return value;
    }
    return null;
  }

  @override
  Object? visitMixinDeclaration(MixinDeclaration node) {
    if (_pass == _Pass.declaration) {
      final PlangMixin kmixin = PlangMixin(mixinDeclaration: node);

      if (_currentScope.declareAndAssign(node.name.name, kmixin)
          case VariableStateAlreadyDeclared()) {
        throw InterpreterException(
          message: 'Mixin name already exists.',
          node: node.name,
        );
      }
    }
    return null;
  }

  @override
  Object? visitIncludeDirective(IncludeDirective node) {
    final String resolvedPath =
        node.pathLiteral.value.canonicalizedAbsolutePath();
    if (_visitedUnits.contains(resolvedPath)) {
      return null;
    }

    _visitedUnits.add(resolvedPath);
    _visit(_units[resolvedPath]);
    return null;
  }

  @override
  Object? visitCompilationUnit(CompilationUnit node) {
    node.includes.forEach(_visit);
    node.statements.forEach(_visit);
    return null;
  }

  @override
  Object? visitAnonymousCallbackDeclaration(AnonymousCallbackDeclaration node) {
    return PlangAnonymousFunction(
      parentScope: _currentScope,
      anonymousCallbackDeclaration: node,
    );
  }

  @override
  Object? visitAnonymousCallExpression(AnonymousCallExpression node) {
    if (_pass == _Pass.declaration) {
      return null;
    }

    if (_pass == _Pass.run && _currentScope == _globalScope) {
      return null;
    }

    switch (_evaluate(node.callee)) {
      case PlangCallable fn:
        _pushScope();

        try {
          return fn.invoke(this, [_evaluate(node.call)]);
        } on InterpreterReturnException catch (e) {
          return e.value;
        } finally {
          _popScope();
        }

      default:
        throw InterpreterException(message: 'Not callable.', node: node.callee);
    }
  }

  @override
  Object? visitType(AnnotatedType node) {
    throw UnimplementedError();
  }

  @override
  Object? visitParameter(Parameter node) {
    throw UnimplementedError();
  }

  @override
  Object? visitConstructorDeclaration(ConstructorDeclaration node) {
    throw UnimplementedError();
  }

  @override
  Object? visitUnaryExpression(UnaryExpression node) {
    final Object? value = _evaluate(node.operand);

    if (node.operator.type == TokenType.bang) {
      return !isTruthy(value);
    } else if (node.operator.type == TokenType.minus && value is num) {
      return -value;
    }

    return value;
  }
}

class InterpreterException implements Exception {
  InterpreterException({
    required this.message,
    required this.node,
  });

  final String message;
  final AstNode node;

  @override
  String toString() {
    return '$message ${node.compilationFile}:${1 + node.token.line}:${1 + node.token.column}';
  }
}

class InterpreterReturnException implements Exception {
  InterpreterReturnException(this.value);

  final Object? value;
}
