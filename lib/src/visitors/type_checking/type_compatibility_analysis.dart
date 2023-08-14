import 'dart:collection';

import 'package:plang/src/ast.dart';
import 'package:plang/src/extensions.dart';
import 'package:plang/src/models/analysis_error.dart';
import 'package:plang/src/token_type.dart';
import 'package:plang/src/type_names.dart';
import 'package:plang/src/visitor.dart';

class TypeEnvironment {
  TypeEnvironment({
    TypeEnvironment? parent,
  }) : _parent = parent;

  final TypeEnvironment? _parent;
  final Map<String, AstNode> _values = <String, AstNode>{};

  void set(String name, AstNode value) => _values[name] = value;

  T? get<T>(String name) {
    for (TypeEnvironment? scope = this; scope != null; scope = scope._parent) {
      if (scope._values.containsKey(name) && scope._values[name] is T) {
        return scope._values[name]! as T;
      }
    }
    return null;
  }
}

class ResolvedType {
  ResolvedType({
    required this.type,
    required this.providedTypeParameters,
  });

  final TypeDefinition type;
  final List<TypeDefinition> providedTypeParameters;

  String get resolvedName {
    final StringBuffer buffer = StringBuffer();

    buffer.write(type.name.name);

    if (providedTypeParameters.isNotEmpty) {
      buffer.write('<');
      for (var i = 0; i < providedTypeParameters.length; i += 1) {
        buffer.write(providedTypeParameters[i].name.name);
        if (1 + i < providedTypeParameters.length) {
          buffer.write(', ');
        }
      }
      buffer.write('>');
    }

    return buffer.toString();
  }
}

class TypeCompatibilityAnalysis implements RecursiveVisitor<ResolvedType> {
  TypeCompatibilityAnalysis({
    required final TypeEnvironment scope,
  }) : _globalScope = scope {
    _scopes.addLast(_globalScope);
  }

  final TypeEnvironment _globalScope;

  final ListQueue<TypeEnvironment> _scopes = ListQueue<TypeEnvironment>();

  final List<AnalysisError> _errors = <AnalysisError>[];

  List<AnalysisError> analyze(List<AstNode> nodes) {
    nodes.forEach(_visit);
    return List<AnalysisError>.unmodifiable(_errors);
  }

  ResolvedType _visit(final AstNode node) => node.accept(this);

  void _addError(AnalysisError error) => _errors.add(error);

  void _pushScope() => _scopes.addLast(TypeEnvironment(parent: _scopes.last));

  void _popScope() => _scopes.removeLast();

  bool get _isGlobalScope => _scopes.last == _globalScope;

  TypeEnvironment get _currentScope => _scopes.last;

  TypeDefinition _findType(final String typeName) {
    return _globalScope.get<TypeDefinition>(typeName) ??
        _globalScope.get<TypeDefinition>(kUnknownType)!;
  }

  bool _isCompatibleType(ResolvedType lhs, ResolvedType rhs) {
    if (lhs.type.name.name == kObjectType) {
      return true;
    }

    if (lhs.type.name.name == rhs.type.name.name) {
      if (lhs.providedTypeParameters.length !=
          rhs.providedTypeParameters.length) {
        return false;
      }
      if (lhs.providedTypeParameters.isEmpty) {
        return true;
      }
      for (var i = 0; i < lhs.providedTypeParameters.length; i += 1) {
        final TypeDefinition lhsTypeParam = lhs.providedTypeParameters[i];
        final TypeDefinition rhsTypeParam = rhs.providedTypeParameters[i];
        if (_isAssignmentCompatibleType(
            lhsTypeParam.asResolvedType(), rhsTypeParam.asResolvedType())) {
          return true;
        }
      }
    }

    final ListQueue<String> superTypes = ListQueue<String>()
      ..addAll(rhs.type.superTypes);

    while (superTypes.isNotEmpty) {
      final TypeDefinition superType = _findType(superTypes.removeFirst());
      if (lhs.type.name.name == superType.name.name) {
        return true;
      }
      superTypes.addAll(superType.superTypes);
    }

    return false;
  }

  bool _isAssignmentCompatibleType(ResolvedType lhs, ResolvedType rhs) {
    if (lhs.type.name.name == kIntType && rhs.type.name.name != kIntType) {
      return false;
    }
    if (lhs.type.name.name == kDoubleType &&
        rhs.type.superTypes.contains(kNumberType)) {
      return true;
    }
    return _isCompatibleType(lhs, rhs);
  }

  void _addUnknownTypeError(AstNode node) {
    _addError(AnalysisError(
      type: AnalysisErrorType.error,
      message: 'Unknown type found.',
      node: node,
    ));
  }

  ResolvedType _resolvedTypeFromAnnotatedType(AnnotatedType type) {
    return ResolvedType(
      type: _findType(type.name.name),
      providedTypeParameters: type.typeParameters
          .map((e) => _findType(e.name.name))
          .cast<TypeDefinition>()
          .toList(growable: false),
    );
  }

  @override
  ResolvedType visitBinaryExpression(BinaryExpression node) {
    final ResolvedType lhs = _visit(node.left);
    final ResolvedType rhs = _visit(node.right);

    if (lhs.type.isUnknownType) {
      _addUnknownTypeError(node.left);
    }
    if (rhs.type.isUnknownType) {
      _addUnknownTypeError(node.right);
    }

    switch (node.token.type) {
      case TokenType.plus:
        if (_chainSearchMethod(lhs.type, 'plus')
            case MethodDeclaration methodDecl) {
          _checkCall(methodDecl.parameters, [node.right],
              methodDecl.typeParameters, node.left);
          return _resolvedTypeFromAnnotatedType(methodDecl.returnType);
        }
        break;
      case TokenType.plusEqual:
        if (_chainSearchMethod(lhs.type, 'plus')
            case MethodDeclaration methodDecl) {
          _checkCall(methodDecl.parameters, [node.right],
              methodDecl.typeParameters, node.left);
          return _resolvedTypeFromAnnotatedType(methodDecl.returnType);
        }
        break;
      case TokenType.minus:
        if (_chainSearchMethod(lhs.type, 'minus')
            case MethodDeclaration methodDecl) {
          _checkCall(methodDecl.parameters, [node.right],
              methodDecl.typeParameters, node.left);
          return _resolvedTypeFromAnnotatedType(methodDecl.returnType);
        }
        break;
      case TokenType.slash:
        if (lhs.type.name.name == kDoubleType &&
                rhs.type.name.name == kDoubleType ||
            lhs.type.name.name == kIntType &&
                rhs.type.name.name == kDoubleType ||
            lhs.type.name.name == kDoubleType &&
                rhs.type.name.name == kIntType) {
          return _findType(kDoubleType).asResolvedType();
        }
        if (lhs.type.name.name == kIntType && rhs.type.name.name == kIntType) {
          return _findType(kIntType).asResolvedType();
        }
        break;
      case TokenType.star:
        if (lhs.type.name.name == kDoubleType &&
                rhs.type.name.name == kDoubleType ||
            lhs.type.name.name == kIntType &&
                rhs.type.name.name == kDoubleType ||
            lhs.type.name.name == kDoubleType &&
                rhs.type.name.name == kIntType) {
          return _findType(kDoubleType).asResolvedType();
        }
        if (lhs.type.name.name == kIntType && rhs.type.name.name == kIntType) {
          return _findType(kIntType).asResolvedType();
        }
        if (lhs.type.name.name == kStringType &&
            rhs.type.name.name == kIntType) {
          return _findType(kStringType).asResolvedType();
        }
        break;
      case TokenType.and:
      case TokenType.or:
        if (lhs.type.name.name == kBoolType && _isCompatibleType(lhs, rhs)) {
          return _findType(kBoolType).asResolvedType();
        }
        break;
      case TokenType.equalEqual:
      case TokenType.bangEqual:
      case TokenType.lt:
      case TokenType.lte:
      case TokenType.gt:
      case TokenType.gte:
        return _findType(kBoolType).asResolvedType();
      default:
    }

    _addError(AnalysisError(
      type: AnalysisErrorType.error,
      message:
          'Operation "${node.token.lexeme}" between "${lhs.resolvedName}" and "${rhs.resolvedName}" is not compatible.',
      node: node,
    ));

    return rhs;
  }

  @override
  ResolvedType visitBlock(Block node) {
    for (var i = 0; i < node.statements.length; i += 1) {
      if (1 + i == node.statements.length) {
        return _visit(node.statements[i]);
      }
      _visit(node.statements[i]);
    }
    return _findType(kUnknownType).asResolvedType();
  }

  void _checkCall(
    List<Parameter> parameters,
    List<AstNode> arguments,
    List<AnnotatedType> typeParameters,
    AstNode node,
  ) {
    if (node case Identifier identifier) {
      final AstNode targetNode = _currentScope.get(identifier.name);
      if (targetNode is ClassDeclaration) {
        if (targetNode.typeParameters.length != typeParameters.length) {
          _addError(AnalysisError(
            type: AnalysisErrorType.error,
            message:
                'Expected ${targetNode.typeParameters.length} generic arguments received ${typeParameters.length} instead.',
            node: node,
          ));
        }
      }
    }

    for (var i = 0; i < parameters.length; i += 1) {
      final String? parameterTypeName =
          parameters.elementAtOrNull(i)?.type.name.name;

      if (i >= arguments.length || parameterTypeName == null) {
        _addError(AnalysisError(
          type: AnalysisErrorType.error,
          message:
              'Expected argument of type "$parameterTypeName" at position ${1 + i}, instead found nothing.',
          node: node,
        ));
        continue;
      }

      final ResolvedType argumentType = _visit(arguments[i]);
      late ResolvedType parameterType =
          switch (_currentScope.get(parameterTypeName)) {
        AnnotatedType type => _resolvedTypeFromAnnotatedType(type),
        TypeDefinition typeDef => typeDef.asResolvedType(),
        ConstructorDeclaration ctor =>
          _findType(ctor.name.name).asResolvedType(),
        _ => _findType(parameterTypeName).asResolvedType(),
      };

      if (!_isAssignmentCompatibleType(parameterType, argumentType)) {
        _addError(AnalysisError(
          type: AnalysisErrorType.error,
          message:
              'Argument type "${argumentType.resolvedName}" is not assignable to parameter type "${parameterType.resolvedName}".',
          node: arguments[i],
        ));
      }
    }
  }

  @override
  ResolvedType visitCallExpression(CallExpression node) {
    if (node.callee case Identifier callee) {
      _pushScope();
      final AstNode calleeType =
          _currentScope.get<AstNode>(callee.name) ?? _findType(kUnknownType);

      if (calleeType case ClassDeclaration classDecl) {
        if (classDecl.isUnknownType) {
          _addError(AnalysisError(
            type: AnalysisErrorType.error,
            message: 'Unknown type found.',
            node: node,
          ));
        }

        for (int i = 0; i < node.typeParameters.length; i += 1) {
          _currentScope.set(
              calleeType.typeParameters[i].name.name, node.typeParameters[i]);
        }
      }

      if (calleeType case Callable callable) {
        for (int i = 0; i < node.typeParameters.length; i += 1) {
          _currentScope.set(
              callable.typeParameters[i].name.name, node.typeParameters[i]);
        }
      }

      final List<Parameter> parameters = switch (calleeType) {
        Callable() => calleeType.parameters,
        ClassDeclaration() => calleeType.constructors.firstOrNull?.parameters ??
            const <Parameter>[],
        _ => const <Parameter>[],
      };

      _checkCall(
        parameters,
        node.arguments,
        node.typeParameters,
        node.callee,
      );

      final ResolvedType resolvedType = switch (calleeType) {
        AnnotatedType type => _resolvedTypeFromAnnotatedType(type),
        Callable() => _resolvedTypeFromAnnotatedType(calleeType.returnType),
        TypeDefinition() => ResolvedType(
            type: calleeType,
            providedTypeParameters: node.typeParameters
                .map((e) => _findType(e.name.name))
                .cast<TypeDefinition>()
                .toList(growable: false),
          ),
        _ => _findType(kUnknownType).asResolvedType(),
      };

      _popScope();
      return resolvedType;
    }

    if (node.callee case GetExpression getExpression) {
      _pushScope();
      final AstNode? resolved = _resolveFromGetExpression(getExpression);

      if (resolved == null) {
        _popScope();
        return _findType(kUnknownType).asResolvedType();
      }

      if (resolved is Callable) {
        _checkCall(
          resolved.parameters,
          node.arguments,
          node.typeParameters,
          node.callee,
        );

        final ResolvedType resolvedType =
            switch (_currentScope.get(resolved.returnType.name.name)) {
          AnnotatedType type => _resolvedTypeFromAnnotatedType(type),
          Callable callable =>
            _resolvedTypeFromAnnotatedType(callable.returnType),
          TypeDefinition typeDef => typeDef.asResolvedType(),
          _ => _findType(kUnknownType).asResolvedType(),
        };
        _popScope();

        // if (node.typeParameters.length != resolved.typeParameters.length) {
        //   _addError(AnalysisError(
        //     type: AnalysisErrorType.error,
        //     'Expected ${targetNode.typeParameters.length} generic arguments received ${typeParameters.length} instead.',
        //     node: node,
        //   ));
        // }

        for (var i = 0; i < resolved.typeParameters.length; i += 1) {
          _currentScope.set(
              resolved.typeParameters[i].name.name, node.typeParameters[i]);
        }

        // for (var i = 0; i < resolvedType.type.typeParameters.length; i += 1) {
        //   _currentScope.set(resolvedType.type.typeParameters[i].name.name,
        //       resolvedType.providedTypeParameters[i]);
        // }

        return resolvedType;
      }

      if (resolved is VariableDeclaration) {
        _popScope();
        return _resolvedTypeFromAnnotatedType(resolved.type);
      }

      _popScope();
    }

    if (node.callee is CallExpression) {
      return _visit(node.callee);
    }

    return _findType(kNilType).asResolvedType();
  }

  AstNode? _resolveFromGetExpression(GetExpression getExpression) {
    TypeDefinition lhsType;
    if (getExpression.left case GetExpression left) {
      lhsType = _visit(left).type;
    } else if (getExpression.left case Identifier left) {
      lhsType = _visit(left).type;

      if (_currentScope.get(left.name) case VariableDeclaration varDecl) {
        for (var i = 0; i < lhsType.typeParameters.length; i += 1) {
          _currentScope.set(lhsType.typeParameters[i].name.name,
              varDecl.type.typeParameters[i]);
        }
      }
    } else if (getExpression.left case CallExpression left) {
      lhsType = _visit(left).type;
    } else {
      lhsType = _findType(kUnknownType);
      throw UnimplementedError('asdf');
    }

    if (lhsType.isUnknownType) {
      _addError(AnalysisError(
        type: AnalysisErrorType.error,
        message: 'Field does not exist.',
        node: getExpression.right,
      ));
      return null;
    }

    if (getExpression.right case Identifier rhs) {
      if (lhsType is ClassDeclaration) {
        if (_chainSearchField(lhsType, rhs.name)
            case VariableDeclaration field) {
          return field;
        }
      }

      if (_chainSearchMethod(lhsType, rhs.name) case Callable callable) {
        return callable;
      }

      _addError(AnalysisError(
        type: AnalysisErrorType.error,
        message:
            'Name "${rhs.name}" not declared on type "${lhsType.name.name}".',
        node: rhs,
      ));
    }

    return null;
  }

  Callable? _chainSearchMethod(
      TypeDefinition typeDefinition, String methodName) {
    MethodDeclaration? method = typeDefinition.methods.firstWhereOrNull(
        (MethodDeclaration method) => method.name.name == methodName);

    if (method != null) {
      return method;
    }

    for (final String superType in typeDefinition.superTypes) {
      final TypeDefinition superTypeDefinition = _findType(superType);
      method = superTypeDefinition.methods.firstWhereOrNull(
          (MethodDeclaration method) => method.name.name == methodName);
      if (method != null) {
        return method;
      }
    }

    return _findType(kObjectType).methods.firstWhereOrNull(
        (MethodDeclaration method) => method.name.name == methodName);
  }

  VariableDeclaration? _chainSearchField(
      ClassDeclaration classDeclaration, String fieldName) {
    VariableDeclaration? field = classDeclaration.fields.firstWhereOrNull(
        (VariableDeclaration field) => field.name.name == fieldName);

    if (field != null) {
      return field;
    }

    for (final String superType in classDeclaration.superTypes) {
      final TypeDefinition superTypeDefinition = _findType(superType);
      if (superTypeDefinition is! ClassDeclaration) {
        continue;
      }
      field = superTypeDefinition.fields.firstWhereOrNull(
          (VariableDeclaration field) => field.name.name == fieldName);
      if (field != null) {
        return field;
      }
    }

    return (_findType(kObjectType) as ClassDeclaration).fields.firstWhereOrNull(
        (VariableDeclaration field) => field.name.name == fieldName);
  }

  @override
  ResolvedType visitClassDeclaration(ClassDeclaration node) {
    _pushScope();

    _currentScope.set('this', node);

    for (final MethodDeclaration method in node.methods) {
      _currentScope.set('this.${method.name.lexeme}', method);
      _currentScope.set(method.name.lexeme, method);
    }

    for (final VariableDeclaration field in node.fields) {
      _currentScope.set('this.${field.name.name}', field);
      _visit(field);
    }

    for (final ConstructorDeclaration constructor in node.constructors) {
      _visit(constructor);
    }

    for (final MethodDeclaration method in node.methods) {
      _visit(method);
    }

    _popScope();

    return node.asResolvedType();
  }

  @override
  ResolvedType visitFunctionDeclaration(FunctionDeclaration node) {
    if (!_isGlobalScope) {
      _currentScope.set(node.name.name, node);
    }

    if (node.block != null) {
      _pushScope();
      for (final Parameter param in node.parameters) {
        _currentScope.set(param.name.lexeme, param);
      }
      _visit(node.block!);
      _popScope();
    }
    return _findType(kUnknownType).asResolvedType();
  }

  @override
  ResolvedType visitIdentifier(Identifier node) {
    return switch (_currentScope.get(node.name)) {
      TypeDefinition typeDef => typeDef.asResolvedType(),
      Parameter param => _resolvedTypeFromAnnotatedType(param.type),
      VariableDeclaration varDecl =>
        _resolvedTypeFromAnnotatedType(varDecl.type),
      _ => _findType(kUnknownType).asResolvedType(),
    };
  }

  @override
  ResolvedType visitMethodDeclaration(MethodDeclaration node) {
    if (node.block != null) {
      _pushScope();
      for (final Parameter param in node.parameters) {
        _currentScope.set(param.name.lexeme, param);
      }
      _visit(node.block!);
      _popScope();
    }
    return _resolvedTypeFromAnnotatedType(node.returnType);
  }

  @override
  ResolvedType visitMixinDeclaration(MixinDeclaration node) {
    return node.asResolvedType();
  }

  @override
  ResolvedType visitParameter(Parameter node) {
    return _visit(node.type);
  }

  @override
  ResolvedType visitVariableDeclaration(VariableDeclaration node) {
    if (!_isGlobalScope) {
      _currentScope.set(node.name.name, node);
    }

    if (node.initializer != null) {
      final ResolvedType variableType = _visit(node.type);
      final ResolvedType initializerType = _visit(node.initializer!);

      if (!_isAssignmentCompatibleType(variableType, initializerType)) {
        _addError(AnalysisError(
          type: AnalysisErrorType.error,
          message:
              'Value of type "${initializerType.resolvedName}" is not assignable to type "${variableType.resolvedName}".',
          node: node.initializer!,
        ));
      }

      return initializerType;
    }
    return _findType(kNilType).asResolvedType();
  }

  @override
  ResolvedType visitLiteralNumber(LiteralNumber node) {
    if (node.value is double) {
      return _findType(kDoubleType).asResolvedType();
    }
    return _findType(kIntType).asResolvedType();
  }

  @override
  ResolvedType visitLiteralString(LiteralString node) {
    return _findType(kStringType).asResolvedType();
  }

  @override
  ResolvedType visitAssignment(AssignmentExpression node) {
    final lhs = _visit(node.left);
    final rhs = _visit(node.right);

    if (lhs.type.isUnknownType || node.left is ThisExpression) {
      return rhs;
    }

    if (!_isAssignmentCompatibleType(lhs, rhs)) {
      _addError(AnalysisError(
        type: AnalysisErrorType.error,
        message:
            '"${rhs.resolvedName}" is not subtype of "${lhs.resolvedName}".',
        node: node.right,
      ));
    }

    return lhs;
  }

  @override
  ResolvedType visitLiteralBoolean(LiteralBoolean node) {
    return _findType(kBoolType).asResolvedType();
  }

  @override
  ResolvedType visitReturn(ReturnStatement node) {
    if (node.value != null) {
      final ResolvedType returnType = _visit(node.value!);
      {
        final Callable? parent =
            node.getParentNode((parent) => parent is Callable) as Callable?;

        if (parent is! Callable) {
          return _findType(kNilType).asResolvedType();
        }

        if (parent.returnType.name.name == kVoidType &&
            returnType.type.name.name != kVoidType) {
          _addError(AnalysisError(
            type: AnalysisErrorType.error,
            message:
                'Invalid return value of type "${returnType.resolvedName}". Return type of "${parent.name.name}" is "Void", so only an empty "return" is allowed.',
            node: node.value!,
          ));
        }

        if (!_isCompatibleType(
            _resolvedTypeFromAnnotatedType(parent.returnType), returnType)) {
          _addError(AnalysisError(
            type: AnalysisErrorType.error,
            message:
                'Return value of type "${returnType.resolvedName}" is not compatible with the return type "${parent.returnType.name.name}" of "${parent.name.name}".',
            node: node.value!,
          ));
        }
      }
    }
    return _findType(kVoidType).asResolvedType();
  }

  @override
  ResolvedType visitIf(IfStatement node) {
    if (!_isCompatibleType(
        _visit(node.condition), _findType(kBoolType).asResolvedType())) {
      _addError(AnalysisError(
        type: AnalysisErrorType.error,
        message: "Condition type must be '$kBoolType'.",
        node: node.condition,
      ));
    }
    _visit(node.block);

    for (final elseBranch in node.elseBranches) {
      if (elseBranch.ifBranch case IfStatement ifBranch) {
        final ResolvedType conditionType = _visit(ifBranch.condition);
        if (!_isCompatibleType(
            conditionType, _findType(kBoolType).asResolvedType())) {
          _addError(AnalysisError(
            type: AnalysisErrorType.error,
            message: "Condition type must be '$kBoolType'.",
            node: node.condition,
          ));
        }
        _visit(ifBranch.block);
      }

      if (elseBranch.block case Block block) {
        _visit(block);
      }
    }

    return _findType(kNilType).asResolvedType();
  }

  @override
  ResolvedType visitAnonymousCallExpression(AnonymousCallExpression node) {
    // TODO():
    return _findType(kObjectType).asResolvedType();
  }

  @override
  ResolvedType visitAnonymousCallbackDeclaration(
      AnonymousCallbackDeclaration node) {
    // TODO():
    return _findType(kObjectType).asResolvedType();
  }

  @override
  ResolvedType visitCompilationUnit(CompilationUnit node) {
    node.statements.forEach(_visit);
    return _findType(kUnknownType).asResolvedType();
  }

  @override
  ResolvedType visitElse(ElseStatement node) {
    throw UnimplementedError();
  }

  @override
  ResolvedType visitExpressionStatement(ExpressionStatement node) {
    return _visit(node.expression);
  }

  @override
  ResolvedType visitFor(ForStatement node) {
    _pushScope();
    if (node.initializer case AstNode initializer) {
      _visit(initializer);
    }
    if (node.condition case AstNode condition) {
      final ResolvedType conditionType = _visit(condition);
      if (!_isCompatibleType(
          conditionType, _findType(kBoolType).asResolvedType())) {
        _addError(AnalysisError(
          type: AnalysisErrorType.error,
          message:
              'Expected "$kBoolType" in for condition, instead found "${conditionType.resolvedName}".',
          node: condition,
        ));
      }
    }
    _pushScope();
    _visit(node.block);
    _popScope();
    _popScope();
    return _findType(kVoidType).asResolvedType();
  }

  @override
  ResolvedType visitGetExpression(GetExpression node) {
    final ResolvedType lhs = _visit(node.left);

    if (lhs.type.isUnknownType) {
      return _findType(kUnknownType).asResolvedType();
    }

    if (node.right case Identifier name) {
      if (lhs is ThisExpression) {
        return switch (_currentScope.get('this.${name.name}')) {
          VariableDeclaration varDecl =>
            _resolvedTypeFromAnnotatedType(varDecl.type),
          ConstructorDeclaration constructorDecl =>
            _resolvedTypeFromAnnotatedType(constructorDecl.returnType),
          _ => _findType(kUnknownType).asResolvedType(),
        };
      }

      if (lhs.type is ClassDeclaration) {
        if (_chainSearchField(lhs.type as ClassDeclaration, name.name)
            case VariableDeclaration field) {
          final ResolvedType fieldResolvedType =
              _resolvedTypeFromAnnotatedType(field.type);
          for (var i = 0;
              i < fieldResolvedType.type.typeParameters.length;
              i += 1) {
            _currentScope.set(
                fieldResolvedType.type.typeParameters[i].name.name,
                fieldResolvedType.providedTypeParameters[i]);
          }
          return _resolvedTypeFromAnnotatedType(field.type);
        }
      }

      final Callable? callable =
          _chainSearchMethod(lhs.type as ClassDeclaration, name.name);

      if (callable == null) {
        _addError(AnalysisError(
          type: AnalysisErrorType.error,
          message:
              'Field "${name.name}" does not exist on type "${lhs.resolvedName}".',
          node: name,
        ));
        return _findType(kUnknownType).asResolvedType();
      }

      return _resolvedTypeFromAnnotatedType(callable.returnType);
    }

    return _findType(kUnknownType).asResolvedType();
  }

  @override
  ResolvedType visitGroupExpression(GroupExpression node) {
    return _visit(node.expression);
  }

  @override
  ResolvedType visitIncludeDirective(IncludeDirective node) {
    throw UnimplementedError();
  }

  @override
  ResolvedType visitLiteralNil(LiteralNil node) {
    return _findType(kNilType).asResolvedType();
  }

  @override
  ResolvedType visitSetExpression(SetExpression node) {
    final ResolvedType classType = _visit(node.left);

    if (node.field case Identifier field) {
      if (classType.type is ClassDeclaration) {
        final VariableDeclaration? matchedField =
            _chainSearchField(classType.type as ClassDeclaration, field.name);
        final ResolvedType valueType = _visit(node.value);

        if (matchedField == null) {
          if (!classType.type.isUnknownType) {
            _addError(AnalysisError(
              type: AnalysisErrorType.error,
              message:
                  'Field "${field.name}" is not declared on type "${classType.resolvedName}".',
              node: field,
            ));
          }
          return valueType;
        }

        final ResolvedType matchedFieldResolvedType =
            _resolvedTypeFromAnnotatedType(matchedField.type);
        if (!_isAssignmentCompatibleType(matchedFieldResolvedType, valueType)) {
          _addError(AnalysisError(
            type: AnalysisErrorType.error,
            message:
                'Value of type "${valueType.resolvedName}" is not assignable to type "${matchedFieldResolvedType.resolvedName}".',
            node: node.value,
          ));
        }

        return _resolvedTypeFromAnnotatedType(matchedField.type);
      }
    }

    return classType;
  }

  @override
  ResolvedType visitThisExpression(ThisExpression node) {
    final ClassDeclaration? classDeclaration =
        _currentScope.get<ClassDeclaration?>('this');
    return (classDeclaration ?? _findType(kUnknownType)).asResolvedType();
  }

  @override
  ResolvedType visitType(AnnotatedType node) {
    return ResolvedType(
      type: _findType(node.name.name),
      providedTypeParameters: node.typeParameters
          .map((e) => _findType(e.name.name))
          .cast<TypeDefinition>()
          .toList(growable: false),
    );
  }

  @override
  ResolvedType visitConstructorDeclaration(ConstructorDeclaration node) {
    if (node.block != null) {
      _pushScope();
      for (final Parameter param in node.parameters) {
        _currentScope.set(param.name.lexeme, param);
      }
      _visit(node.block!);

      List<String> initializedFields = <String>[];
      for (AstNode statement in node.block!.statements) {
        if (statement is! SetExpression) {
          continue;
        }

        if (statement.left is ThisExpression) {
          if (statement.field case Identifier field) {
            initializedFields.add(field.name);
          }
        }
      }

      final ClassDeclaration classDeclaration = node.parent as ClassDeclaration;

      for (final field in classDeclaration.fields) {
        if (!initializedFields.contains(field.name.name) &&
            field.initializer == null) {
          _addError(AnalysisError(
            type: AnalysisErrorType.error,
            message:
                'Field "${field.name.name}" is never initialized in constructor',
            node: field.name,
          ));
        }
      }

      _popScope();
    }
    return _resolvedTypeFromAnnotatedType(node.returnType);
  }

  @override
  ResolvedType visitUnaryExpression(UnaryExpression node) {
    return _visit(node.operand);
  }
}

extension on TypeDefinition {
  bool get isUnknownType => name.name == kUnknownType;

  ResolvedType asResolvedType() {
    return ResolvedType(
      type: this,
      providedTypeParameters: const <TypeDefinition>[],
    );
  }
}
