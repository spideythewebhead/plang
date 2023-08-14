import 'package:plang/src/ast.dart';
import 'package:plang/src/token.dart';
import 'package:plang/src/visitor.dart';

typedef _Token = String;
typedef _Modifier = String;

class _TokenType {
  static _Token keyword = 'keyword';
  static _Token kclass = 'class';
  static _Token function = 'function';
  static _Token method = 'method';
  static _Token variable = 'variable';
  static _Token string = 'string';
  static _Token number = 'number';
  static _Token operator = 'operator';
  static _Token parameter = 'parameter';
  static _Token other = 'other';
}

class _TokenModifier {
  static _Modifier declaration = 'declaration';
  static _Modifier definition = 'definition';
  static _Modifier readonly = 'readonly';
}

class SemanticTokensFromUnit implements RecursiveVisitor<void> {
  SemanticTokensFromUnit(this.unit);

  final CompilationUnit unit;

  final List<Map<String, dynamic>> _tokens = <Map<String, dynamic>>[];

  List<Map<String, dynamic>> execute() {
    _visit(unit);
    return List.unmodifiable(_tokens);
  }

  void _visit(AstNode? node) => node?.accept(this);

  void _addToken(
    Token token, {
    required _Token type,
    List<_Modifier>? modifiers,
  }) {
    _tokens.add({
      'length': token.length,
      'offset': token.offset,
      'column': token.column,
      'line': token.line,
      'tokenType': type,
      'tokenModifier': modifiers,
    });
  }

  @override
  void visitAssignment(AssignmentExpression node) {
    _visit(node.left);
    _visit(node.right);
  }

  @override
  void visitBinaryExpression(BinaryExpression node) {
    _visit(node.left);
    _addToken(node.token, type: _TokenType.operator);
    _visit(node.right);
  }

  @override
  void visitBlock(Block node) {
    node.statements.forEach(_visit);
  }

  @override
  void visitCallExpression(CallExpression node) {
    if (node.callee case Identifier callee) {
      _addToken(callee.token, type: _TokenType.function);
    } else {
      _visit(node.callee);
    }
    node.arguments.forEach(_visit);
  }

  @override
  void visitClassDeclaration(ClassDeclaration node) {
    if (node.externalKeyword != null) {
      _addToken(node.externalKeyword!, type: _TokenType.keyword);
    }
    _addToken(node.classKeyword, type: _TokenType.keyword);

    _addToken(node.name.token,
        type: _TokenType.kclass, modifiers: [_TokenModifier.definition]);

    if (node.withKeyword case Token withKeyword) {
      _addToken(withKeyword, type: _TokenType.keyword);
    }

    for (var mixin in node.mixins) {
      _addToken(mixin.token, type: _TokenType.kclass);
    }

    node.methods.forEach(_visit);
  }

  @override
  void visitCompilationUnit(CompilationUnit node) {
    node.includes.forEach(_visit);
    node.statements.forEach(_visit);
  }

  @override
  void visitElse(ElseStatement node) {}

  @override
  void visitExpressionStatement(ExpressionStatement node) {
    _visit(node.expression);
  }

  @override
  void visitFor(ForStatement node) {
    _addToken(node.forKeyword, type: _TokenType.keyword);
    _visit(node.initializer);
    _visit(node.condition);
    _visit(node.increment);
    _visit(node.block);
  }

  @override
  void visitFunctionDeclaration(FunctionDeclaration node) {
    _addToken(node.fnKeyword, type: _TokenType.keyword);
    _addToken(node.name.token,
        type: _TokenType.function, modifiers: [_TokenModifier.definition]);

    for (final param in node.parameters) {
      _addToken(param.token, type: _TokenType.parameter);
    }

    _visit(node.block);
  }

  @override
  void visitGetExpression(GetExpression node) {
    _visit(node.left);
    _addToken(node.accessor, type: _TokenType.operator);
    _visit(node.right);
  }

  @override
  void visitGroupExpression(GroupExpression node) {
    _visit(node.expression);
  }

  @override
  void visitIdentifier(Identifier node) {
    final methodOrFunctionParent = node.getParentNode((parent) {
      return switch (parent) {
        MethodDeclaration() || FunctionDeclaration() => true,
        _ => false,
      };
    });

    final params = switch (methodOrFunctionParent) {
      MethodDeclaration() => methodOrFunctionParent.parameters,
      FunctionDeclaration() => methodOrFunctionParent.parameters,
      _ => const <Identifier>[],
    };

    if (params.any((element) => element.lexeme == node.name)) {
      _addToken(node.token, type: _TokenType.parameter);
    } else {
      _addToken(node.token, type: _TokenType.other);
    }
  }

  @override
  void visitIf(IfStatement node) {
    _addToken(node.token, type: _TokenType.keyword);
    _visit(node.condition);
    _visit(node.block);

    for (final elseBranch in node.elseBranches) {
      _addToken(elseBranch.token, type: _TokenType.keyword);
      if (elseBranch.ifBranch case IfStatement ifStatement) {
        _addToken(ifStatement.token, type: _TokenType.keyword);
        _visit(ifStatement.condition);
        _visit(ifStatement.block);
      }
      _visit(elseBranch.block);
    }
  }

  @override
  void visitIncludeDirective(IncludeDirective node) {
    _addToken(node.includeKeyword, type: _TokenType.keyword);
    _visit(node.pathLiteral);
  }

  @override
  void visitLiteralBoolean(LiteralBoolean node) {
    _addToken(node.token, type: _TokenType.keyword);
  }

  @override
  void visitLiteralNil(LiteralNil node) {
    _addToken(node.token, type: _TokenType.keyword);
  }

  @override
  void visitLiteralNumber(LiteralNumber node) {
    _addToken(node.token, type: _TokenType.number);
  }

  @override
  void visitLiteralString(LiteralString node) {
    _addToken(node.token, type: _TokenType.string);
  }

  @override
  void visitMethodDeclaration(MethodDeclaration node) {
    if (node.externalKeyword != null) {
      _addToken(node.externalKeyword!, type: _TokenType.keyword);
    }

    _addToken(node.name.token,
        type: _TokenType.method, modifiers: [_TokenModifier.definition]);
    for (final Parameter param in node.parameters) {
      _addToken(param.token, type: _TokenType.parameter);
    }
    _visit(node.block);
  }

  @override
  void visitMixinDeclaration(MixinDeclaration node) {
    _addToken(node.mixinKeyword, type: _TokenType.keyword);
    _addToken(node.name.token, type: _TokenType.kclass);
    node.methods.forEach(_visit);
  }

  @override
  void visitReturn(ReturnStatement node) {
    _addToken(node.token, type: _TokenType.keyword);
    _visit(node.value);
  }

  @override
  void visitSetExpression(SetExpression node) {
    _visit(node.left);
    _addToken(node.dot, type: _TokenType.operator);
    _visit(node.field);
    _visit(node.value);
  }

  @override
  void visitThisExpression(ThisExpression node) {
    _addToken(node.token, type: _TokenType.keyword);
  }

  @override
  void visitVariableDeclaration(VariableDeclaration node) {
    _addToken(node.token, type: _TokenType.keyword);
    _addToken(node.name.token, type: _TokenType.variable, modifiers: [
      _TokenModifier.declaration,
      if (node.isImmutable) _TokenModifier.readonly
    ]);
    _visit(node.initializer);
  }

  @override
  void visitAnonymousCallbackDeclaration(AnonymousCallbackDeclaration node) {
    if (node.arrow != null) {
      _addToken(node.arrow!, type: _TokenType.operator);
    }
    node.parameters.forEach(_visit);
  }

  @override
  void visitAnonymousCallExpression(AnonymousCallExpression node) {
    _visit(node.call);
    _visit(node.callee);
  }

  @override
  void visitType(AnnotatedType node) {}

  @override
  void visitParameter(Parameter node) {}

  @override
  void visitConstructorDeclaration(ConstructorDeclaration node) {}

  @override
  void visitUnaryExpression(UnaryExpression node) {}
}
