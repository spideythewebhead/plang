import 'package:path/path.dart';

extension PathX on String {
  String canonicalizedAbsolutePath() {
    return canonicalize(absolute(this));
  }
}

extension CollectionX<T> on List<T> {
  T? firstWhereOrNull(bool Function(T element) test) {
    try {
      return firstWhere(test);
    } catch (_) {
      return null;
    }
  }
}
