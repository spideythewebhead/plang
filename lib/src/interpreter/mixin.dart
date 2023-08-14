import 'package:plang/src/ast.dart';

class PlangMixin {
  PlangMixin({
    required MixinDeclaration mixinDeclaration,
  }) : _mixinDeclaration = mixinDeclaration;

  final MixinDeclaration _mixinDeclaration;

  List<MethodDeclaration> get methods => _mixinDeclaration.methods;
}
