import 'package:moor_generator/src/model/sql_query.dart';
import 'package:moor_generator/src/state/session.dart';
import 'package:moor_generator/src/writer/query_writer.dart';
import 'package:moor_generator/src/writer/result_set_writer.dart';
import 'package:recase/recase.dart';
import 'package:moor_generator/src/model/specified_database.dart';
import 'package:moor_generator/src/writer/table_writer.dart';
import 'utils.dart';

class DatabaseWriter {
  final SpecifiedDatabase db;
  final GeneratorSession session;

  DatabaseWriter(this.db, this.session);

  void write(StringBuffer buffer) {
    // Write referenced tables
    for (final table in db.tables) {
      TableWriter(table, session).writeInto(buffer);
    }

    // Write additional classes to hold the result of custom queries
    for (final query in db.queries) {
      if (query is SqlSelectQuery && query.resultSet.matchingTable == null) {
        ResultSetWriter(query).write(buffer);
      }
    }

    // Write the database class
    final className = '_\$${db.fromClass.name}';
    buffer.write('abstract class $className extends GeneratedDatabase {\n'
        '$className(QueryExecutor e) : super(const SqlTypeSystem.withDefaults(), e); \n');

    final tableGetters = <String>[];

    for (var table in db.tables) {
      tableGetters.add(table.tableFieldName);
      final tableClassName = table.tableInfoName;

      writeMemoizedGetter(
        buffer: buffer,
        getterName: table.tableFieldName,
        returnType: tableClassName,
        code: '$tableClassName(this)',
      );
    }

    // Write fields to access an dao. We use a lazy getter for that.
    for (var dao in db.daos) {
      final typeName = dao.displayName;
      final getterName = ReCase(typeName).camelCase;
      final databaseImplName = db.fromClass.name;

      writeMemoizedGetter(
        buffer: buffer,
        getterName: getterName,
        returnType: typeName,
        code: '$typeName(this as $databaseImplName)',
      );
    }

    // Write implementation for query methods
    final writtenMappingMethods = <String>{};
    for (var query in db.queries) {
      QueryWriter(query, session, writtenMappingMethods).writeInto(buffer);
    }

    final daoGetters = db.daos.map((d) => ReCase(d.displayName).camelCase);
    // Write List of tables, close bracket for class
    final tables = tableGetters;
    tables.addAll(daoGetters.map((d) => '...$d.tables'));

    buffer
      ..write('@override\nList<TableInfo> get allTables => [')
      ..write(tables.join(','))
      ..write('];\n}');
  }
}
