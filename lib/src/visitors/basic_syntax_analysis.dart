import 'dart:collection';
import 'dart:io';

import 'package:plang/src/ast.dart';
import 'package:plang/src/extensions.dart';
import 'package:plang/src/models/analysis_error.dart';
import 'package:plang/src/token_type.dart';
import 'package:plang/src/visitor.dart';

enum _Pass {
  topLevelDeclaration,
  topLevelAssignment,
  run;
}

enum _VariableState {
  notDeclared,
  declared,
  unitialized,
  initialized,
  initializedImmutable;

  bool get doesExist => this != _VariableState.notDeclared;
}

class _BasicSyntaxAnalysisScope {
  _BasicSyntaxAnalysisScope({
    _BasicSyntaxAnalysisScope? parentScope,
  }) : _parentScope = parentScope;

  final _BasicSyntaxAnalysisScope? _parentScope;
  final Map<String, _VariableState> _vars = <String, _VariableState>{};

  void declare(String name) {
    _vars[name] = _VariableState.declared;
  }

  void declareVar(String name) {
    _vars[name] = _VariableState.unitialized;
  }

  void assign(String name, {bool isImmutable = false}) {
    _vars[name] = isImmutable
        ? _VariableState.initializedImmutable
        : _VariableState.initialized;
  }

  _VariableState getRecursively(String name) {
    _BasicSyntaxAnalysisScope? scope = this;
    while (scope != null) {
      if (scope._vars.containsKey(name)) {
        return scope._vars[name]!;
      }
      scope = scope._parentScope;
    }
    return _VariableState.notDeclared;
  }

  _VariableState get(String name) {
    return _vars[name] ?? _VariableState.notDeclared;
  }
}

class BasicSyntaxAnalysis implements RecursiveVisitor<void> {
  BasicSyntaxAnalysis(this.units) {
    _scopes.add(_globalScope);
  }

  final _BasicSyntaxAnalysisScope _globalScope = _BasicSyntaxAnalysisScope();
  final ListQueue<_BasicSyntaxAnalysisScope> _scopes =
      ListQueue<_BasicSyntaxAnalysisScope>();
  final List<AnalysisError> _errors = <AnalysisError>[];

  void _pushScope({_BasicSyntaxAnalysisScope? scope}) {
    _scopes
        .addLast(scope ?? _BasicSyntaxAnalysisScope(parentScope: _scopes.last));
  }

  void _popScope() {
    _scopes.removeLast();
  }

  _BasicSyntaxAnalysisScope get _currentScope => _scopes.last;
  bool get _isGlobalScope => _currentScope == _globalScope;

  void _addError(AnalysisError error) => _errors.add(error);

  final Map<String, CompilationUnit> units;
  final Set<String> _visitedUnits = <String>{};

  _Pass _pass = _Pass.topLevelDeclaration;

  List<AnalysisError> analyze(CompilationUnit main) {
    for (final _Pass pass in _Pass.values) {
      _pass = pass;
      _visitedUnits.clear();
      _visitedUnits.add(main.filePath.canonicalizedAbsolutePath());
      _visit(main);
    }
    return List<AnalysisError>.unmodifiable(_errors);
  }

  void _visit(AstNode? node) {
    node?.accept(this);
  }

  @override
  void visitAssignment(AssignmentExpression node) {
    if (_pass == _Pass.topLevelDeclaration) {
      return;
    }

    if (node.left case Identifier id) {
      if (_currentScope.getRecursively(id.name) ==
          _VariableState.initializedImmutable) {
        _addError(AnalysisError(
          type: AnalysisErrorType.error,
          message: 'Identifier "${id.name}" is immutable.',
          node: node.left,
        ));
      }
    }

    // if (node.left is ThisExpression) {
    //   if (_currentScope.getRecursively('this') ==
    //       _VariableState.initializedImmutable) {
    //     _addError(AnalysisError(
    //       type: AnalysisErrorType.error,
    //       message: '"this" can not be reassigned.',
    //       node: node.left,
    //     ));
    //   }
    //   _visit(node.right);
    //   return;
    // }

    _visit(node.left);
    _visit(node.right);
  }

  @override
  void visitBinaryExpression(BinaryExpression node) {
    if (_pass == _Pass.topLevelDeclaration) {
      return;
    }

    _visit(node.left);
    _visit(node.right);
  }

  @override
  void visitBlock(Block node) {
    if (_pass == _Pass.topLevelDeclaration) {
      return;
    }

    node.statements.forEach(_visit);
  }

  @override
  void visitCallExpression(CallExpression node) {
    if (_pass == _Pass.topLevelDeclaration) {
      return;
    }

    // if (node.callee is! LiteralString) {
    //   if (!_currentScope.getRecursively(node.callee.lexeme).doesExist) {
    //     _addError(AnalysisError(
    //       type: AnalysisErrorType.error,
    //       message: 'Callable "${node.callee.lexeme}" not declared.',
    //       node: node.callee,
    //     ));
    //   }
    // }

    _visit(node.callee);
    node.arguments.forEach(_visit);
  }

  @override
  void visitClassDeclaration(ClassDeclaration node) {
    if (_pass == _Pass.topLevelDeclaration && _isGlobalScope) {
      if (_currentScope.getRecursively(node.name.name) ==
          _VariableState.declared) {
        _addError(AnalysisError(
          type: AnalysisErrorType.error,
          message: 'Class name "${node.name.name}" is already declared.',
          node: node,
        ));
      } else {
        _currentScope.declare(node.name.name);
      }
      return;
    }

    if (_pass != _Pass.run) {
      return;
    }

    _pushScope();

    _currentScope.assign('this', isImmutable: true);

    for (final field in node.fields) {
      _currentScope.declare('this.${field.name.name}');
      if (field.initializer != null) {
        _currentScope.assign('this.${field.name.name}',
            isImmutable: field.isImmutable);
      }
    }

    node.constructors.forEach(_visit);
    node.methods.forEach(_visit);

    _popScope();
  }

  @override
  void visitElse(ElseStatement node) {}

  @override
  void visitExpressionStatement(ExpressionStatement node) {
    if (_pass != _Pass.run) {
      return;
    }
    _visit(node.expression);
  }

  @override
  void visitFor(ForStatement node) {
    _pushScope();

    _visit(node.initializer);
    _visit(node.condition);
    _visit(node.increment);

    _pushScope();
    _visit(node.block);
    _popScope();

    _popScope();
  }

  @override
  void visitFunctionDeclaration(FunctionDeclaration node) {
    if (_pass == _Pass.topLevelDeclaration && _isGlobalScope) {
      if (_currentScope.get(node.name.lexeme) == _VariableState.declared) {
        _addError(AnalysisError(
          type: AnalysisErrorType.error,
          message:
              'Duplicate function name "${node.name.lexeme}" is already declared.',
          node: node,
        ));
      } else {
        _currentScope.declare(node.name.lexeme);
      }
      return;
    }

    if (_pass != _Pass.run) {
      return;
    }

    if (!_isGlobalScope) {
      if (_currentScope.get(node.name.name).doesExist) {
        _addError(AnalysisError(
          type: AnalysisErrorType.error,
          message:
              'Duplicate function name "${node.name.lexeme}" is already declared.',
          node: node.name,
        ));
      } else {
        _currentScope.declare(node.name.lexeme);
      }
    }

    _pushScope();

    for (final Parameter parameter in node.parameters) {
      if (_currentScope.get(parameter.name.lexeme).doesExist) {
        _addError(AnalysisError(
          type: AnalysisErrorType.error,
          message: 'Parameter "${parameter.name.name}" already declared.',
          node: parameter.name,
        ));
      }

      _currentScope.assign(parameter.name.lexeme, isImmutable: true);
      _visit(parameter);
    }

    _visit(node.returnType);
    _visit(node.block);

    _popScope();
  }

  @override
  void visitGetExpression(GetExpression node) {
    // if (node.left is ThisExpression) {
    //   _visit(node.left);
    //   if (node.right case Identifier right) {
    //     if (!_currentScope.getRecursively('this.${right.name}').doesExist) {
    //       _addError(AnalysisError(
    //         type: AnalysisErrorType.error,
    //         message: 'Field "${right.name}" is not declared.',
    //         node: right,
    //       ));
    //     }
    //   }
    // }
  }

  @override
  void visitGroupExpression(GroupExpression node) {
    _visit(node.expression);
  }

  @override
  void visitIdentifier(Identifier node) {
    final _VariableState variableState =
        _currentScope.getRecursively(node.name);

    if (variableState == _VariableState.notDeclared) {
      _addError(AnalysisError(
        type: AnalysisErrorType.error,
        message: '"${node.name}" is not declared.',
        node: node,
      ));
      return;
    }

    if (variableState == _VariableState.unitialized) {
      _addError(AnalysisError(
        type: AnalysisErrorType.error,
        message: '"${node.name}" is not initialized yet.',
        node: node,
      ));
      return;
    }
  }

  @override
  void visitIf(IfStatement node) {
    if (_pass == _Pass.topLevelDeclaration) {
      return;
    }

    _visit(node.condition);

    if (node.block.statements.isEmpty) {
      _addError(AnalysisError(
        type: AnalysisErrorType.warning,
        message: "Empty block.",
        node: node.block,
      ));
    }

    _pushScope();
    _visit(node.block);
    _popScope();

    final int elseIndex =
        node.elseBranches.indexWhere((element) => element.block != null);

    if (elseIndex != -1 && (node.elseBranches.length - 1) > elseIndex) {
      final ElseStatement elseBranch = node.elseBranches[elseIndex];
      _addError(AnalysisError(
        type: AnalysisErrorType.error,
        message: '"else" is only allowed as the last branch.',
        node: elseBranch,
      ));
    }

    for (final branch in node.elseBranches) {
      if (branch.ifBranch != null) {
        _visit(branch.ifBranch?.condition);

        if (branch.ifBranch!.block.statements.isEmpty) {
          _addError(AnalysisError(
            type: AnalysisErrorType.warning,
            message: "Empty block.",
            node: branch.ifBranch!,
          ));
        }

        _pushScope();
        _visit(branch.ifBranch?.block);
        _popScope();
      }

      if (branch.block != null) {
        if (branch.block!.statements.isEmpty) {
          _addError(AnalysisError(
            type: AnalysisErrorType.warning,
            message: "Empty block.",
            node: branch.block!,
          ));
        }

        _pushScope();
        _visit(branch.block);
        _popScope();
      }
    }
  }

  @override
  void visitLiteralBoolean(LiteralBoolean node) {}

  @override
  void visitLiteralNil(LiteralNil node) {}

  @override
  void visitLiteralNumber(LiteralNumber node) {}

  @override
  void visitLiteralString(LiteralString node) {}

  @override
  void visitMethodDeclaration(MethodDeclaration node) {
    _pushScope();

    for (final Parameter parameter in node.parameters) {
      _currentScope.assign(parameter.name.name, isImmutable: true);
    }

    node.parameters.forEach(_visit);

    _visit(node.block);

    _popScope();
  }

  @override
  void visitMixinDeclaration(MixinDeclaration node) {
    if (_pass == _Pass.topLevelDeclaration && _isGlobalScope) {
      if (_currentScope.getRecursively(node.name.name) ==
          _VariableState.declared) {
        _addError(AnalysisError(
          type: AnalysisErrorType.error,
          message: 'Mixin "${node.name}" is already declared.',
          node: node,
        ));
      } else {
        _currentScope.declare(node.name.name);
      }
      return;
    }

    _pushScope();

    _currentScope.assign('this', isImmutable: true);
    node.methods.forEach(_visit);

    _popScope();
  }

  @override
  void visitReturn(ReturnStatement node) {
    if (_pass != _Pass.run) {
      return;
    }

    if (node.hasParent((parent) =>
        parent is FunctionDeclaration || parent is MethodDeclaration)) {
      _visit(node.value);
      return;
    }

    _addError(AnalysisError(
      type: AnalysisErrorType.error,
      message: '"return" keyword is only allowed inside a function or method.',
      line: node.token.line,
      column: node.token.column,
      node: node,
    ));

    _visit(node.value);
  }

  @override
  void visitSetExpression(SetExpression node) {
    // if (node.left is ThisExpression) {
    //   if (node.field case Identifier right) {
    //     if (!_currentScope.getRecursively('this.${right.name}').doesExist) {
    //       _addError(AnalysisError(
    //         type: AnalysisErrorType.error,
    //         message: 'Field "${right.name}" is not declared.',
    //         node: right,
    //       ));
    //     }
    //   }
    // }
    _visit(node.left);
    _visit(node.value);
  }

  @override
  void visitThisExpression(ThisExpression node) {
    if (!node.hasParent(
        (parent) => parent is ClassDeclaration || parent is MixinDeclaration)) {
      _addError(AnalysisError(
        type: AnalysisErrorType.error,
        message: '"this" is only allowed inside a method\'s body.',
        node: node,
      ));
    }
  }

  @override
  void visitVariableDeclaration(VariableDeclaration node) {
    if (_pass == _Pass.topLevelDeclaration && _isGlobalScope) {
      if (_currentScope.get(node.name.name).doesExist) {
        _addError(AnalysisError(
          type: AnalysisErrorType.error,
          message: 'Variable name "${node.name.name}" is already declared.',
          node: node.name,
        ));
      }
      _currentScope.declareVar(node.name.name);
      return;
    }

    if (_pass == _Pass.topLevelAssignment) {
      if (_isGlobalScope) {
        if (_currentScope.get(node.name.name) == _VariableState.notDeclared) {
          _addError(AnalysisError(
            type: AnalysisErrorType.error,
            message: 'Variable name "${node.name.name}" is not declared.',
            node: node.name,
          ));
        }
      }

      _visit(node.type);
      _visit(node.initializer);

      _currentScope.assign(node.name.name, isImmutable: node.isImmutable);

      // if (node.initializer != null) {
      //   final String initializerType =
      //       TypeEvaluator(_declaredTypes).evaluate(node.initializer);
      //   if (initializerType != kNilType && node.type.name != initializerType) {
      //     _addError(AnalysisError(
      //       type: AnalysisErrorType.error,
      //       message:
      //           'Initializer value type "$initializerType" is not compatibible with provided type "${node.type.name}".',
      //       node: node.initializer!,
      //     ));
      //   }
      // }
      return;
    }

    if (_pass == _Pass.run && !_isGlobalScope) {
      if (_currentScope.get(node.name.name).doesExist) {
        _addError(AnalysisError(
          type: AnalysisErrorType.error,
          message: 'Parameter "${node.name.name}" already declared.',
          node: node.name,
        ));
      }

      _currentScope.declare(node.name.name);

      _visit(node.type);

      if (node.initializer != null) {
        // final String initializerType =
        //     TypeEvaluator(_declaredTypes).evaluate(node.initializer);
        // if (initializerType != kNilType && node.type.name != initializerType) {
        //   _addError(AnalysisError(
        //     type: AnalysisErrorType.error,
        //     message:
        //         'Initializer value type "$initializerType" is not compatibible with provided type "${node.type.name}".',
        //     node: node.initializer!,
        //   ));
        // }

        _currentScope.assign(node.name.name, isImmutable: node.isImmutable);
        _visit(node.initializer);
      }
      return;
    }
  }

  @override
  void visitIncludeDirective(IncludeDirective node) {
    final String filePath = node.pathLiteral.value.canonicalizedAbsolutePath();

    if (_visitedUnits.contains(filePath)) {
      return;
    }
    _visitedUnits.add(filePath);

    if (!File(filePath).existsSync()) {
      _addError(AnalysisError(
        type: AnalysisErrorType.error,
        message: 'Include file not found.',
        node: node.pathLiteral,
      ));
    }

    _visit(units[filePath]!);
  }

  @override
  void visitCompilationUnit(CompilationUnit node) {
    node.includes.forEach(_visit);
    node.statements.forEach(_visit);
  }

  @override
  void visitAnonymousCallbackDeclaration(AnonymousCallbackDeclaration node) {}

  @override
  void visitAnonymousCallExpression(AnonymousCallExpression node) {
    _visit(node.callee);
    _visit(node.call);
  }

  @override
  void visitType(AnnotatedType node) {}

  @override
  void visitParameter(Parameter node) {}

  @override
  void visitConstructorDeclaration(ConstructorDeclaration node) {
    _pushScope();

    for (final Parameter parameter in node.parameters) {
      if (_currentScope.get(parameter.name.lexeme).doesExist) {
        _addError(AnalysisError(
          type: AnalysisErrorType.error,
          message: 'Parameter "${parameter.name.name}" already declared.',
          node: parameter.name,
        ));
      }

      _currentScope.assign(parameter.name.name, isImmutable: true);
      _visit(parameter);
    }

    _visit(node.block);

    _popScope();
  }

  @override
  void visitUnaryExpression(UnaryExpression node) {
    if (_pass == _Pass.topLevelDeclaration) {
      return;
    }
    switch (node.operator.type) {
      case TokenType.bang:
      case TokenType.minus:
        break;
      default:
        _addError(AnalysisError(
          type: AnalysisErrorType.error,
          message:
              'Parameter "${node.operator.lexeme}" is not valid unary operator.',
          node: node,
        ));
        break;
    }
    _visit(node.operand);
  }
}
