import 'package:plang/src/interpreter/interpreter.dart';

abstract interface class PlangCallable {
  int get arity;

  Object? invoke(
    Interpreter interpreter,
    List<Object?> args,
  );
}
