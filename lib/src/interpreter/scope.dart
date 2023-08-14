// enum VariableState {
//   notDefined,
//   alreadyDeclared,
//   declared,
//   updated,
// }

class VariableState {}

class VariableStateNotDefined implements VariableState {
  const VariableStateNotDefined();
}

class VariableStateAlreadyDeclared implements VariableState {
  const VariableStateAlreadyDeclared();
}

class VariableStateDeclared implements VariableState {
  const VariableStateDeclared();
}

class VariableStateUpdated implements VariableState {
  const VariableStateUpdated();
}

class VariableStateGet implements VariableState {
  VariableStateGet(this.value);

  final Object? value;
}

class Scope {
  Scope({Scope? parent}) : _parent = parent;

  final Scope? _parent;
  final Map<String, Object?> _varToValue = <String, Object?>{};

  VariableState declareAndAssign(String name, Object? value) {
    if (declare(name) case VariableStateAlreadyDeclared result) {
      return result;
    }
    return assign(name, value);
  }

  VariableState declare(String name) {
    if (_varToValue.containsKey(name)) {
      return const VariableStateAlreadyDeclared();
    }

    _varToValue[name] = null;
    return const VariableStateDeclared();
  }

  VariableState assign(String name, Object? value) {
    Scope? scope = this;
    while (scope != null && !scope._varToValue.containsKey(name)) {
      scope = scope._parent;
    }

    if (scope != null) {
      scope._varToValue[name] = value;
      return const VariableStateUpdated();
    }

    return const VariableStateNotDefined();
  }

  VariableState setWithoutLookup(String name, Object? value) {
    _varToValue[name] = value;
    return VariableStateGet(value);
  }

  VariableState get(String name) {
    Scope? scope = this;
    while (scope != null) {
      if (scope._varToValue.containsKey(name)) {
        return VariableStateGet(scope._varToValue[name]);
      }
      scope = scope._parent;
    }

    return VariableStateNotDefined();
  }

  // bool _containsVariableInChain(String name) {
  //   Scope? scope = this;
  //   while (scope != null) {
  //     if (scope._varToValue.containsKey(name)) {
  //       return true;
  //     }
  //     scope = scope._parent;
  //   }
  //   return false;
  // }
}
