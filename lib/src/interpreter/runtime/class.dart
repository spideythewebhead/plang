import 'dart:collection';

import 'package:plang/src/ast.dart';
import 'package:plang/src/extensions.dart';
import 'package:plang/src/interpreter/interpreter.dart';
import 'package:plang/src/interpreter/runtime/callable.dart';
import 'package:plang/src/interpreter/runtime/instance.dart';
import 'package:plang/src/interpreter/scope.dart';
import 'package:plang/src/type_names.dart';

class PlangClass implements PlangCallable {
  PlangClass({
    required this.classDeclaration,
    this.superClassDeclaration,
    required Scope parentScope,
  }) : _parentScope = parentScope;

  final ClassDeclaration classDeclaration;
  final ClassDeclaration? superClassDeclaration;
  final Scope _parentScope;

  String get name => classDeclaration.name.name;

  @override
  int get arity {
    return _ctor?.parameters.length ?? 0;
  }

  @override
  Object? invoke(Interpreter interpreter, List<Object?> args) {
    final Scope instanceScope = Scope(parent: _parentScope);
    final PlangInstanceBase instance = PlangInstanceBase(this, instanceScope);

    instanceScope.declareAndAssign('this', instance);
    instanceScope.declareAndAssign('runtimeType', classDeclaration.name.name);

    for (final field in [
      ...classDeclaration.fields,
      if (superClassDeclaration case ClassDeclaration superClassDecl)
        ...superClassDecl.fields,
    ]) {
      if (field.initializer == null) {
        continue;
      }
      instanceScope.declareAndAssign(field.name.name,
          interpreter.runSingle(instanceScope, field.initializer!));
    }

    if (_ctor case ConstructorDeclaration ctor) {
      final Scope ctorScope = Scope(parent: instanceScope);

      for (var i = 0; i < ctor.parameters.length; i += 1) {
        ctorScope.declareAndAssign(ctor.parameters[i].name.lexeme, args[i]);
      }

      if (superClassDeclaration case ClassDeclaration superClassDeclaration
          when superClassDeclaration.constructors.isNotEmpty) {
        interpreter.runBlock(
            ctorScope, superClassDeclaration.constructors.first.block!);
      }

      interpreter.runBlock(ctorScope, ctor.block!);
    }

    return instance;
  }

  MethodDeclaration? getMethod(String name) {
    MethodDeclaration? method = classDeclaration.methods
        .firstWhereOrNull((element) => element.name.name == name);

    if (method != null) {
      return method;
    }

    final ListQueue<String> superTypes = ListQueue<String>();

    if (classDeclaration.superType != null) {
      superTypes.add(classDeclaration.superType!.name);
    }

    superTypes.addAll(classDeclaration.mixins.map((e) => e.name));

    while (superTypes.isNotEmpty) {
      final String superType = superTypes.removeFirst();

      switch (_parentScope.get(superType)) {
        case TypeDefinition typeDefinition:
          method = typeDefinition.methods
              .firstWhereOrNull((element) => element.name.name == name);

          if (method != null) {
            return method;
          }

          superTypes.addAll(typeDefinition.superTypes);
          break;
      }
    }

    return null;
  }

  ConstructorDeclaration? get _ctor {
    return classDeclaration.constructors.firstOrNull;
  }
}

class PlangNativeClass extends PlangClass {
  PlangNativeClass({
    required super.classDeclaration,
    required super.parentScope,
  });

  @override
  Object? invoke(Interpreter interpreter, List<Object?> args) {
    final Scope instanceScope = Scope(parent: _parentScope);
    late final PlangInstanceBase instance;

    instanceScope.declareAndAssign('runtimeType', classDeclaration.name.name);

    switch (classDeclaration.name.name) {
      case kListType:
        instance = PlangInstanceBase.list(instanceScope);
        break;
      case kMapType:
        instance = PlangInstanceBase.map(instanceScope);
        break;
      case kStringType:
        instance = PlangInstanceBase.string(instanceScope, args[0] as String);
        break;
      default:
        throw Error();
    }

    instanceScope.declareAndAssign('this', instance);

    return instance;
  }
}
