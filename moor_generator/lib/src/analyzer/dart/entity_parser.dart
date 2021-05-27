import 'package:analyzer/dart/constant/value.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:analyzer/src/dart/element/inheritance_manager3.dart' show InheritanceManager3;
import 'package:moor/moor.dart';
import 'package:moor/sqlite_keywords.dart';
import 'package:moor_generator/src/analyzer/dart/parser.dart';
import 'package:moor_generator/src/analyzer/errors.dart';
import 'package:moor_generator/src/model/specified_column.dart';
import 'package:moor_generator/src/model/specified_table.dart';
import 'package:moor_generator/src/model/used_type_converter.dart';
import 'package:moor_generator/src/utils/names.dart';
import 'package:recase/recase.dart';
import 'package:source_gen/source_gen.dart';

class EntityParser {
  EntityParser(this.base);

  final MoorDartParser base;
  final isEntityColumnBase = const TypeChecker.fromRuntime(EntityColumnBase);
  final isPrimaryKey = const TypeChecker.fromRuntime(EntityPrimaryKey);
  final isToOne = const TypeChecker.fromRuntime(EntityToOne);
  final isUseDao = const TypeChecker.fromRuntime(UseDao);

  /// If [element] has a `@UseDao` annotation, parses the database model
  /// declared by that class and the referenced tables.
  Future<SpecifiedTable> parse(ClassElement element) async {
    final tableName = _parseTableName(element);
    final dartTableName = ReCase(tableName).pascalCase;

    final columns = await _parseColumns(element);

    final primaryKey = columns.where((c) => c.features.contains(const PrimaryKey())).toSet();

    final table = SpecifiedTable(
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
      overrideDontWriteConstraints: true,
    );

    var index = 0;
    for (var converter in table.converters) {
      converter
        ..index = index++
        ..table = table;
    }

    return table;
  }

  String _parseTableName(ClassElement element) {
    return '${ReCase(element.name).snakeCase}s';
  }

  Future<List<SpecifiedColumn>> _parseColumns(ClassElement element) async {
    // ignore: deprecated_member_use
    final manager = InheritanceManager3();

    final superFields = manager
    // ignore: deprecated_member_use
        .getInheritedConcreteMap2(element)
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

      final column = await _fieldToSpecifiedColumn(field as FieldElement);
      if (column != null) {
        columns[field.name] = column;
      }
    }

    return columns.values.toList();
  }

  Future<SpecifiedColumn> _fieldToSpecifiedColumn(FieldElement field) async {
    final columns = await Future.wait(field.metadata
        .map((ElementAnnotation annotation) => annotation.computeConstantValue())
        .where((DartObject i) => isEntityColumnBase.isAssignableFromType(i.type))
        .map((DartObject i) => _makeSpecifiedColumn(field, i)));

    if (columns.length > 1) {
      base.step.reportError(ErrorInDartCode(affectedElement: field, message: 'Only one EntityColumn annotation is allowed on a Field!'));

      return null;
    }

    if (columns.isEmpty) return null;

    return columns.first;
  }

  Future<SpecifiedColumn> _makeSpecifiedColumn(FieldElement f, DartObject obj) async {
    final columnName = obj.getField('name').toStringValue();
    final isNullable = obj.getField('isNullable').toBoolValue();
    final autoIncrement = obj.getField('auto').toBoolValue();
    final converterType = obj.getField('converter')?.toTypeValue();
    final defaultArgument = obj.getField('defaultValue')?.toStringValue();

    UsedTypeConverter typeConverter;

    if (converterType != null) {
      final typeArguments = (converterType.element as ClassElement).supertype.typeArguments;
      final mappedType = typeArguments.first;
      final sqlType = typeArguments.last;

      typeConverter = UsedTypeConverter(
        converterType: converterType,
        mappedType: mappedType,
        sqlType: _typeToColumnType(sqlType),
      );
    }

//    final unique = obj.getField('uniqueGroup').toStringValue();
//    final length = obj.getField('length').toIntValue();

    final foundFeatures = <ColumnFeature>[];

    SpecifiedColumn referencedColumn;

    if (isPrimaryKey.isExactlyType(obj.type)) {
      foundFeatures.add(const PrimaryKey());
    } else if (isToOne.isExactlyType(obj.type)) {
      final referencedDao = obj.getField('dao')?.toTypeValue().element as ClassElement;

      final ElementAnnotation meta = referencedDao.metadata.firstWhere(
              (m) => isUseDao.isExactlyType(m.computeConstantValue().type),
          orElse: () => null);
      if (meta == null)
        throw Exception("Cannot find or parse `UseDao` annotation!");

      final parsedDao = await base.step.parseDao(referencedDao, ConstantReader(meta.computeConstantValue()));
      final referencedTable = parsedDao.tables.first;
      referencedColumn = parsedDao.tables.first.primaryKey.first;

      foundFeatures.add(ToOne(referencedTable, referencedColumn));
    }

    if (autoIncrement) {
      foundFeatures.add(AutoIncrement());
      // a column declared as auto increment is always a primary key
      foundFeatures.add(const PrimaryKey());
    }

    ColumnType type;

    if (typeConverter != null) {
      type = typeConverter.sqlType;
    } else if (referencedColumn != null) {
      type = referencedColumn.type;
    } else {
      type = _typeToColumnType(f.type);
    }

    return SpecifiedColumn(
      type: type,
      dartGetterName: f.name,
      name: columnName != null ? ColumnName.explicitly(columnName) : ColumnName.implicitly(ReCase(f.name).snakeCase),
//        overriddenJsonName: _readJsonKey(getterElement),
//        customConstraints: foundCustomConstraint,
      nullable: isNullable,
      features: foundFeatures,
//        defaultArgument: foundDefaultExpression?.toSource(),
      typeConverter: typeConverter,
      defaultArgument: defaultArgument,
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
