import 'package:plang/src/ast.dart';
import 'package:plang/src/extensions.dart';
import 'package:plang/src/interpreter/interpreter.dart';
import 'package:plang/src/interpreter/runtime/callable.dart';
import 'package:plang/src/interpreter/runtime/class.dart';
import 'package:plang/src/interpreter/runtime/method.dart';
import 'package:plang/src/interpreter/scope.dart';

abstract interface class PlangInstanceBase {
  factory PlangInstanceBase(PlangClass kclass, Scope scope) = PlangInstance;
  factory PlangInstanceBase.list(Scope scope) = PlangListInstance;
  factory PlangInstanceBase.map(Scope scope) = PlangMapInstance;
  factory PlangInstanceBase.string(Scope scope, String value) =
      PlangStringInstance;

  Object? set(String field, Object? value);
  Object? get(String name);
}

class PlangInstance implements PlangInstanceBase {
  PlangInstance(this._class, Scope scope) {
    _scope = Scope(parent: scope);
  }

  final PlangClass _class;
  late final Scope _scope;

  @override
  Object? set(String field, Object? value) {
    return _scope.setWithoutLookup(field, value);
  }

  @override
  Object? get(String name) {
    if (_class.getMethod(name) case MethodDeclaration method) {
      return PlangMethod(
        name: name,
        parentScope: Scope(parent: _scope),
        methodDeclaration: method,
      );
    }
    if (_scope.get(name) case VariableStateGet s) {
      return s;
    }
    return null;
  }

  @override
  String toString() {
    return "Instance '${_class.name}'";
  }
}

class PlangListInstance implements PlangInstanceBase {
  PlangListInstance(Scope parentScope) {
    _scope = Scope(parent: parentScope);
  }

  late final Scope _scope;

  final List<Object?> _internal = <Object?>[];

  @override
  Object? set(String field, Object? value) => null;

  @override
  Object? get(String name) {
    final Scope newScope = Scope(parent: _scope);
    switch (name) {
      case 'elementAt':
        return PlangNativeMethod(
          name: 'elementAt',
          parentScope: newScope,
          arity: 1,
          callback: (runtime, args) =>
              _internal.elementAtOrNull(args[0] as int),
        );
      case 'length':
        return PlangNativeMethod(
          name: 'length',
          parentScope: newScope,
          arity: 0,
          callback: (runtime, args) => _internal.length,
        );
      case 'push':
        return PlangNativeMethod(
          name: 'push',
          parentScope: newScope,
          arity: 1,
          callback: (runtime, args) {
            _internal.add(args[0]);
            Interpreter.returnValue(args[0]);
          },
        );
      case 'setAt':
        return PlangNativeMethod(
          name: 'setAt',
          parentScope: newScope,
          arity: 2,
          callback: (runtime, args) {
            _internal[args[0] as int] = args[1];
            Interpreter.returnValue(args[1]);
          },
        );
      case 'firstWhere':
        return PlangNativeMethod(
          name: 'firstWhere',
          parentScope: newScope,
          arity: 1,
          callback: (Interpreter interpreter, args) {
            return _internal.firstWhereOrNull((Object? element) {
              try {
                (args[0] as PlangCallable).invoke(interpreter, [element]);
              } on InterpreterReturnException catch (e) {
                return interpreter.isTruthy(e.value);
              }
              return false;
            });
          },
        );
      case 'filter':
        return PlangNativeMethod(
          name: 'filter',
          parentScope: newScope,
          arity: 1,
          callback: (Interpreter interpreter, args) {
            final List<Object?> filtered = _internal.where((Object? element) {
              try {
                return interpreter.isTruthy((args[0] as PlangCallable).invoke(
                  interpreter,
                  [1, element],
                ));
              } on InterpreterReturnException catch (e) {
                return interpreter.isTruthy(e.value);
              }
            }).toList(growable: false);

            if (_scope.get('List')
                case VariableStateGet(:final PlangCallable value)) {
              final PlangListInstance instance =
                  value.invoke(interpreter, []) as PlangListInstance;
              instance._internal.addAll(filtered);
              return instance;
            }

            return null;
          },
        );
      case 'map':
        return PlangNativeMethod(
          name: 'map',
          parentScope: newScope,
          arity: 1,
          callback: (Interpreter interpreter, args) {
            final List<Object?> filtered = _internal.map((Object? element) {
              try {
                return (args[0] as PlangCallable)
                    .invoke(interpreter, [1, element]);
              } on InterpreterReturnException catch (e) {
                return e.value;
              }
            }).toList(growable: false);

            if (_scope.get('List')
                case VariableStateGet(:final PlangCallable value)) {
              final PlangListInstance instance =
                  value.invoke(interpreter, []) as PlangListInstance;
              instance._internal.addAll(filtered);
              return instance;
            }

            return null;
          },
        );
    }
    return null;
  }

  @override
  String toString() {
    return _internal.toString();
  }
}

class PlangMapInstance implements PlangInstanceBase {
  PlangMapInstance(Scope parentScope) {
    _scope = Scope(parent: parentScope);
  }

  late final Scope _scope;

  final Map<Object?, Object?> _internal = <Object?, Object?>{};

  @override
  Object? set(String field, Object? value) => null;

  @override
  Object? get(String name) {
    final Scope newScope = Scope(parent: _scope);
    switch (name) {
      case 'set':
        return PlangNativeMethod(
          name: 'set',
          parentScope: newScope,
          arity: 2,
          callback: (runtime, args) => _internal[args[0]] = args[1],
        );
      case 'get':
        return PlangNativeMethod(
          name: 'get',
          parentScope: newScope,
          arity: 1,
          callback: (runtime, args) => _internal[args[0]],
        );
      case 'length':
        return PlangNativeMethod(
          name: 'length',
          parentScope: newScope,
          arity: 0,
          callback: (runtime, args) => _internal.length,
        );
      case 'keys':
        return PlangNativeMethod(
          name: 'keys',
          parentScope: newScope,
          arity: 0,
          callback: (Interpreter interpreter, args) {
            if (_scope.get('List')
                case VariableStateGet(:final PlangCallable value)) {
              final PlangListInstance instance =
                  value.invoke(interpreter, []) as PlangListInstance;
              instance._internal.addAll(_internal.keys);
              return instance;
            }

            return null;
          },
        );
      case 'values':
        return PlangNativeMethod(
          name: 'values',
          parentScope: newScope,
          arity: 0,
          callback: (Interpreter interpreter, args) {
            if (_scope.get('List')
                case VariableStateGet(:final PlangCallable value)) {
              final PlangListInstance instance =
                  value.invoke(interpreter, []) as PlangListInstance;
              instance._internal.addAll(_internal.values);
              return instance;
            }

            return null;
          },
        );
    }
    return null;
  }

  @override
  String toString() {
    return _internal.toString();
  }
}

class PlangStringInstance implements PlangInstanceBase {
  PlangStringInstance(this._scope, this._internal);

  late final Scope _scope;

  final String _internal;

  String get raw => _internal;

  @override
  Object? set(String field, Object? value) => null;

  @override
  Object? get(String name) {
    final Scope newScope = Scope(parent: _scope);
    switch (name) {
      case 'length':
        return PlangNativeMethod(
          name: 'length',
          parentScope: newScope,
          arity: 0,
          callback: (runtime, args) => _internal.length,
        );
      case 'substring':
        return PlangNativeMethod(
          name: 'substring',
          parentScope: newScope,
          arity: 1,
          callback: (Interpreter interpreter, args) {
            if (_scope.get('String')
                case VariableStateGet(:final PlangCallable value)) {
              final PlangStringInstance instance = value.invoke(
                      interpreter, [_internal.substring(args[0] as int)])
                  as PlangStringInstance;

              return instance;
            }

            return null;
          },
        );
      case 'charAt':
        return PlangNativeMethod(
          name: 'charAt',
          parentScope: newScope,
          arity: 1,
          callback: (Interpreter interpreter, args) {
            if (_scope.get('String')
                case VariableStateGet(:final PlangCallable value)) {
              final PlangStringInstance instance =
                  value.invoke(interpreter, [_internal[args[0] as int]])
                      as PlangStringInstance;

              return instance;
            }

            return null;
          },
        );
    }
    return null;
  }

  @override
  int get hashCode => _internal.hashCode;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is PlangStringInstance &&
            runtimeType == other.runtimeType &&
            _internal == other._internal;
  }

  @override
  String toString() {
    return _internal.toString();
  }
}
