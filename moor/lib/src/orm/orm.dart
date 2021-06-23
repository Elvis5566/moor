
import 'package:moor/moor.dart';

typedef WhereFilter<T extends Table> = Expression<bool?> Function(T table);