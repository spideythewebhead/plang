import 'package:plang/src/ast.dart';
import 'package:plang/src/extensions.dart';
import 'package:plang/src/models/analysis_error.dart';
import 'package:plang/src/visitor.dart';
import 'package:plang/src/visitors/type_checking/type_compatibility_analysis.dart';

enum _Pass {
  typeRegistration,
  checkValidityOfType,
  evaluateTypesCompatibility,
}

class BasicTypeCheckingAnalysis implements RecursiveVisitor<void> {
  BasicTypeCheckingAnalysis(this.units);

  final Map<String, CompilationUnit> units;

  final Map<String, TypeDefinition> _knownTypes = <String, TypeDefinition>{};
  final Set<String> _visitedUnits = <String>{};

  final List<AnalysisError> _errors = <AnalysisError>[];

  _Pass _pass = _Pass.typeRegistration;

  List<AnalysisError> analyze(CompilationUnit main) {
    for (final _Pass pass in _Pass.values) {
      _pass = pass;
      _visitedUnits.clear();
      _visit(main);
    }

    final List<AstNode> nodes = [
      for (final CompilationUnit unit in units.values) ...unit.statements,
    ];

    final TypeEnvironment scope = TypeEnvironment();

    for (final CompilationUnit unit in units.values) {
      for (final AstNode statement in unit.statements) {
        switch (statement) {
          case TypeDefinition():
            scope.set(statement.name.name, statement);
            break;
          case VariableDeclaration():
            scope.set(statement.name.name, statement);
            break;
          case FunctionDeclaration():
            scope.set(statement.name.name, statement);
            break;
        }
      }
    }

    _errors.addAll(TypeCompatibilityAnalysis(scope: scope).analyze(nodes));

    return List<AnalysisError>.unmodifiable(_errors);
  }

  void _visit(AstNode? node) => node?.accept(this);

  void _addError(AnalysisError error) => _errors.add(error);

  @override
  void visitAnonymousCallExpression(AnonymousCallExpression node) {}

  @override
  void visitAnonymousCallbackDeclaration(AnonymousCallbackDeclaration node) {}

  @override
  void visitAssignment(AssignmentExpression node) {}

  @override
  void visitBinaryExpression(BinaryExpression node) {}

  @override
  void visitBlock(Block node) {
    for (final AstNode statement in node.statements) {
      _visit(statement);
    }
  }

  @override
  void visitCallExpression(CallExpression node) {}

  @override
  void visitClassDeclaration(ClassDeclaration node) {
    if (_pass == _Pass.typeRegistration) {
      _knownTypes[node.name.lexeme] = node;
      return;
    }

    if (_pass == _Pass.checkValidityOfType) {
      if (node.superType case Identifier superType) {
        if (!_knownTypes.containsKey(superType.name)) {
          _addError(AnalysisError(
            type: AnalysisErrorType.error,
            message:
                'Unknown type "${node.name.name}" as super class. Hint: Check for: \n'
                '  1. Mistype.\n'
                '  2. Undefined type.\n'
                '  3. Or missing "include" statement.\n',
            node: superType,
          ));
        }
      }
      for (final MethodDeclaration method in node.methods) {
        _visit(method);
      }
      for (final VariableDeclaration field in node.fields) {
        _visit(field);
      }
      for (final AnnotatedType typeParam in node.typeParameters) {
        _visit(typeParam);
      }
      return;
    }
  }

  @override
  void visitCompilationUnit(CompilationUnit node) {
    if (_pass != _Pass.evaluateTypesCompatibility) {
      node.includes.forEach(_visit);
      node.statements.forEach(_visit);
      return;
    }
  }

  @override
  void visitElse(ElseStatement node) {}

  @override
  void visitExpressionStatement(ExpressionStatement node) {}

  @override
  void visitFor(ForStatement node) {
    if (_pass == _Pass.checkValidityOfType) {
      _visit(node.initializer);
      _visit(node.increment);
      _visit(node.increment);
      _visit(node.block);
      return;
    }
  }

  @override
  void visitFunctionDeclaration(FunctionDeclaration node) {
    if (_pass == _Pass.checkValidityOfType) {
      for (final Parameter parameter in node.parameters) {
        _visit(parameter);
      }

      for (final AnnotatedType typeParam in node.typeParameters) {
        _visit(typeParam);
      }

      _visit(node.returnType);
      _visit(node.block);
      return;
    }
  }

  @override
  void visitGetExpression(GetExpression node) {}

  @override
  void visitGroupExpression(GroupExpression node) {}

  @override
  void visitIdentifier(Identifier node) {}

  @override
  void visitIf(IfStatement node) {}

  @override
  void visitIncludeDirective(IncludeDirective node) {
    final String filePath = node.pathLiteral.value.canonicalizedAbsolutePath();

    if (_visitedUnits.contains(filePath)) {
      return;
    }

    _visitedUnits.add(filePath);
    _visit(units[filePath]!);
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
    if (_pass == _Pass.checkValidityOfType) {
      for (final Parameter parameter in node.parameters) {
        _visit(parameter);
      }
      for (final AnnotatedType typeParam in node.typeParameters) {
        _visit(typeParam);
      }

      _visit(node.returnType);
      _visit(node.block);

      return;
    }
  }

  @override
  void visitMixinDeclaration(MixinDeclaration node) {
    if (_pass == _Pass.typeRegistration) {
      _knownTypes[node.name.lexeme] = node;
      return;
    }
  }

  @override
  void visitParameter(Parameter node) {
    _visit(node.type);
  }

  @override
  void visitReturn(ReturnStatement node) {}

  @override
  void visitSetExpression(SetExpression node) {}

  @override
  void visitThisExpression(ThisExpression node) {}

  @override
  void visitType(AnnotatedType node) {
    // for (final AnnotatedType typeParam in node.typeParameters) {
    //   _visit(typeParam);
    // }

    // if (!_knownTypes.containsKey(node.name.name)) {
    //   if (node.getParentNode((parent) => parent is TypeDefinition)
    //       case TypeDefinition parent) {
    //     for (final AnnotatedType typeParameter in parent.typeParameters) {
    //       if (typeParameter.name.name == node.name.name) {
    //         return;
    //       }
    //     }
    //   }

    //   _addError(AnalysisError(
    //     type: AnalysisErrorType.error,
    //     message:
    //         'Undefined type "${node.name.name}" provided. Hint: Check for: \n'
    //         '  1. Mistype.\n'
    //         '  2. Undefined type.\n'
    //         '  3. Or missing "include" statement.\n',
    //     node: node,
    //   ));
    // }
  }

  @override
  void visitVariableDeclaration(VariableDeclaration node) {
    if (_pass == _Pass.checkValidityOfType) {
      _visit(node.type);
      return;
    }
  }

  @override
  void visitConstructorDeclaration(ConstructorDeclaration node) {
    if (_pass == _Pass.checkValidityOfType) {
      for (final Parameter parameter in node.parameters) {
        _visit(parameter);
      }

      _visit(node.returnType);
      _visit(node.block);

      return;
    }
  }

  @override
  void visitUnaryExpression(UnaryExpression node) {
    _visit(node.operand);
  }
}
