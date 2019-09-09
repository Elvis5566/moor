import 'package:moor/moor.dart';
import 'package:moor/src/runtime/components/join.dart';
import 'package:moor/src/runtime/expressions/variables.dart';

/// Base class for generated classes. [TableDsl] is the type specified by the
/// user that extends [Table], [D] is the type of the data class
/// generated from the table.
mixin TableInfo<TableDsl extends Table, D extends DataClass> on Table {
  /// Type system sugar. Implementations are likely to inherit from both
  /// [TableInfo] and [TableDsl] and can thus just return their instance.
  TableDsl get asDslTable;

  /// The primary key of this table. Can be null or empty if no custom primary
  /// key has been specified.
  Set<GeneratedColumn> get $primaryKey => null;

  // The "primaryKey" is what users define on their table classes, the
  // "$primaryKey" is what moor generates in the implementation table info
  // classes. Having two of them is pretty pointless, we're going to remove
  // the "$primaryKey$ getter in Moor 2.0. Until then, let's make sure they're
  // consistent for classes from CREATE TABLE statements, where the info class
  // and the table class is the same thing but primaryKey isn't overriden.
  @override
  Set<Column> get primaryKey => $primaryKey;

  /// The table name in the sql table. This can be an alias for the actual table
  /// name. See [actualTableName] for a table name that is not aliased.
  String get $tableName;

  /// The name of the table in the database. Unless [$tableName], this can not
  /// be aliased.
  String get actualTableName;

  /// The table name, optionally suffixed with the alias if one exists. This
  /// can be used in select statements, as it returns something like "users u"
  /// for a table called users that has been aliased as "u".
  String get tableWithAlias {
    if ($tableName == actualTableName) {
      return actualTableName;
    } else {
      return '$actualTableName ${$tableName}';
    }
  }

  List<GeneratedColumn> get $columns;

  /// Validates that the given entity can be inserted into this table, meaning
  /// that it respects all constraints (nullability, text length, etc.).
  VerificationContext validateIntegrity(covariant UpdateCompanion<D> instance,
      {bool isInserting = false});

  /// Maps the given update companion to a [Map] that can be inserted into sql.
  /// The keys should represent the column name in sql, the values the
  /// corresponding values of the field. All fields of the [instance] which are
  /// present will be written, absent fields will be omitted.
  Map<String, Variable> entityToSql(covariant UpdateCompanion<D> instance);

  /// Maps the given row returned by the database into the fitting data class.
  D map(Map<String, dynamic> data, {String tablePrefix});

  TableInfo<TableDsl, D> createAlias(String alias);

  List<Join> getJoins() {
    List<Join> joins = [];
    final joinInfo = buildJoinInfo();

    joins.addAll(joinInfo.keys.map((column) {
      final table = joinInfo[column];
      return leftOuterJoin(table, column.equalsExp(table.primaryKey.first));
    }));

    joins.addAll(joinInfo.values.expand((table) => table.getJoins()));

    return joins;
  }

  Map<GeneratedColumn, TableInfo> buildJoinInfo() => {};

  @override
  bool operator ==(other) {
    // tables are singleton instances except for aliases
    if (other is TableInfo) {
      return other.runtimeType == runtimeType && other.$tableName == $tableName;
    }
    return false;
  }

  @override
  int get hashCode => $mrjf($mrjc(runtimeType.hashCode, $tableName.hashCode));
}
