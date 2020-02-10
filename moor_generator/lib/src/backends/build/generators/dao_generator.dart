import 'package:build/build.dart';
import 'package:moor_generator/src/backends/build/moor_builder.dart';
import 'package:moor_generator/src/model/specified_column.dart';
import 'package:moor_generator/src/model/specified_table.dart';
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
    final writer = builder.createWriter();

    for (var dao in parsed.declaredDaos) {
      final classScope = writer.child();
      final element = dao.fromClass;

      final daoName = element.displayName;

      classScope.leaf().write('mixin _\$${daoName}Mixin on '
          'DatabaseAccessor<${dao.dbClass.displayName}> {\n');

      for (var table in dao.allTables) {
        final infoType = table.tableInfoName;
        final getterName = table.tableFieldName;
        if (table.fromEntity) {
          writeMemoizedGetter(
            buffer: classScope.leaf(),
            getterName: getterName,
            returnType: infoType,
            code: '$infoType(db)',
          );

          _writeUpsert(table, classScope.leaf());
          _writeLoadAll(table, classScope.leaf());
          _writeLoad(table, classScope.leaf());
          _writePartialUpdate(table, classScope.leaf());

        } else {
          classScope
              .leaf()
              .write('$infoType get $getterName => db.$getterName;\n');
        }
      }

      final tableGetters = dao.tables.map((t) => t.tableFieldName).toList();
      classScope
        .leaf()
        ..write('List<TableInfo> get tables => [')
        ..write(tableGetters.join(','))
        ..write('];\n');

      final writtenMappingMethods = <String>{};
      for (var query in dao.resolvedQueries) {
        QueryWriter(query, classScope.child(), writtenMappingMethods).write();
      }

      classScope.leaf().write('}');

      dao.tables.where((t) => t.fromEntity).forEach((t) => TableWriter(t, writer.child()).writeInto());
    }

    return writer.writeGenerated();
  }

  void _writeUpsert(SpecifiedTable table, StringBuffer buffer) {
    buffer.write('Future upsert(${table.dartTypeName} instance, [Batch _batch]) async {\n');
    final toOneColumns = table.columns.where((c) => c.features.any((f) => f is ToOne));

    buffer.write('if (_batch != null) {\n');
    for (final column in toOneColumns) {
      buffer.write('instance.${column.dartGetterName}?.save(batch: _batch);\n');
    }
    buffer.write('_batch.insert(${table.tableFieldName}, instance, mode: InsertMode.insertOrReplace);\n');
    buffer.write('} else {\n');
    buffer.write('await batch((b) {\n');
    for (final column in toOneColumns) {
      buffer.write('instance.${column.dartGetterName}?.save(batch: b);\n');
    }
    buffer.write('b.insert(${table.tableFieldName}, instance, mode: InsertMode.insertOrReplace);\n');
    buffer.write('});\n');
    buffer.write('}\n');

//    buffer.write('return transaction(() async {\n');
//    for (final column in toOneColumns) {
//      buffer.write('await instance.${column.dartGetterName}?.save();\n');
//    }
//
//    buffer.write('await into(${table.tableFieldName}).insert(instance, orReplace: true);\n');

//    buffer.write('});\n');
    buffer.write('}\n');
  }

  void _writeLoadAll(SpecifiedTable table, StringBuffer buffer) {
    final tableClassName = table.tableInfoName;

    buffer.write('Future<List<${table.dartTypeName}>> loadAll({WhereFilter<$tableClassName> where, '
        'int limit, int offset = 0, List<OrderClauseGenerator<$tableClassName>> orderBy}) {\n');

    buffer.write('final statement = select(${table.tableFieldName});\n');
    buffer.write('if (where != null) {\n');
    buffer.write('statement.where(where);\n');
    buffer.write('}\n');

    buffer.write('if (orderBy != null) {\n');
    buffer.write('statement.orderBy(orderBy);\n');
    buffer.write('}\n');

    buffer.write('final joins = ${table.tableFieldName}.getJoins();\n');

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
    buffer.write('return rows.map((row) => row.readTable(${table.tableFieldName})).toList();\n');
    buffer.write('});\n');
    buffer.write('}\n');

    buffer.write('}\n');
  }

  void _writeLoad(SpecifiedTable table, StringBuffer buffer) {
    buffer.write('Future<${table.dartTypeName}> load(key) async {\n');
    buffer.write('final statement = select(${table.tableFieldName});\n');
    buffer.write('statement.where((table) => table.primaryKey.first.equals(key));\n');
    buffer.write('final joins = ${table.tableFieldName}.getJoins();\n');
    buffer.write('final list = await (joins.length == 0\n');
    buffer.write('? statement.get()\n');
    buffer.write(': statement.join(joins).get().then((rows) {\n');
    buffer.write('return rows.map((row) => row.readTable(${table.tableFieldName})).toList();\n');
    buffer.write('}));\n');
    buffer.write('return list.length > 0 ? list.first : null;\n');
    buffer.write('}\n');
  }

  void _writePartialUpdate(SpecifiedTable table, StringBuffer buffer) {
    final tableClassName = table.tableInfoName;

    buffer.write('Future<int> partialUpdate(${tableClassName}Companion companion, {WhereFilter<$tableClassName> where}) {\n');

    buffer.write('final statement = update(${table.tableFieldName});\n');
    buffer.write('if (where != null) {\n');
    buffer.write('statement.where(where);\n');
    buffer.write('}\n');

    buffer.write('return statement.write(companion);\n');

    buffer.write('}\n');
  }
}
