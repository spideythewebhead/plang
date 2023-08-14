import 'package:plang/src/ast.dart';
import 'package:plang/src/token.dart';
import 'package:plang/src/token_type.dart';

class ParseResult {
  ParseResult({
    required this.compilationUnit,
    required this.errors,
  });

  final CompilationUnit compilationUnit;
  final List<ParserError> errors;
}

final class PlangParser {
  PlangParser(
    this.tokens, {
    required this.filePath,
  });

  final List<Token> tokens;
  final String filePath;

  int _current = 0;

  ParseResult parse() {
    final List<IncludeDirective> includes = <IncludeDirective>[];
    final List<AstNode> body = <AstNode>[];

    final List<ParserError> errors = <ParserError>[];

    while (_hasMoreToParse()) {
      try {
        final AstNode node = _parseStatement();
        if (node is IncludeDirective) {
          includes.add(node);
        } else {
          body.add(node);
        }
      } on ParserException catch (e) {
        errors.add(ParserError(
          message: e.message,
          token: e.token,
          filePath: e.filePath,
        ));
        _recover();
      }
    }

    return ParseResult(
      compilationUnit: CompilationUnit(
        includes: includes,
        statements: body,
        filePath: filePath,
      ),
      errors: errors,
    );
  }

  void _recover() {
    while (_hasMoreToParse()) {
      if (_peek().type case TokenType.rightBrace) {
        break;
      }
      _advance();
    }
    if (_hasMoreToParse()) {
      _advance();
    }
  }

  AstNode _parseStatement() {
    return switch (_peek().type) {
      TokenType.kval || TokenType.kvar => _parseVariableDeclaration(),
      TokenType.kif => _parseIfStatement(),
      TokenType.fn => _parseFunctionDeclaration(),
      TokenType.kreturn => _parseReturnStatement(),
      TokenType.kfor => _parseForStatement(),
      TokenType.external => _parseExternal(),
      TokenType.kclass => _parseClassStatement(),
      TokenType.kmixin => _parseMixinStatement(),
      TokenType.include => _parseIncludeStatement(),
      _ => _parseExpressionStatement(),
    };
  }

  AstNode _parseExpressionStatement() {
    final AstNode expression = _parseExpression();
    final Token semicolon =
        _expect(TokenType.semicolon, message: 'Expected ";" after expression');
    if (expression is SetExpression) {
      return expression;
    }
    return ExpressionStatement(
      expression.token,
      expression: expression,
      semicolon: semicolon,
    );
  }

  AstNode _parseExternal() {
    if (_peek(offset: 1).type == TokenType.kclass) {
      return _parseClassStatement();
    }
    return _parseFunctionDeclaration();
  }

  AnnotatedType _parseAnnotatedType() {
    final Token name = _expect(TokenType.identifier,
        message: 'Expected identifier after "${_previous().lexeme}".');

    final List<AnnotatedType> typeParameters = <AnnotatedType>[];
    if (_peek().type == TokenType.lt) {
      typeParameters.addAll(_parseTypeParameters());
    }

    return AnnotatedType(
      name: Identifier(name),
      typeParameters: typeParameters,
    );
  }

  List<AnnotatedType> _parseTypeParameters() {
    final List<AnnotatedType> parameterTypes = <AnnotatedType>[];

    if (_match(TokenType.lt)) {
      while (_hasMoreToParse() && _peek().type != TokenType.gt) {
        parameterTypes.add(_parseAnnotatedType());
        _match(TokenType.comma);
      }
      _expect(TokenType.gt, message: 'Expected ">".');
    }

    return parameterTypes;
  }

  VariableDeclaration _parseVariableDeclaration() {
    final Token valOrVar = _advance();
    final Identifier id = Identifier(_expect(
      TokenType.identifier,
      message: 'Expected idenfitifer after "${valOrVar.lexeme}".',
    ));

    final Token colon =
        _expect(TokenType.colon, message: 'Expected type after "${id.name}".');
    final AnnotatedType type = _parseAnnotatedType();

    AstNode? initializer;
    if (_match(TokenType.equal)) {
      initializer = _parseExpression();
    }

    final semicolon = _expect(TokenType.semicolon, message: "Expected ';'.");

    return VariableDeclaration(
      valOrVar,
      name: id,
      colon: colon,
      type: type,
      initializer: initializer,
      semicolon: semicolon,
    );
  }

  IfStatement _parseIfStatement({bool parseBranches = true}) {
    final Token ifKeyword = _advance();
    final Token leftParen = _expect(TokenType.leftParen,
        message: 'Expected "(" after "${ifKeyword.lexeme}".');
    final AstNode condition = _parseExpression();
    final Token rightParen = _expect(TokenType.rightParen,
        message: 'Expected "(" after "${ifKeyword.lexeme}".');
    final Block block = _parseBlock();

    final List<ElseStatement> elseBranches = <ElseStatement>[];

    if (parseBranches) {
      while (_match(TokenType.kelse)) {
        elseBranches.add(_parseElseStatement());
      }
    }

    return IfStatement(
      ifKeyword,
      leftParen: leftParen,
      condition: condition,
      rightParen: rightParen,
      block: block,
      elseBranches: elseBranches,
    );
  }

  ElseStatement _parseElseStatement() {
    final Token elseKeyword = _previous();

    if (_peek().type == TokenType.kif) {
      return ElseStatement(
        elseKeyword,
        ifBranch: _parseIfStatement(parseBranches: false),
      );
    }

    return ElseStatement(
      elseKeyword,
      block: _parseBlock(),
    );
  }

  FunctionDeclaration _parseFunctionDeclaration() {
    Token? externalKeyword;
    if (_match(TokenType.external)) {
      externalKeyword = _previous();
    }

    final Token fnKeyword = _expect(TokenType.fn, message: 'Expected "fun".');
    final Identifier name = Identifier(_expect(TokenType.identifier,
        message: 'Expected identifier after "fun".'));
    final List<AnnotatedType> typeParameters = _parseTypeParameters();
    final Token leftParen =
        _expect(TokenType.leftParen, message: 'Expected "(" after identifier.');

    final List<Parameter> parameters = <Parameter>[];
    while (_hasMoreToParse() && _peek().type != TokenType.rightParen) {
      parameters.add(Parameter(
        name: Identifier(
            _expect(TokenType.identifier, message: 'Expected identifier.')),
        colon: _expect(TokenType.colon, message: 'Expected ":".'),
        type: _parseAnnotatedType(),
      ));
      // this allows trailing comma on parameters
      _match(TokenType.comma);
    }

    final Token rightParen = _expect(TokenType.rightParen,
        message: 'Expected ")" after parameters.');

    final Token colon = _expect(TokenType.colon,
        message: 'Expected ":" after "${rightParen.lexeme}".');
    final AnnotatedType returnType = _parseAnnotatedType();

    Token? semicolon;
    Block? block;

    if (externalKeyword != null) {
      semicolon = _expect(TokenType.semicolon,
          message: 'Expected ";" after "${returnType.name}"');
    } else {
      block = _parseBlock();
    }

    return FunctionDeclaration(
      externalKeyword: externalKeyword,
      fnKeyword: fnKeyword,
      typeParameters: typeParameters,
      name: name,
      leftParen: leftParen,
      parameters: parameters,
      rightParen: rightParen,
      colon: colon,
      returnType: returnType,
      semicolon: semicolon,
      block: block,
    );
  }

  Block _parseBlock() {
    final Token leftBrace =
        _expect(TokenType.leftBrace, message: "Expected '{'.");
    final List<AstNode> statements = <AstNode>[];

    while (_hasMoreToParse() && _peek().type != TokenType.rightBrace) {
      statements.add(_parseStatement());
    }

    final Token rightBrace =
        _expect(TokenType.rightBrace, message: "Expected '}'.");

    return Block(
      leftBrace: leftBrace,
      statements: statements,
      rightBrace: rightBrace,
    );
  }

  IncludeDirective _parseIncludeStatement() {
    return IncludeDirective(
      includeKeyword:
          _expect(TokenType.include, message: 'Expected "include" keyword.'),
      pathLiteral: LiteralString(
          _expect(TokenType.string, message: 'Expected quoted string path.')),
      semicolon: _expect(TokenType.semicolon,
          message: 'Expected ";" after string path.'),
    );
  }

  ReturnStatement _parseReturnStatement() {
    final Token returnKeyword =
        _expect(TokenType.kreturn, message: 'Expected "return".');

    if (_match(TokenType.semicolon)) {
      return ReturnStatement(
        returnKeyword,
        value: null,
        semicolon: _previous(),
      );
    }

    final AstNode value = _peek().type == TokenType.fn
        ? _parseFunctionDeclaration()
        : _parseExpression();
    final Token semicolon =
        _expect(TokenType.semicolon, message: 'Expected ";".');

    return ReturnStatement(
      returnKeyword,
      value: value,
      semicolon: semicolon,
    );
  }

  ForStatement _parseForStatement() {
    final Token forKeyword =
        _expect(TokenType.kfor, message: 'Expected "for".');
    final Token leftParen = _expect(TokenType.leftParen,
        message: 'Expected "(" after "${forKeyword.lexeme}".');

    AstNode? initializer;
    if (_match(TokenType.semicolon)) {
      initializer = null;
    } else if (_peek().type case TokenType.kval || TokenType.kvar) {
      initializer = _parseVariableDeclaration();
    } else {
      initializer = _parseAssignment();
    }

    AstNode? condition;
    if (!_match(TokenType.semicolon)) {
      condition = _parseExpressionStatement();
    }

    AstNode? increment;
    if (_peek().type != TokenType.rightParen) {
      increment = _parseExpression();
    }

    final Token rightParen = _expect(TokenType.rightParen,
        message: 'Expected "(" after "${increment?.lexeme ?? ';'}".');

    final Block block = _parseBlock();

    return ForStatement(
      forKeyword: forKeyword,
      leftParen: leftParen,
      initializer: initializer,
      condition: condition,
      increment: increment,
      rightParen: rightParen,
      block: block,
    );
  }

  ClassDeclaration _parseClassStatement() {
    Token? externalKeyword;
    if (_match(TokenType.external)) {
      externalKeyword = _previous();
    }

    final Token classKeyword =
        _expect(TokenType.kclass, message: 'Expected "class" keyword.');
    final Identifier name = Identifier(_expect(TokenType.identifier,
        message: 'Expected identifier after "class".'));

    final List<AnnotatedType> typeParameters = <AnnotatedType>[];
    if (_peek().type == TokenType.lt) {
      typeParameters.addAll(_parseTypeParameters());
    }

    Token? extendsKeyword;
    Identifier? superType;

    if (_match(TokenType.kextends)) {
      extendsKeyword = _previous();
      superType = Identifier(_expect(TokenType.identifier,
          message: 'Expected identifier after "${extendsKeyword.lexeme}".'));
    }

    Token? withKeyword;
    List<Identifier> mixins = <Identifier>[];

    if (_match(TokenType.kwith)) {
      withKeyword = _previous();

      while (_hasMoreToParse()) {
        mixins.add(Identifier(_expect(
          TokenType.identifier,
          message: 'Expected identifier',
        )));

        if (_peek().type == TokenType.leftBrace) {
          break;
        } else {
          _expect(TokenType.comma, message: "Expected ','.");
        }
      }
    }

    final Token leftBrace = _expect(TokenType.leftBrace,
        message: 'Expected "{" after ${name.name}.');

    final List<VariableDeclaration> fields = <VariableDeclaration>[];
    final List<ConstructorDeclaration> constructors =
        <ConstructorDeclaration>[];
    final List<MethodDeclaration> methods = <MethodDeclaration>[];

    while (_hasMoreToParse() && _peek().type != TokenType.rightBrace) {
      final int offset = _peek().type == TokenType.external ? 1 : 0;
      switch (_peek(offset: offset).type) {
        case TokenType.kval:
        case TokenType.kvar:
          fields.add(_parseVariableDeclaration());
          break;
        case TokenType.identifier:
          if (_peek(offset: offset).lexeme == name.name) {
            constructors.add(_parseConstructorDeclaration());
            break;
          }
          methods.add(_parseMethodDeclaration(name.name));
          break;
        default:
          methods.add(_parseMethodDeclaration(name.name));
          break;
      }
    }

    final Token rightBrace =
        _expect(TokenType.rightBrace, message: "Expected '}'");

    return ClassDeclaration(
      externalKeyword: externalKeyword,
      classKeyword: classKeyword,
      name: name,
      typeParameters: typeParameters,
      extendsKeyword: extendsKeyword,
      superType: superType,
      withKeyword: withKeyword,
      fields: fields,
      mixins: mixins,
      leftBrace: leftBrace,
      constructors: constructors,
      methods: methods,
      rightBrace: rightBrace,
    );
  }

  MixinDeclaration _parseMixinStatement() {
    final Token mixinKeyword =
        _expect(TokenType.kmixin, message: 'Expected "mixin" keyword.');

    final Identifier name = Identifier(_expect(TokenType.identifier,
        message: 'Expected identifier after "mixin".'));

    final List<AnnotatedType> typeParameters = <AnnotatedType>[];
    if (_peek().type == TokenType.lt) {
      typeParameters.addAll(_parseTypeParameters());
    }

    final Token leftBrace = _expect(TokenType.leftBrace,
        message: 'Expected "{" after ${name.name}.');

    final List<MethodDeclaration> methods = <MethodDeclaration>[];
    while (_hasMoreToParse() && _peek().type != TokenType.rightBrace) {
      methods.add(_parseMethodDeclaration(''));
    }

    final Token rightBrace =
        _expect(TokenType.rightBrace, message: "Expected '}'");

    return MixinDeclaration(
      mixinKeyword,
      name: name,
      typeParameters: typeParameters,
      leftBrace: leftBrace,
      methods: methods,
      rightBrace: rightBrace,
    );
  }

  MethodDeclaration _parseMethodDeclaration(String className) {
    Token? externalKeyword;
    if (_match(TokenType.external)) {
      externalKeyword = _previous();
    }

    final Identifier name = Identifier(
        _expect(TokenType.identifier, message: 'Expected indentifier.'));

    final List<AnnotatedType> typeParameters = _parseTypeParameters();

    final Token leftParen = _expect(TokenType.leftParen,
        message: 'Expected "(" after ${name.name}');

    final List<Parameter> parameters = <Parameter>[];
    while (_hasMoreToParse() && _peek().type != TokenType.rightParen) {
      parameters.add(Parameter(
        name: Identifier(
            _expect(TokenType.identifier, message: 'Expected indentifier.')),
        colon:
            _expect(TokenType.colon, message: 'Expected ":" after identifier.'),
        type: _parseAnnotatedType(),
      ));
      _match(TokenType.comma);
    }

    final Token rightParen = _expect(TokenType.rightParen,
        message: 'Expected ")" after ${name.name}');

    final Token colon = _expect(TokenType.colon,
        message: 'Expected ":" after "${rightParen.lexeme}".');

    final AnnotatedType returnType = _parseAnnotatedType();

    Token? semicolon;
    Block? block;

    if (externalKeyword != null) {
      semicolon = _expect(TokenType.semicolon,
          message: 'Expected ";" after "${returnType.name}"');
    } else {
      block = _parseBlock();
    }

    return MethodDeclaration(
      externalKeyword: externalKeyword,
      name: name,
      typeParameters: typeParameters,
      leftParen: leftParen,
      parameters: parameters,
      rightParen: rightParen,
      colon: colon,
      returnType: returnType,
      semicolon: semicolon,
      block: block,
    );
  }

  ConstructorDeclaration _parseConstructorDeclaration() {
    Token? externalKeyword;
    if (_match(TokenType.external)) {
      externalKeyword = _previous();
    }

    final Identifier name = Identifier(
        _expect(TokenType.identifier, message: 'Expected indentifier.'));
    final Token leftParen = _expect(TokenType.leftParen,
        message: 'Expected "(" after ${name.name}');

    final List<Parameter> parameters = <Parameter>[];
    while (_hasMoreToParse() && _peek().type != TokenType.rightParen) {
      parameters.add(Parameter(
        name: Identifier(
            _expect(TokenType.identifier, message: 'Expected indentifier.')),
        colon:
            _expect(TokenType.colon, message: 'Expected ":" after identifier.'),
        type: _parseAnnotatedType(),
      ));
      _match(TokenType.comma);
    }

    final Token rightParen = _expect(TokenType.rightParen,
        message: 'Expected ")" after ${name.name}');

    Token? semicolon;
    Block? block;

    if (externalKeyword != null) {
      semicolon = _expect(TokenType.semicolon,
          message: 'Expected ";" after "${rightParen.lexeme}"');
    } else {
      block = _parseBlock();
    }

    return ConstructorDeclaration(
      externalKeyword: externalKeyword,
      name: name,
      leftParen: leftParen,
      parameters: parameters,
      rightParen: rightParen,
      semicolon: semicolon,
      returnType: AnnotatedType(name: name, typeParameters: []),
      block: block,
    );
  }

  AstNode _parseExpression() {
    return _parseLogicalExpression();
  }

  AstNode _parseLogicalExpression() {
    AstNode leftExpr = _parseEquality();

    while (_match(TokenType.and)) {
      leftExpr = BinaryExpression(
        _previous(),
        left: leftExpr,
        right: _parseEquality(),
      );
    }

    while (_match(TokenType.or)) {
      leftExpr = BinaryExpression(
        _previous(),
        left: leftExpr,
        right: _parseEquality(),
      );
    }

    return leftExpr;
  }

  AstNode _parseEquality() {
    AstNode leftExpr = _parseComparison();

    while (_match(TokenType.equalEqual) || _match(TokenType.bangEqual)) {
      leftExpr = BinaryExpression(
        _previous(),
        left: leftExpr,
        right: _parseComparison(),
      );
    }

    return leftExpr;
  }

  AstNode _parseComparison() {
    AstNode leftExpr = _parseTerm();

    while (_match(TokenType.lt) ||
        _match(TokenType.lte) ||
        _match(TokenType.gt) ||
        _match(TokenType.gte)) {
      leftExpr = BinaryExpression(
        _previous(),
        left: leftExpr,
        right: _parseTerm(),
      );
    }

    return leftExpr;
  }

  AstNode _parseTerm() {
    AstNode leftExpr = _parseFactor();

    while (_match(TokenType.plus) || _match(TokenType.minus)) {
      leftExpr = BinaryExpression(
        _previous(),
        left: leftExpr,
        right: _parseFactor(),
      );
    }

    return leftExpr;
  }

  AstNode _parseFactor() {
    AstNode leftExpr = _parseAssignment();

    while (_match(TokenType.star) || _match(TokenType.slash)) {
      leftExpr = BinaryExpression(
        _previous(),
        left: leftExpr,
        right: _parseAssignment(),
      );
    }

    return leftExpr;
  }

  List<AstNode> _parseCallArguments() {
    final List<AstNode> arguments = <AstNode>[];
    while (_hasMoreToParse() && _peek().type != TokenType.rightParen) {
      if (_peek().type == TokenType.leftBrace) {
        arguments.add(_parseAnonymousCallback());
      } else {
        arguments.add(_parseExpression());
      }
      _match(TokenType.comma);
    }
    return arguments;
  }

  AstNode _parseAssignment() {
    AstNode expr = _parseFunctionCall();

    if (_match(TokenType.plusEqual) ||
        _match(TokenType.minusEqual) ||
        _match(TokenType.starEqual) ||
        _match(TokenType.slashEqual)) {
      if (expr is GetExpression) {
        return SetExpression(
          left: expr.left,
          dot: expr.accessor,
          field: expr.right,
          value: BinaryExpression(
            _previous(),
            left: expr,
            right: _parseExpression(),
          ),
        );
      }
      return AssignmentExpression(
        _previous(),
        left: expr,
        right: BinaryExpression(
          _previous(),
          left: expr,
          right: _parseExpression(),
        ),
      );
    }

    while (_hasMoreToParse() && _match(TokenType.equal)) {
      if (expr is GetExpression) {
        expr = SetExpression(
          left: expr.left,
          dot: expr.accessor,
          field: expr.right,
          value: _parseExpression(),
        );
      } else {
        expr = AssignmentExpression(
          _previous(),
          left: expr,
          right: _parseExpression(),
        );
      }
    }

    return expr;
  }

  AstNode _parseFunctionCall() {
    AstNode expr = _parseUnaryExpression();

    while (_hasMoreToParse()) {
      if (_match(TokenType.leftParen)) {
        final Token leftParen = _previous();
        final List<AstNode> arguments = _parseCallArguments();
        final Token rightParen = _expect(TokenType.rightParen,
            message: 'Expected ")" after arguments.');

        expr = CallExpression(
          callee: expr,
          typeParameters: const <AnnotatedType>[],
          leftParen: leftParen,
          arguments: arguments,
          rightParen: rightParen,
        );
      } else if (_match(TokenType.dot) || _match(TokenType.questionMarkDot)) {
        expr = GetExpression(
          left: expr,
          accessor: _previous(),
          right: _parsePrimary(),
        );
      } else if (expr is GetExpression && _peek().type == TokenType.leftBrace) {
        expr = AnonymousCallExpression(
          callee: expr,
          call: _parseAnonymousCallback(),
        );
      } else if (expr is Identifier && _peek().type == TokenType.leftBrace) {
        expr = AnonymousCallExpression(
          callee: expr,
          call: _parseAnonymousCallback(),
        );
      } else if (_peek().type == TokenType.lt) {
        if (_hasFutureMatch(TokenType.gt, stopAt: TokenType.semicolon)) {
          final List<AnnotatedType> typeParameters = _parseTypeParameters();
          final Token leftParen = _expect(TokenType.leftParen,
              message: 'Expected "(" after "${_previous().lexeme}".');
          final List<AstNode> arguments = _parseCallArguments();
          final Token rightParen = _expect(TokenType.rightParen,
              message: 'Expected ")" after arguments.');

          expr = CallExpression(
            callee: expr,
            typeParameters: typeParameters,
            leftParen: leftParen,
            arguments: arguments,
            rightParen: rightParen,
          );
          continue;
        }
        break;
      } else {
        break;
      }
    }

    return expr;
  }

  AstNode _parseUnaryExpression() {
    if (_hasMoreToParse() && _match(TokenType.bang) ||
        _match(TokenType.minus)) {
      return UnaryExpression(
        operator: _previous(),
        operand: _parseUnaryExpression(),
      );
    }

    return _parsePrimary();
  }

  AstNode _parseGroup() {
    final Token leftParen =
        _expect(TokenType.leftParen, message: 'Expected "(".');
    final AstNode expression = _parseExpression();
    final Token rightParen = _expect(TokenType.rightParen,
        message: 'Expected ")" after expression.');

    return GroupExpression(
      leftParen,
      expression: expression,
      rightParen: rightParen,
    );
  }

  AnonymousCallbackDeclaration _parseAnonymousCallback() {
    final Token leftBrace =
        _expect(TokenType.leftBrace, message: 'Expected "{".');

    Token? arrowToken;
    if (_match(TokenType.minusGreater)) {
      arrowToken = _previous();
    }

    final List<Identifier> parameters = <Identifier>[];

    if (_hasFutureMatch(TokenType.minusGreater, stopAt: TokenType.rightBrace)) {
      while (_hasMoreToParse() && _match(TokenType.identifier)) {
        parameters.add(Identifier(_previous()));
        _match(TokenType.comma); // skip comma
      }
    }

    if (parameters.isNotEmpty) {
      arrowToken = _expect(
        TokenType.minusGreater,
        message: 'Expected "=>" after "${parameters.last.name}".',
      );
    }

    final List<AstNode> statements = <AstNode>[];
    while (_hasMoreToParse() && _peek().type != TokenType.rightBrace) {
      statements.add(_parseStatement());
    }

    final Token rightBrace =
        _expect(TokenType.rightBrace, message: 'Expected "}".');

    return AnonymousCallbackDeclaration(
      leftBrace: leftBrace,
      parameters: parameters,
      arrow: arrowToken,
      statements: statements,
      rightBrace: rightBrace,
    );
  }

  AstNode _parsePrimary() {
    return switch (_peek().type) {
      TokenType.number => LiteralNumber(_advance()),
      TokenType.boolean => LiteralBoolean(_advance()),
      TokenType.string => LiteralString(_advance()),
      TokenType.identifier => Identifier(_advance()),
      TokenType.leftParen when _previous().type != TokenType.dot =>
        _parseGroup(),
      TokenType.nil => LiteralNil(_advance()),
      TokenType.kif => _parseIfStatement(),
      TokenType.kthis => ThisExpression(_advance()),
      _ => throw ParserException(
          message: 'Unexpected token "${_peek().lexeme}".',
          token: _peek(),
          filePath: filePath,
        ),
    };
  }

  Token _peek({int offset = 0}) {
    if (_hasMoreToParse()) {
      return tokens[_current + offset];
    }
    return Token.eof(0, 0, 0);
  }

  bool _hasFutureMatch(
    TokenType type, {
    TokenType? stopAt,
  }) {
    for (var offset = 0; _current + offset < tokens.length; offset += 1) {
      if (_peek(offset: offset).type == type) {
        return true;
      }
      if (_peek(offset: offset).type == stopAt) {
        return false;
      }
    }
    return false;
  }

  Token _advance() {
    _current += 1;
    return tokens[_current - 1];
  }

  bool _match(TokenType type) {
    if (_hasMoreToParse() && _peek().type == type) {
      _advance();
      return true;
    }
    return false;
  }

  Token _expect(TokenType type, {required String message}) {
    if (_match(type)) {
      return _previous();
    }
    throw ParserException(
      message: message,
      token: _previous(),
      filePath: filePath,
    );
  }

  Token _previous() {
    return tokens[_current - 1];
  }

  bool _hasMoreToParse() {
    return _current < tokens.length && tokens[_current].type != TokenType.eof;
  }
}

class ParserException implements Exception {
  ParserException({
    required this.message,
    required this.token,
    required this.filePath,
  });

  final Token token;
  final String message;
  final String filePath;

  @override
  String toString() {
    return '$message Check line ${1 + token.line} and column ${1 + token.column}. $filePath:${1 + token.line}:${1 + token.column}.';
  }
}

class ParserError {
  ParserError({
    required this.message,
    required this.token,
    required this.filePath,
  });

  final Token token;
  final String message;
  final String filePath;

  @override
  String toString() {
    return '$message Check line ${1 + token.line} and column ${1 + token.column}. $filePath:${1 + token.line}:${1 + token.column}.';
  }
}
