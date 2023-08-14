import 'dart:io';

import 'package:plang/src/ast.dart';
import 'package:plang/src/visitor.dart';

class AstPrinter implements RecursiveVisitor<void> {
  String _indent = '';

  void accept(AstNode? node) {
    node?.accept(this);
  }

  void _increaseIndent() {
    _indent += '  ';
  }

  void _decreaseIndent() {
    _indent = _indent.substring(0, _indent.length - 2);
  }

  @override
  void visitBinaryExpression(BinaryExpression node) {
    stdout.writeln('${_indent}BinaryExpression op "${node.lexeme}"');

    _increaseIndent();

    accept(node.left);
    accept(node.right);

    _decreaseIndent();
  }

  @override
  void visitIdentifier(Identifier node) {
    stdout.writeln('${_indent}Identifier ${node.name}');
  }

  @override
  void visitLiteralBoolean(LiteralBoolean node) {
    stdout.writeln('${_indent}LiteralBoolean ${node.value}');
  }

  @override
  void visitLiteralNumber(LiteralNumber node) {
    stdout.writeln('${_indent}LiteralNumber ${node.value}');
  }

  @override
  void visitLiteralString(LiteralString node) {
    stdout.writeln('${_indent}LiteralString ${node.value}');
  }

  @override
  void visitLiteralNil(LiteralNil node) {
    stdout.writeln('${_indent}LiteralNil');
  }

  @override
  void visitGroupExpression(GroupExpression node) {
    stdout.writeln('${_indent}Group');

    _increaseIndent();
    accept(node.expression);
    _decreaseIndent();
  }

  @override
  void visitBlock(Block node) {
    stdout
        .writeln('${_indent}Block ${node.statements.isEmpty ? '<Empty>' : ''}');

    _increaseIndent();

    for (final statement in node.statements) {
      accept(statement);
    }
    _decreaseIndent();
  }

  @override
  void visitVariableDeclaration(VariableDeclaration node) {
    stdout.writeln(
        '$_indent${node.token.lexeme} ${node.name.name} ${node.type.name}');

    if (node.initializer != null) {
      _increaseIndent();

      stdout.writeln('${_indent}Initializer');

      accept(node.initializer!);

      _decreaseIndent();
    }
  }

  @override
  void visitIf(IfStatement node) {
    stdout.writeln('${_indent}If');

    _increaseIndent();

    accept(node.condition);
    accept(node.block);

    _decreaseIndent();

    for (final ElseStatement branch in node.elseBranches) {
      accept(branch);
    }
  }

  @override
  void visitElse(ElseStatement node) {
    stdout.writeln('${_indent}Else');

    _increaseIndent();

    if (node.ifBranch != null) {
      accept(node.ifBranch!);
    } else if (node.block != null) {
      accept(node.block!);
    }

    _decreaseIndent();
  }

  // @override
  // void visitComparisonExpression(ComparisonExpression node) {
  //   stdout.writeln('${_indent}Comparison "${node.lexeme}"');

  //   _increaseIndent();

  //   accept(node.left);
  //   accept(node.right);

  //   _decreaseIndent();
  // }

  @override
  void visitFunctionDeclaration(FunctionDeclaration node) {
    stdout.writeln('${_indent}fn ${node.name.lexeme}');

    _increaseIndent();

    stdout.writeln('${_indent}Parameters');
    _increaseIndent();
    for (final Parameter parameter in node.parameters) {
      accept(parameter);
    }
    _decreaseIndent();

    accept(node.block);

    _decreaseIndent();
  }

  @override
  void visitReturn(ReturnStatement node) {
    stdout.writeln('${_indent}Return ');

    _increaseIndent();

    accept(node.value);

    _decreaseIndent();
  }

  @override
  void visitCallExpression(CallExpression node) {
    if (node.callee is CallExpression) {
      _increaseIndent();
      accept(node.callee);
    }

    stdout.writeln('${_indent}Call');

    _increaseIndent();

    accept(node.callee);

    stdout.writeln('${_indent}Arguments');

    for (final argument in node.arguments) {
      accept(argument);
    }

    if (node.callee is CallExpression) {
      _decreaseIndent();
    }

    _decreaseIndent();
  }

  @override
  void visitExpressionStatement(ExpressionStatement node) {
    accept(node.expression);
  }

  @override
  void visitAssignment(AssignmentExpression node) {
    stdout.writeln('${_indent}Assignment');

    _increaseIndent();

    accept(node.left);
    accept(node.right);

    _decreaseIndent();
  }

  @override
  void visitFor(ForStatement node) {
    stdout.writeln('${_indent}For');

    _increaseIndent();

    accept(node.initializer);
    accept(node.condition);
    accept(node.increment);
    accept(node.block);

    _decreaseIndent();
  }

  @override
  void visitClassDeclaration(ClassDeclaration node) {
    stdout.writeln('${_indent}Class ${node.name.name}');

    _increaseIndent();

    for (final MethodDeclaration method in node.methods) {
      accept(method);
    }

    _decreaseIndent();
  }

  @override
  void visitMethodDeclaration(MethodDeclaration node) {
    stdout.writeln('${_indent}Method ${node.name.lexeme}');

    _increaseIndent();

    stdout.writeln('${_indent}Parameters');
    _increaseIndent();
    for (final Parameter parameter in node.parameters) {
      accept(parameter);
    }
    _decreaseIndent();

    accept(node.block);

    _decreaseIndent();
  }

  @override
  void visitThisExpression(ThisExpression node) {
    stdout.writeln('${_indent}this');
  }

  @override
  void visitGetExpression(GetExpression node) {
    stdout.writeln('${_indent}Get expression');

    _increaseIndent();

    accept(node.left);
    accept(node.right);

    _decreaseIndent();
  }

  @override
  void visitSetExpression(SetExpression node) {
    stdout.writeln('${_indent}Set expression');

    _increaseIndent();

    accept(node.left);
    accept(node.field);

    stdout.writeln('${_indent}Value');
    _increaseIndent();
    accept(node.value);
    _decreaseIndent();

    _decreaseIndent();
  }

  @override
  void visitMixinDeclaration(MixinDeclaration node) {
    stdout.writeln('${_indent}Mixin ${node.name.name}');

    _increaseIndent();

    for (final MethodDeclaration method in node.methods) {
      accept(method);
    }

    _decreaseIndent();
  }

  @override
  void visitIncludeDirective(IncludeDirective node) {
    stdout.writeln('${_indent}Include ${node.pathLiteral.value}');
  }

  @override
  visitCompilationUnit(CompilationUnit node) {
    stdout.writeln('${_indent}Compilation unit ${node.filePath}');

    _increaseIndent();
    node.includes.forEach(accept);
    node.statements.forEach(accept);
    _decreaseIndent();
  }

  @override
  void visitAnonymousCallbackDeclaration(AnonymousCallbackDeclaration node) {
    stdout.writeln('${_indent}Anonymous function');

    _increaseIndent();

    stdout.writeln('${_indent}Parameters');
    _increaseIndent();
    for (final Identifier parameter in node.parameters) {
      accept(parameter);
    }
    _decreaseIndent();

    node.statements.forEach(accept);

    _decreaseIndent();
  }

  @override
  void visitAnonymousCallExpression(AnonymousCallExpression node) {
    stdout.writeln('${_indent}Anonymous call');

    _increaseIndent();

    accept(node.callee);
    accept(node.call);

    _decreaseIndent();
  }

  @override
  void visitType(AnnotatedType node) {}

  @override
  void visitParameter(Parameter node) {
    stdout.writeln('${node.name.lexeme} ${node.type.name}');
  }

  @override
  void visitConstructorDeclaration(ConstructorDeclaration node) {
    stdout.writeln('${_indent}Constructor ${node.name.lexeme}');

    _increaseIndent();

    stdout.writeln('${_indent}Parameters');
    _increaseIndent();
    for (final Parameter parameter in node.parameters) {
      accept(parameter);
    }
    _decreaseIndent();

    accept(node.block);

    _decreaseIndent();
  }

  @override
  void visitUnaryExpression(UnaryExpression node) {
    stdout.writeln('${_indent}Unary ${node.operator.lexeme}');

    _increaseIndent();
    accept(node.operand);
    _decreaseIndent();
  }
}
