import 'package:analyzer/dart/element/element.dart';
import 'package:build/build.dart';
import 'package:moor/moor.dart';
import 'package:moor_generator/src/model/specified_column.dart';
import 'package:moor_generator/src/model/specified_table.dart';
import 'package:moor_generator/src/state/generator_state.dart';
import 'package:moor_generator/src/state/options.dart';
import 'package:moor_generator/src/writer/query_writer.dart';
import 'package:moor_generator/src/writer/result_set_writer.dart';
import 'package:moor_generator/src/writer/table_writer.dart';
import 'package:moor_generator/src/writer/utils.dart';
import 'package:source_gen/source_gen.dart';

import 'model/sql_query.dart';

class DaoGenerator extends GeneratorForAnnotation<UseDao> {
  final MoorOptions options;

  DaoGenerator(this.options);

  @override
  generateForAnnotatedElement(Element element, ConstantReader annotation, BuildStep buildStep) async {
    final state = useState(() => GeneratorState(options));
    final session = state.startSession(buildStep);

    if (element is! ClassElement) {
      throw InvalidGenerationSourceError('This annotation can only be used on classes', element: element);
    }

    final targetClass = element as ClassElement;
    final parsedDao = await session.parseDao(targetClass, annotation);

    final dbType = targetClass.supertype;
    if (dbType.name != 'DatabaseAccessor') {
      throw InvalidGenerationSourceError('This class must directly inherit from DatabaseAccessor', element: element);
    }

    // inherits from DatabaseAccessor<T>, we want to know which T
    final dbImpl = dbType.typeArguments.single;
    if (dbImpl.isDynamic) {
      throw InvalidGenerationSourceError(
          'This class must inherit from DatabaseAccessor<T>, where T is an '
          'actual type of a database.',
          element: element);
    }

    // finally, we can write the mixin
    final buffer = StringBuffer();

    final daoName = targetClass.displayName;

    buffer.write('mixin _\$${daoName}Mixin on '
        'DatabaseAccessor<${dbImpl.displayName}> {\n');

    for (var table in parsedDao.tables) {
      final infoType = table.tableInfoName;
      final getterName = table.tableFieldName;
      if (table.fromEntity) {
        writeMemoizedGetter(
          buffer: buffer,
          getterName: getterName,
          returnType: infoType,
          code: '$infoType(db)',
        );

        _writeUpsert(table, buffer);
        _writeLoadAll(table, buffer);
        _writeLoad(table, buffer);
        _writePartialUpdate(table, buffer);

      } else {
        buffer.write('$infoType get $getterName => db.$getterName;\n');
      }
    }

    final tableGetters = parsedDao.tables.map((t) => t.tableFieldName).toList();
    buffer
      ..write('List<TableInfo> get tables => [')
      ..write(tableGetters.join(','))
      ..write('];\n');

    final writtenMappingMethods = <String>{};
    for (var query in parsedDao.queries) {
      QueryWriter(query, session, writtenMappingMethods).writeInto(buffer);
    }

    buffer.write('}');

    // if the queries introduced additional classes, also write those
    for (final query in parsedDao.queries) {
      if (query is SqlSelectQuery && query.resultSet.matchingTable == null) {
        ResultSetWriter(query).write(buffer);
      }
    }

    parsedDao.tables.where((t) => t.fromEntity).forEach((t) => TableWriter(t, session).writeInto(buffer));

    return buffer.toString();
  }

  void _writeUpsert(SpecifiedTable table, StringBuffer buffer) {
    buffer.write('Future upsert(${table.dartTypeName} instance) {\n');
    final toOneColumns = table.columns.where((c) => c.features.any((f) => f is ToOne));

    buffer.write('return transaction((_) async {\n');
    for (final column in toOneColumns) {
      buffer.write('await instance.${column.dartGetterName}?.save();\n');
    }

    buffer.write('await into(${table.tableFieldName}).insert(instance, orReplace: true);\n');

    buffer.write('});\n');
    buffer.write('}\n');
  }

  void _writeLoadAll(SpecifiedTable table, StringBuffer buffer) {
    final tableClassName = table.tableInfoName;

    buffer.write('Future<List<${table.dartTypeName}>> loadAll({Expression<bool, BoolType> where($tableClassName table), '
        'int limit, int offset, List<OrderClauseGenerator<$tableClassName>> orderBy}) {\n');

    buffer.write('final statement = select(${table.tableFieldName});\n');
    buffer.write('if (where != null) {\n');
    buffer.write('statement.where(where);\n');
    buffer.write('}\n');

    buffer.write('if (limit != null) {\n');
    buffer.write('statement.limit(limit, offset: offset);\n');
    buffer.write('}\n');

    buffer.write('if (orderBy != null) {\n');
    buffer.write('statement.orderBy(orderBy);\n');
    buffer.write('}\n');

    buffer.write('final joins = ${table.tableFieldName}.getJoins();\n');

    buffer.write('return joins.length == 0\n');
    buffer.write('? statement.get()\n');
    buffer.write(': statement.join(joins).get().then((rows) {\n');
    buffer.write('return rows.map((row) => row.readTable(${table.tableFieldName})).toList();\n');
    buffer.write('});\n');
    buffer.write('}\n');
  }

  void _writeLoad(SpecifiedTable table, StringBuffer buffer) {
    buffer.write('Future<${table.dartTypeName}> load(key) async {\n');
    buffer.write('final list = await (select(${table.tableFieldName})..where((table) => table.primaryKey.first.equals(key))).get();\n');
    buffer.write('return list.length > 0 ? list.first : null;\n');
    buffer.write('}\n');

  }

  void _writePartialUpdate(SpecifiedTable table, StringBuffer buffer) {
    final tableClassName = table.tableInfoName;

    buffer.write('Future<int> partialUpdate(${tableClassName}Companion companion, {Expression<bool, BoolType> where($tableClassName table)}) {\n');

    buffer.write('final statement = update(${table.tableFieldName});\n');
    buffer.write('if (where != null) {\n');
    buffer.write('statement.where(where);\n');
    buffer.write('}\n');

    buffer.write('return statement.write(companion);\n');

    buffer.write('}\n');
  }
}
