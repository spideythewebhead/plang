import 'package:plang/src/extensions.dart';
import 'package:plang/src/token.dart';
import 'package:plang/src/token_type.dart';
import 'package:plang/src/visitor.dart';

@pragma('vm:prefer-inline')
void _attachParent(List<AstNode> nodes, AstNode parent) {
  for (final AstNode node in nodes) {
    node._parent = parent;
  }
}

abstract class AstNode {
  AstNode(this.token);

  AstNode? _parent;

  final Token token;

  String get lexeme => token.lexeme;

  int get offset => token.offset;

  int get length => token.length;

  int get end => offset + length;

  AstNode? get parent => _parent;

  R accept<R>(RecursiveVisitor<R> visitor);

  AstNode? getParentNode(bool Function(AstNode parent) predicate) {
    AstNode? node = this;
    while (node != null) {
      if (predicate(node)) {
        return node;
      }
      node = node._parent;
    }
    return null;
  }

  bool hasParent(bool Function(AstNode parent) predicate) {
    return getParentNode(predicate) != null;
  }

  String get compilationFile {
    if (getParentNode((node) => node is CompilationUnit)
        case CompilationUnit unit) {
      return unit.filePath;
    }
    return '';
  }
}

class CompilationUnit extends AstNode {
  CompilationUnit({
    required this.includes,
    required this.statements,
    required this.filePath,
  }) : super(includes.firstOrNull?.token ??
            statements.firstOrNull?.token ??
            Token.eof(0, 0, 0)) {
    _attachParent(includes, this);
    _attachParent(statements, this);
  }

  final List<IncludeDirective> includes;
  final List<AstNode> statements;

  final String filePath;

  String get resolvedFilePath => filePath.canonicalizedAbsolutePath();

  @override
  R accept<R>(RecursiveVisitor<R> visitor) {
    return visitor.visitCompilationUnit(this);
  }
}

class LiteralNumber extends AstNode {
  LiteralNumber(super.token);

  num get value => (token as SimpleToken).literalValue as num;

  @override
  R accept<R>(RecursiveVisitor<R> visitor) {
    return visitor.visitLiteralNumber(this);
  }
}

class LiteralString extends AstNode {
  LiteralString(super.token);

  String get value => (token as SimpleToken).literalValue as String;

  @override
  R accept<R>(RecursiveVisitor<R> visitor) {
    return visitor.visitLiteralString(this);
  }
}

class LiteralBoolean extends AstNode {
  LiteralBoolean(super.token);

  late final bool value = (token as SimpleToken).lexeme == "true";

  @override
  R accept<R>(RecursiveVisitor<R> visitor) {
    return visitor.visitLiteralBoolean(this);
  }
}

class LiteralNil extends AstNode {
  LiteralNil(super.token);

  final Object? value = null;

  @override
  R accept<R>(RecursiveVisitor<R> visitor) {
    return visitor.visitLiteralNil(this);
  }
}

class Identifier extends AstNode {
  Identifier(super.token);

  String get name => token.lexeme;

  @override
  R accept<R>(RecursiveVisitor<R> visitor) {
    return visitor.visitIdentifier(this);
  }
}

class AnnotatedType extends AstNode {
  AnnotatedType({
    required this.name,
    required this.typeParameters,
  }) : super(name.token) {
    _attachParent(typeParameters, this);
  }

  final Identifier name;
  final List<AnnotatedType> typeParameters;

  @override
  R accept<R>(RecursiveVisitor<R> visitor) {
    return visitor.visitType(this);
  }
}

class ThisExpression extends AstNode {
  ThisExpression(super.token);

  String get name => token.lexeme;

  @override
  R accept<R>(RecursiveVisitor<R> visitor) {
    return visitor.visitThisExpression(this);
  }
}

class BinaryExpression extends AstNode {
  BinaryExpression(
    super.token, {
    required this.left,
    required this.right,
  }) {
    left._parent = this;
    right._parent = this;
  }

  final AstNode left;
  final AstNode right;

  @override
  int get offset => left.offset;

  @override
  int get length => right.end - left.offset;

  @override
  int get end => right.end;

  @override
  String toString() {
    return 'BinaryExpression(left= $left, operator= ${token.lexeme}, right= $right)';
  }

  @override
  R accept<R>(RecursiveVisitor<R> visitor) {
    return visitor.visitBinaryExpression(this);
  }
}

class GroupExpression extends AstNode {
  GroupExpression(
    super.token, {
    required this.expression,
    required this.rightParen,
  }) {
    expression._parent = this;
  }

  final AstNode expression;
  final Token rightParen;

  Token get leftParen => token;

  @override
  R accept<R>(RecursiveVisitor<R> visitor) {
    return visitor.visitGroupExpression(this);
  }
}

class CallExpression extends AstNode {
  CallExpression({
    required this.callee,
    required this.typeParameters,
    required this.leftParen,
    required this.arguments,
    required this.rightParen,
  }) : super(callee.token) {
    callee._parent = this;

    _attachParent(typeParameters, this);
    _attachParent(arguments, this);
  }

  final AstNode callee;
  final List<AnnotatedType> typeParameters;
  final Token leftParen;
  final List<AstNode> arguments;
  final Token rightParen;

  @override
  int get end => rightParen.end;

  @override
  R accept<R>(RecursiveVisitor<R> visitor) {
    return visitor.visitCallExpression(this);
  }
}

class AnonymousCallExpression extends AstNode {
  AnonymousCallExpression({
    required this.callee,
    required this.call,
  }) : super(callee.token) {
    callee._parent = this;
    call._parent = this;
  }

  final AstNode callee;
  final AnonymousCallbackDeclaration call;

  @override
  int get end => call.end;

  @override
  R accept<R>(RecursiveVisitor<R> visitor) {
    return visitor.visitAnonymousCallExpression(this);
  }
}

class AssignmentExpression extends AstNode {
  AssignmentExpression(
    super.token, {
    required this.left,
    required this.right,
  }) {
    left._parent = this;
    right._parent = this;
  }

  final AstNode left;
  final AstNode right;

  Token get equals => token;

  @override
  int get offset => left.offset;

  @override
  int get end => right.end;

  @override
  R accept<R>(RecursiveVisitor<R> visitor) {
    return visitor.visitAssignment(this);
  }
}

class GetExpression extends AstNode {
  GetExpression({
    required this.left,
    required this.accessor,
    required this.right,
  }) : super(left.token) {
    left._parent = this;
    right._parent = this;
  }

  final AstNode left;
  final Token accessor;
  final AstNode right;

  @override
  int get end => right.end;

  @override
  R accept<R>(RecursiveVisitor<R> visitor) {
    return visitor.visitGetExpression(this);
  }
}

class SetExpression extends AstNode {
  SetExpression({
    required this.left,
    required this.dot,
    required this.field,
    required this.value,
  }) : super(left.token) {
    left._parent = this;
    field._parent = this;
    value._parent = this;
  }

  final AstNode left;
  final Token dot;
  final AstNode field;
  final AstNode value;

  @override
  int get end => value.end;

  @override
  R accept<R>(RecursiveVisitor<R> visitor) {
    return visitor.visitSetExpression(this);
  }
}

class ExpressionStatement extends AstNode {
  ExpressionStatement(
    super.token, {
    required this.expression,
    required this.semicolon,
  }) {
    expression._parent = this;
  }

  final AstNode expression;
  final Token semicolon;

  @override
  int get end => semicolon.end;

  @override
  R accept<R>(RecursiveVisitor<R> visitor) {
    return visitor.visitExpressionStatement(this);
  }
}

class Block extends AstNode {
  Block({
    required this.leftBrace,
    required this.statements,
    required this.rightBrace,
  }) : super(leftBrace) {
    _attachParent(statements, this);
  }

  final Token leftBrace;
  final List<AstNode> statements;
  final Token rightBrace;

  @override
  R accept<R>(RecursiveVisitor<R> visitor) {
    return visitor.visitBlock(this);
  }
}

class VariableDeclaration extends AstNode {
  VariableDeclaration(
    super.token, {
    required this.name,
    required this.colon,
    required this.type,
    this.initializer,
    required this.semicolon,
  }) {
    name._parent = this;
    type._parent = this;
    initializer?._parent = this;
  }

  final Identifier name;
  final Token colon;
  final AnnotatedType type;
  final AstNode? initializer;
  final Token semicolon;

  bool get isImmutable => token.type == TokenType.kval;

  @override
  R accept<R>(RecursiveVisitor<R> visitor) {
    return visitor.visitVariableDeclaration(this);
  }
}

class IfStatement extends AstNode {
  IfStatement(
    super.token, {
    required this.leftParen,
    required this.condition,
    required this.rightParen,
    required this.block,
    required this.elseBranches,
  }) {
    condition._parent = this;
    block._parent = this;
    _attachParent(elseBranches, this);
  }

  final Token leftParen;
  final AstNode condition;
  final Token rightParen;
  final Block block;
  final List<ElseStatement> elseBranches;

  @override
  int get end => block.end;

  @override
  R accept<R>(RecursiveVisitor<R> visitor) {
    return visitor.visitIf(this);
  }
}

class ElseStatement extends AstNode {
  ElseStatement(
    super.token, {
    this.ifBranch,
    this.block,
  }) {
    ifBranch?._parent = this;
    block?._parent = this;
  }

  final IfStatement? ifBranch;
  final Block? block;

  @override
  R accept<R>(RecursiveVisitor<R> visitor) {
    return visitor.visitElse(this);
  }
}

abstract class Callable extends AstNode {
  Callable(super.token);

  Identifier get name;
  List<AnnotatedType> get typeParameters;
  List<Parameter> get parameters;
  AnnotatedType get returnType;
}

class FunctionDeclaration extends Callable {
  FunctionDeclaration({
    this.externalKeyword,
    required this.fnKeyword,
    required this.name,
    required this.typeParameters,
    required this.leftParen,
    required this.parameters,
    required this.rightParen,
    required this.colon,
    required this.returnType,
    this.semicolon,
    this.block,
  })  : assert(block == null && semicolon != null ||
            block != null && semicolon == null),
        super(name.token) {
    name._parent = this;

    _attachParent(typeParameters, this);
    _attachParent(parameters, this);

    returnType._parent = this;
    block?._parent = this;
  }

  final Token? externalKeyword;
  final Token fnKeyword;

  @override
  final Identifier name;

  @override
  final List<AnnotatedType> typeParameters;

  final Token leftParen;

  @override
  final List<Parameter> parameters;

  final Token rightParen;
  final Token colon;

  @override
  final AnnotatedType returnType;

  final Token? semicolon;
  final Block? block;

  @override
  int get offset => externalKeyword?.offset ?? fnKeyword.offset;

  @override
  int get end => block?.end ?? semicolon!.end;

  @override
  R accept<R>(RecursiveVisitor<R> visitor) {
    return visitor.visitFunctionDeclaration(this);
  }
}

class Parameter extends AstNode {
  Parameter({
    required this.name,
    required this.colon,
    required this.type,
  }) : super(name.token) {
    name._parent = this;
    type._parent = this;
  }

  final Identifier name;
  final Token colon;
  final AnnotatedType type;

  @override
  R accept<R>(RecursiveVisitor<R> visitor) {
    return visitor.visitParameter(this);
  }
}

class AnonymousCallbackDeclaration extends AstNode {
  AnonymousCallbackDeclaration({
    required this.leftBrace,
    required this.parameters,
    required this.arrow,
    required this.statements,
    required this.rightBrace,
  }) : super(leftBrace) {
    _attachParent(parameters, this);
    _attachParent(statements, this);
  }

  final Token leftBrace;
  final List<Identifier> parameters;
  final Token? arrow;
  final List<AstNode> statements;
  final Token rightBrace;

  @override
  R accept<R>(RecursiveVisitor<R> visitor) {
    return visitor.visitAnonymousCallbackDeclaration(this);
  }
}

class ReturnStatement extends AstNode {
  ReturnStatement(
    super.token, {
    required this.value,
    required this.semicolon,
  }) {
    value?._parent = this;
  }

  final AstNode? value;
  final Token semicolon;

  Token get returnKeyword => token;

  @override
  int get end => semicolon.end;

  @override
  R accept<R>(RecursiveVisitor<R> visitor) {
    return visitor.visitReturn(this);
  }
}

class ForStatement extends AstNode {
  ForStatement({
    required this.forKeyword,
    required this.leftParen,
    required this.initializer,
    required this.condition,
    required this.increment,
    required this.rightParen,
    required this.block,
  }) : super(forKeyword) {
    initializer?._parent = this;
    condition?._parent = this;
    increment?._parent = this;
    block._parent = this;
  }

  final Token forKeyword;
  final Token leftParen;
  final AstNode? initializer;
  final AstNode? condition;
  final AstNode? increment;
  final Token rightParen;
  final Block block;

  @override
  int get end => block.end;

  @override
  R accept<R>(RecursiveVisitor<R> visitor) {
    return visitor.visitFor(this);
  }
}

abstract class TypeDefinition extends AstNode {
  TypeDefinition(super.token);

  Identifier get name;

  List<AnnotatedType> get typeParameters;

  List<MethodDeclaration> get methods;

  List<String> get superTypes;
}

class ClassDeclaration extends TypeDefinition {
  ClassDeclaration({
    this.externalKeyword,
    required this.classKeyword,
    required this.name,
    required this.typeParameters,
    this.extendsKeyword,
    this.superType,
    this.withKeyword,
    required this.fields,
    required this.mixins,
    required this.leftBrace,
    required this.constructors,
    required this.methods,
    required this.rightBrace,
  }) : super(classKeyword) {
    name._parent = this;
    superType?._parent = this;

    _attachParent(typeParameters, this);
    _attachParent(mixins, this);
    _attachParent(constructors, this);
    _attachParent(methods, this);
    _attachParent(fields, this);

    superTypes = [
      if (superType != null) superType!.name,
      for (final mixin in mixins) mixin.name,
    ];
  }

  final Token? externalKeyword;
  final Token classKeyword;

  @override
  final Identifier name;

  @override
  final List<AnnotatedType> typeParameters;

  final Token? extendsKeyword;
  final Identifier? superType;

  final Token? withKeyword;
  final List<Identifier> mixins;

  final List<VariableDeclaration> fields;

  final List<ConstructorDeclaration> constructors;

  @override
  final List<MethodDeclaration> methods;

  final Token leftBrace;

  final Token rightBrace;

  @override
  int get offset => externalKeyword?.offset ?? classKeyword.offset;

  @override
  int get end => rightBrace.end;

  @override
  late final List<String> superTypes;

  @override
  R accept<R>(RecursiveVisitor<R> visitor) {
    return visitor.visitClassDeclaration(this);
  }
}

class ConstructorDeclaration extends Callable {
  ConstructorDeclaration({
    required this.externalKeyword,
    required this.name,
    required this.leftParen,
    required this.parameters,
    required this.rightParen,
    required this.returnType,
    this.block,
    this.semicolon,
  })  : assert(block == null && semicolon != null ||
            block != null && semicolon == null),
        super(name.token) {
    name._parent = this;

    _attachParent(typeParameters, this);
    _attachParent(parameters, this);

    returnType._parent = this;
    block?._parent = this;
  }

  @override
  int get end => semicolon?.end ?? block?.end ?? rightParen.end;

  final Token? externalKeyword;

  @override
  final Identifier name;

  @override
  List<AnnotatedType> get typeParameters => [];

  final Token leftParen;

  @override
  final List<Parameter> parameters;

  final Token rightParen;

  @override
  final AnnotatedType returnType;

  final Block? block;
  final Token? semicolon;

  @override
  R accept<R>(RecursiveVisitor<R> visitor) {
    return visitor.visitConstructorDeclaration(this);
  }
}

class MethodDeclaration extends Callable {
  MethodDeclaration({
    required this.externalKeyword,
    required this.name,
    required this.typeParameters,
    required this.leftParen,
    required this.parameters,
    required this.rightParen,
    required this.colon,
    required this.returnType,
    this.block,
    this.semicolon,
  })  : assert(block == null && semicolon != null ||
            block != null && semicolon == null),
        super(name.token) {
    name._parent = this;

    _attachParent(typeParameters, this);
    _attachParent(parameters, this);

    returnType._parent = this;
    block?._parent = this;
  }

  @override
  int get end => semicolon?.end ?? block?.end ?? rightParen.end;

  final Token? externalKeyword;

  @override
  final Identifier name;

  @override
  final List<AnnotatedType> typeParameters;

  final Token leftParen;

  @override
  final List<Parameter> parameters;

  final Token rightParen;
  final Token colon;

  @override
  final AnnotatedType returnType;

  final Block? block;
  final Token? semicolon;

  @override
  R accept<R>(RecursiveVisitor<R> visitor) {
    return visitor.visitMethodDeclaration(this);
  }
}

class MixinDeclaration extends TypeDefinition {
  MixinDeclaration(
    super.token, {
    required this.name,
    required this.typeParameters,
    required this.leftBrace,
    required this.methods,
    required this.rightBrace,
  }) {
    name._parent = this;
    _attachParent(methods, this);
  }

  @override
  final Identifier name;

  @override
  final List<AnnotatedType> typeParameters;

  final Token leftBrace;

  @override
  final List<MethodDeclaration> methods;

  final Token rightBrace;

  Token get mixinKeyword => token;

  @override
  int get end => rightBrace.end;

  @override
  List<String> get superTypes => List<String>.empty();

  @override
  R accept<R>(RecursiveVisitor<R> visitor) {
    return visitor.visitMixinDeclaration(this);
  }
}

class IncludeDirective extends AstNode {
  IncludeDirective({
    required this.includeKeyword,
    required this.pathLiteral,
    required this.semicolon,
  }) : super(includeKeyword) {
    pathLiteral._parent = this;
  }

  final Token includeKeyword;
  final LiteralString pathLiteral;
  final Token semicolon;

  @override
  int get end => semicolon.end;

  @override
  R accept<R>(RecursiveVisitor<R> visitor) {
    return visitor.visitIncludeDirective(this);
  }
}

class UnaryExpression extends AstNode {
  UnaryExpression({
    required this.operator,
    required this.operand,
  }) : super(operator) {
    operand._parent = this;
  }

  final Token operator;
  final AstNode operand;

  @override
  int get end => operand.end;

  @override
  R accept<R>(RecursiveVisitor<R> visitor) {
    return visitor.visitUnaryExpression(this);
  }
}
