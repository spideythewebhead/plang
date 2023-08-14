import 'package:plang/src/ast.dart';

abstract interface class RecursiveVisitor<R> {
  R visitLiteralNumber(LiteralNumber node);
  R visitLiteralBoolean(LiteralBoolean node);
  R visitLiteralString(LiteralString node);
  R visitIdentifier(Identifier node);
  R visitLiteralNil(LiteralNil node);

  R visitGroupExpression(GroupExpression node);
  R visitBinaryExpression(BinaryExpression node);

  R visitBlock(Block node);

  R visitVariableDeclaration(VariableDeclaration node);

  R visitAssignment(AssignmentExpression node);

  R visitIf(IfStatement node);
  R visitElse(ElseStatement node);

  R visitFunctionDeclaration(FunctionDeclaration node);

  R visitReturn(ReturnStatement node);

  R visitCallExpression(CallExpression node);

  R visitExpressionStatement(ExpressionStatement node);

  R visitFor(ForStatement node);

  R visitClassDeclaration(ClassDeclaration node);

  R visitThisExpression(ThisExpression node);

  R visitMethodDeclaration(MethodDeclaration node);

  R visitGetExpression(GetExpression node);

  R visitSetExpression(SetExpression node);

  R visitMixinDeclaration(MixinDeclaration node);

  R visitIncludeDirective(IncludeDirective node);

  R visitCompilationUnit(CompilationUnit node);

  R visitAnonymousCallbackDeclaration(AnonymousCallbackDeclaration node);

  R visitAnonymousCallExpression(AnonymousCallExpression node);

  R visitType(AnnotatedType node);

  R visitParameter(Parameter node);

  R visitConstructorDeclaration(ConstructorDeclaration node);

  R visitUnaryExpression(UnaryExpression node);
}
