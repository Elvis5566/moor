//@dart=2.9
import 'package:build/build.dart';
import 'package:moor_generator/src/backends/build/moor_builder.dart';
import 'package:moor_generator/src/model/model.dart';
import 'package:moor_generator/src/model/table.dart';
import 'package:moor_generator/src/utils/type_utils.dart';
import 'package:moor_generator/writer.dart';
import 'package:moor_generator/src/writer/queries/query_writer.dart';
import 'package:moor_generator/src/writer/tables/table_writer.dart';
import 'package:moor_generator/src/writer/utils/memoized_getter.dart';
import 'package:source_gen/source_gen.dart';

class DaoGenerator extends Generator implements BaseGenerator {
  @override
  MoorBuilder builder;

  @override
  Future<String> generate(LibraryReader library, BuildStep buildStep) async {
    final parsed = await builder.analyzeDartFile(buildStep);
    final writer =
        builder.createWriter(nnbd: library.element.isNonNullableByDefault);

    for (final dao in parsed.declaredDaos) {
      final classScope = writer.child();
      final element = dao.fromClass;

      final daoName = element.displayName;

      final dbTypeName = dao.dbClass.codeString(writer.generationOptions);
      classScope.leaf().write('mixin _\$${daoName}Mixin on '
          'DatabaseAccessor<$dbTypeName> {\n');

      for (final table in dao.tables) {
        final infoType = table.entityInfoName;
        final getterName = table.dbGetterName;

        if (table.fromEntity) {
          writeMemoizedGetter(
            buffer: classScope.leaf(),
            getterName: getterName,
            returnType: infoType,
            code: '$infoType(db)',
            options: writer.generationOptions,
          );

          _writeUpsert(table, classScope.leaf());
          _writeUpsertAll(table, classScope.leaf());
          _writeLoadAll(table, classScope.leaf());
          _writeLoad(table, classScope.leaf());
          _writePartialUpdate(table, classScope.leaf());

        } else {
          classScope
              .leaf()
              .write('$infoType get $getterName => db.$getterName;\n');
        }
      }

      final tableGetters = dao.tables.map((t) => t.dbGetterName).toList();
      classScope
        .leaf()
        ..write('List<TableInfo> get tables => [')
        ..write(tableGetters.join(','))
        ..write('];\n');

      for (final query in dao.queries) {
        QueryWriter(query, classScope.child()).write();
      }

      classScope.leaf().write('}');

      dao.tables.where((t) => t.fromEntity).forEach((t) => TableWriter(t, writer.child()).writeInto());
    }

    return writer.writeGenerated();
  }

  void _writeUpsert(MoorTable table, StringBuffer buffer) {
    buffer.write('Future upsert(${table.dartTypeName} instance) {\n');
    final toOneColumns = table.columns.where((c) => c.features.any((f) => f is ToOne));

    buffer.write('return transaction(() async {\n');
    for (final column in toOneColumns) {
      buffer.write('await instance.${column.fieldName}${column.nullSign}.save();\n');
    }

    buffer.write('await into(${table.dbGetterName}).insert(instance, mode: InsertMode.insertOrReplace);\n');

    buffer.write('});\n');
    buffer.write('}\n');
  }

  void _writeUpsertAll(MoorTable table, StringBuffer buffer) {
    buffer.write('Future upsertAll(List<${table.dartTypeName}> instances) async {\n');
    final toOneColumns = table.columns.where((c) => c.features.any((f) => f is ToOne));

    for (final column in toOneColumns) {
      final entityType = column.getToOne().referencedTable.entityClass.name;
      final whereNotNull = column.nullable ? '.whereType<$entityType>()' : '';
      buffer.write('await instances.map((instance) => instance.${column.fieldName})$whereNotNull.toList().saveAll();\n');
    }

    buffer.write('await batch((b) => b.insertAll(${table.dbGetterName}, instances, mode: InsertMode.insertOrReplace));\n');

    buffer.write('}\n');
  }

  void _writeLoadAll(MoorTable table, StringBuffer buffer) {
    final tableClassName = table.entityInfoName;

    buffer.write('Future<List<${table.dartTypeName}>> loadAll({WhereFilter<$tableClassName>? where, '
        'int? limit, int? offset, List<OrderClauseGenerator<$tableClassName>>? orderBy}) {\n');

    buffer.write('final statement = select(${table.dbGetterName});\n');
    buffer.write('if (where != null) {\n');
    buffer.write('statement.where(where);\n');
    buffer.write('}\n');

    buffer.write('if (orderBy != null) {\n');
    buffer.write('statement.orderBy(orderBy);\n');
    buffer.write('}\n');

    buffer.write('final joins = ${table.dbGetterName}.getJoins();\n');

    buffer.write('if (joins.length == 0) {\n');
    buffer.write('if (limit != null) {\n');
    buffer.write('statement.limit(limit, offset: offset);\n');
    buffer.write('}\n');
    buffer.write('return statement.get();\n');
    buffer.write('} else {\n');
    buffer.write('final joinedStatement = statement.join(joins);\n');
    buffer.write('if (limit != null) {\n');
    buffer.write('joinedStatement.limit(limit, offset: offset);\n');
    buffer.write('}\n');
    buffer.write('return joinedStatement.get().then((rows) {\n');
    buffer.write('return rows.map((row) => row.readTable(${table.dbGetterName})).toList();\n');
    buffer.write('});\n');
    buffer.write('}\n');

    buffer.write('}\n');
  }

  void _writeLoad(MoorTable table, StringBuffer buffer) {
    buffer.write('Future<${table.dartTypeName}?> load(key) async {\n');
    buffer.write('final statement = select(${table.dbGetterName});\n');
    buffer.write('statement.where((table) => table.primaryKey.first.equals(key));\n');
    buffer.write('final joins = ${table.dbGetterName}.getJoins();\n');
    buffer.write('final list = await (joins.length == 0\n');
    buffer.write('? statement.get()\n');
    buffer.write(': statement.join(joins).get().then((rows) {\n');
    buffer.write('return rows.map((row) => row.readTable(${table.dbGetterName})).toList();\n');
    buffer.write('}));\n');
    buffer.write('return list.length > 0 ? list.first : null;\n');
    buffer.write('}\n');
  }

  void _writePartialUpdate(MoorTable table, StringBuffer buffer) {
    final tableClassName = table.entityInfoName;

    buffer.write('Future<int> partialUpdate(${tableClassName}Companion companion, {WhereFilter<$tableClassName>? where}) {\n');

    buffer.write('final statement = update(${table.dbGetterName});\n');
    buffer.write('if (where != null) {\n');
    buffer.write('statement.where(where);\n');
    buffer.write('}\n');

    buffer.write('return statement.write(companion);\n');

    buffer.write('}\n');
  }
}
