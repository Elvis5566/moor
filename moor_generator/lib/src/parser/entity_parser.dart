import 'package:analyzer/dart/constant/value.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:analyzer/src/dart/resolver/inheritance_manager.dart' show InheritanceManager;
import 'package:moor/moor.dart';
import 'package:moor/sqlite_keywords.dart';
import 'package:moor_generator/src/model/specified_column.dart';
import 'package:moor_generator/src/model/specified_table.dart';
import 'package:moor_generator/src/state/errors.dart';
import 'package:moor_generator/src/state/session.dart';
import 'package:moor_generator/src/utils/names.dart';
import 'package:recase/recase.dart';
import 'package:source_gen/source_gen.dart';

class EntityParser {
  EntityParser(this.session);

  final GeneratorSession session;
  final isEntityColumnBase = const TypeChecker.fromRuntime(EntityColumnBase);
  final isPrimaryKey = const TypeChecker.fromRuntime(EntityPrimaryKey);

  /// If [element] has a `@UseDao` annotation, parses the database model
  /// declared by that class and the referenced tables.
  Future<SpecifiedTable> parse(ClassElement element) async {
    final tableName = _parseTableName(element);
    final dartTableName = ReCase(tableName).pascalCase;

    final columns = await _parseColumns(element);

    final primaryKey = columns.where((c) => c.features.contains(const PrimaryKey())).toSet();

//    final table = SpecifiedTable(
//      fromClass: element,
//      columns: columns,
//      sqlName: escapeIfNeeded(sqlName),
//      dartTypeName: _readDartTypeName(element),
//      primaryKey: await _readPrimaryKey(element, columns),
//    );

//    var index = 0;
//    for (var converter in table.converters) {
//      converter
//        ..index = index++
//        ..table = table;
//    }

    return SpecifiedTable(
      fromClass: null,
      columns: columns,
      sqlName: escapeIfNeeded(tableName),
      dartTypeName: dataClassNameForClassName(dartTableName),
      overriddenName: ReCase(tableName).pascalCase,
      fromEntity: true,
      primaryKey: primaryKey,
//      overrideWithoutRowId: table.withoutRowId ? true : null,
//      overrideTableConstraints: constraints.isNotEmpty ? constraints : null,
      // we take care of writing the primary key ourselves
//      overrideDontWriteConstraints: true,
    );
  }

  String _parseTableName(ClassElement element) {
    return '${ReCase(element.name).snakeCase}s';
  }

  Future<List<SpecifiedColumn>> _parseColumns(ClassElement element) async {
    // ignore: deprecated_member_use
    final manager = InheritanceManager(element.library);

    final superFields = manager
        // ignore: deprecated_member_use
        .getMembersInheritedFromClasses(element)
        .values
        .where((e) => e is PropertyAccessorElement)
        .map((e) => (e as PropertyAccessorElement).variable)
        .toList();

    final allFields = [...element.fields, ...superFields];

    final columns = <String, SpecifiedColumn>{};

    for (final field in allFields) {
      if (columns.containsKey(field.name)) continue;

      if (field.displayName == 'hashCode' || field.displayName == 'runtimeType') continue;

      if (field.isStatic) continue;

      final column = _fieldToSpecifiedColumn(field as FieldElement);
      if (column != null) {
        columns[field.name] = column;
        print('gg ${field.name}');
      }
    }

    return columns.values.toList();
  }

  SpecifiedColumn _fieldToSpecifiedColumn(FieldElement field) {
    final columns = field.metadata
        .map((ElementAnnotation annot) => annot.computeConstantValue())
        .where((DartObject i) => isEntityColumnBase.isAssignableFromType(i.type))
        .map((DartObject i) => _makeSpecifiedColumn(field, i))
        .toList();

    if (columns.length > 1) {
      session.errors.add(MoorError(affectedElement: field, message: 'Only one EntityColumn annotation is allowed on a Field!'));

      return null;
    }

    if (columns.isEmpty) return null;

    return columns.first;
  }

  SpecifiedColumn _makeSpecifiedColumn(FieldElement f, DartObject obj) {
    final columnName = obj.getField('name').toStringValue();
    final isNullable = obj.getField('isNullable').toBoolValue();
    final autoIncrement = obj.getField('auto').toBoolValue();
//    final unique = obj.getField('uniqueGroup').toStringValue();
//    final length = obj.getField('length').toIntValue();

    final foundFeatures = <ColumnFeature>[];

    if (isPrimaryKey.isExactlyType(obj.type)) {
      foundFeatures.add(const PrimaryKey());
    }

    if (autoIncrement) {
      foundFeatures.add(AutoIncrement());
      // a column declared as auto increment is always a primary key
      foundFeatures.add(const PrimaryKey());
    }

    return SpecifiedColumn(
      type: _typeToColumnType(f.type),
      dartGetterName: f.name,
      name: columnName != null ? ColumnName.explicitly(columnName) : ColumnName.implicitly(ReCase(f.name).snakeCase),
//        overriddenJsonName: _readJsonKey(getterElement),
//        customConstraints: foundCustomConstraint,
      nullable: isNullable,
      features: foundFeatures,
//        defaultArgument: foundDefaultExpression?.toSource(),
//        typeConverter: converter
    );
  }

  ColumnType _typeToColumnType(DartType type) {
    return const {
      'bool': ColumnType.boolean,
      'String': ColumnType.text,
      'int': ColumnType.integer,
      'double': ColumnType.real,
      'DateTime': ColumnType.datetime,
      'Uint8List': ColumnType.blob,
    }[type.name];
  }
}
