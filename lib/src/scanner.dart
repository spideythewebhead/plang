import 'package:plang/src/token.dart';
import 'package:plang/src/token_type.dart';

final Map<String, TokenType> _keywords = <String, TokenType>{
  'true': TokenType.boolean,
  'false': TokenType.boolean,
  'fn': TokenType.fn,
  'class': TokenType.kclass,
  'return': TokenType.kreturn,
  'var': TokenType.kvar,
  'val': TokenType.kval,
  'if': TokenType.kif,
  'else': TokenType.kelse,
  'for': TokenType.kfor,
  'nil': TokenType.nil,
  'this': TokenType.kthis,
  'mixin': TokenType.kmixin,
  'with': TokenType.kwith,
  'include': TokenType.include,
  'external': TokenType.external,
  'extends': TokenType.kextends,
  'and': TokenType.and,
  'or': TokenType.or,
};

class PlangScanner {
  PlangScanner(this.source);

  final String source;

  int _start = 0;
  int _offset = 0;

  int _line = 0;
  int _column = 0;

  List<Token> scan() {
    final tokens = <Token>[];

    while (true) {
      _start = _offset;

      if (_start >= source.length) {
        break;
      }

      switch (_peek()) {
        case String c when c.isDigit():
          tokens.add(_tokenizeNumber());
          break;
        case String c when c.isAlpha():
          tokens.add(_tokenizeIdentifier());
          break;
        case '"' || "'" || '`':
          tokens.add(_tokenizeString());
          break;
        case '\n':
        case '\r\n':
          _advance();
          _line += 1;
          _column = 0;
          break;
        case '+':
          _advance();
          tokens.add(_createToken(
            _match('=') ? TokenType.plusEqual : TokenType.plus,
            lexeme: source.substring(_start, _offset),
          ));
          break;
        case '-':
          _advance();
          if (_match('>')) {
            tokens.add(_createToken(TokenType.minusGreater, lexeme: '->'));
            break;
          }
          tokens.add(_createToken(
            _match('=') ? TokenType.minusEqual : TokenType.minus,
            lexeme: source.substring(_start, _offset),
          ));
          break;
        case '*':
          _advance();
          tokens.add(_createToken(
            _match('=') ? TokenType.starEqual : TokenType.star,
            lexeme: source.substring(_start, _offset),
          ));
          break;
        case '/':
          _advance();

          if (_match('/')) {
            while (_hasMoreToScan() && !_match('\n')) {
              _advance();
            }
            if (_peek(offset: -1) == '\n' ||
                _peek(offset: -2) == '\r' && _peek(offset: -2) == '\n') {
              _line += 1;
              _column = 0;
            }
            break;
          }

          tokens.add(_createToken(
            _match('=') ? TokenType.slashEqual : TokenType.slash,
            lexeme: source.substring(_start, _offset),
          ));
          break;
        case ' ' || '\t':
          _advance();
          break;
        case '(':
          _advance();
          tokens.add(_createToken(
            TokenType.leftParen,
            lexeme: source.substring(_start, _offset),
          ));
          break;
        case ')':
          _advance();
          tokens.add(_createToken(
            TokenType.rightParen,
            lexeme: source.substring(_start, _offset),
          ));
          break;
        case '{':
          _advance();
          tokens.add(_createToken(
            TokenType.leftBrace,
            lexeme: source.substring(_start, _offset),
          ));
          break;
        case '}':
          _advance();
          tokens.add(_createToken(
            TokenType.rightBrace,
            lexeme: source.substring(_start, _offset),
          ));
          break;
        case '.':
          _advance();
          tokens.add(_createToken(
            TokenType.dot,
            lexeme: source.substring(_start, _offset),
          ));
          break;
        case ';':
          _advance();
          tokens.add(_createToken(
            TokenType.semicolon,
            lexeme: source.substring(_start, _offset),
          ));
          break;
        case '=':
          _advance();
          if (_match('=')) {
            tokens.add(_createToken(TokenType.equalEqual, lexeme: '=='));
            break;
          }
          tokens.add(_createToken(TokenType.equal, lexeme: '='));
          break;
        case '!':
          _advance();
          tokens.add(_createToken(
            _match('=') ? TokenType.bangEqual : TokenType.bang,
            lexeme: source.substring(_start, _offset),
          ));
          break;
        case '>':
          _advance();
          tokens.add(_createToken(
            _match('=') ? TokenType.gte : TokenType.gt,
            lexeme: source.substring(_start, _offset),
          ));
          break;
        case '<':
          _advance();
          tokens.add(_createToken(
            _match('=') ? TokenType.lte : TokenType.lt,
            lexeme: source.substring(_start, _offset),
          ));
          break;
        case ',':
          tokens.add(_createToken(TokenType.comma, lexeme: _advance()));
          break;
        case '?':
          _advance();
          if (_match('.')) {
            tokens.add(_createToken(TokenType.questionMarkDot, lexeme: '?.'));
          }
        case ':':
          _advance();
          tokens.add(_createToken(TokenType.colon, lexeme: ':'));
      }
    }

    tokens.add(Token.eof(_line, _start, _column));

    return tokens;
  }

  Token _tokenizeNumber() {
    while (_hasMoreToScan() && _peek().isDigit()) {
      _advance();
    }

    if (_match('.') && _peek().isDigit()) {
      while (_hasMoreToScan() && _peek().isDigit()) {
        _advance();
      }
    }

    final String lexeme = source.substring(_start, _offset);
    return SimpleToken(
      type: TokenType.number,
      lexeme: lexeme,
      offset: _start,
      end: _offset,
      line: _line,
      column: _column,
      literalValue: num.parse(lexeme),
    );
  }

  Token _tokenizeIdentifier() {
    _advance();

    while (_hasMoreToScan() && _peek().isAlphanumeric()) {
      _advance();
    }

    final String lexeme = source.substring(_start, _offset);

    if (_keywords.containsKey(lexeme)) {
      return SimpleToken(
        type: _keywords[lexeme]!,
        lexeme: lexeme,
        offset: _start,
        end: _offset,
        line: _line,
        column: _column,
        isKeyword: true,
      );
    }

    return _createToken(
      TokenType.identifier,
      lexeme: lexeme,
    );
  }

  Token _tokenizeString() {
    final String openingChar = _advance();
    while (_hasMoreToScan() && _peek() != openingChar) {
      // skips \' or \"
      if (_match('\\') && _match(openingChar)) {
        continue;
      }
      if (_match('\n')) {
        _line += 1;
        _column = 0;
        _expect(openingChar, message: 'Expected "$openingChar".');
        continue;
      }
      _advance();
    }

    _expect(openingChar, message: 'Expected "$openingChar".');

    return SimpleToken(
      type: TokenType.string,
      lexeme: source.substring(_start, _offset),
      offset: _start,
      end: _offset,
      line: _line,
      column: _column,
      literalValue: source.substring(
        1 + _start,
        _offset - 1,
      ),
    );
  }

  @pragma('vm:prefer-line')
  Token _createToken(
    TokenType type, {
    String lexeme = '',
  }) {
    return SimpleToken(
      type: type,
      lexeme: lexeme,
      offset: _start,
      end: _offset,
      line: _line,
      column: _column,
    );
  }

  String _peek({int offset = 0}) {
    if (_hasMoreToScan()) {
      return source[_offset + offset];
    }
    return '';
  }

  String _advance() {
    _column += 1;
    _offset += 1;
    return source[_offset - 1];
  }

  bool _match(String c) {
    if (_peek() == c) {
      _advance();
      return true;
    }
    return false;
  }

  String _expect(
    String c, {
    required String message,
  }) {
    if (_match(c)) {
      return source[_offset - 1];
    }

    throw ScannerException(
      message: message,
      line: _line,
      column: _column,
    );
  }

  bool _hasMoreToScan() {
    return _offset < source.length;
  }
}

class ScannerException implements Exception {
  ScannerException({
    required this.message,
    required this.line,
    required this.column,
  });

  final String message;
  final int line;
  final int column;

  @override
  String toString() {
    return '$message Check at line $line and column $column. $line:$column.';
  }
}

extension on String {
  bool isDigit() {
    return codeUnitAt(0) >= 48 && codeUnitAt(0) <= 57;
  }

  bool isAlpha() {
    return (codeUnitAt(0) >= 65 && codeUnitAt(0) <= 90) ||
        (codeUnitAt(0) >= 97 && codeUnitAt(0) <= 122);
  }

  bool isAlphanumeric() {
    return isDigit() || isAlpha();
  }
}
