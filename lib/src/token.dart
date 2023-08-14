import 'package:plang/src/token_type.dart';

abstract base class Token {
  Token();

  TokenType get type;

  String get lexeme;

  int get offset;

  int get end;

  int get line;

  int get column;

  int get length => end - offset;

  factory Token.eof(int line, int offset, int column) => SimpleToken(
        type: TokenType.eof,
        lexeme: '',
        offset: offset,
        end: offset,
        line: line,
        column: column,
      );

  @override
  String toString() {
    return 'Token(type= $type, lexeme= $lexeme, offset= $offset, end= $end, line= $line)';
  }
}

final class SimpleToken extends Token {
  SimpleToken({
    required this.type,
    this.lexeme = '',
    required this.offset,
    required this.end,
    required this.line,
    required this.column,
    this.literalValue,
    this.isKeyword = false,
  });

  @override
  final TokenType type;

  @override
  final String lexeme;

  @override
  final int offset;

  @override
  final int end;

  @override
  final int line;

  @override
  final int column;

  final Object? literalValue;

  final bool isKeyword;

  @override
  String toString() {
    return 'SimpleToken(type= $type, lexeme= $lexeme, offset= $offset, end= $end, line= $line, column= $column, literalValue= $literalValue, isKeyword= $isKeyword)';
  }
}
