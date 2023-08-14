enum TokenType {
  eof,
  number,
  boolean,
  string,
  identifier,
  comma,
  nil,

  plus,
  plusEqual,
  minus,
  minusEqual,
  star,
  starEqual,
  slash,
  slashEqual,
  percent,
  percentPlus,

  lt,
  lte,
  gt,
  gte,

  and,
  or,

  equal,
  equalEqual,
  bang,
  bangEqual,
  minusGreater,

  semicolon,
  colon,

  leftParen,
  rightParen,
  leftBrace,
  rightBrace,
  dot,
  questionMarkDot,

  fn,
  kreturn,
  kvar,
  kval,

  kclass,
  kthis,
  kextends,
  kmixin,
  kwith,

  kif,
  kelse,

  kfor,

  include,
  external,
}
