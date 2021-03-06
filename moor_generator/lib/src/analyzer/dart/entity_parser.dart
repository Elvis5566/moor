//@dart=2.9
import 'package:analyzer/dart/constant/value.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/nullability_suffix.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:analyzer/src/dart/element/inheritance_manager3.dart'
    show InheritanceManager3;
import 'package:moor/moor.dart';
import 'package:moor/sqlite_keywords.dart';
import 'package:moor_generator/src/analyzer/dart/parser.dart';
import 'package:moor_generator/src/analyzer/errors.dart';
import 'package:moor_generator/src/model/column.dart';
import 'package:moor_generator/src/model/declarations/declaration.dart';
import 'package:moor_generator/src/model/table.dart';
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
  Future<MoorTable> parse(ClassElement element) async {
    final tableName = _parseTableName(element);
    final dartTableName = ReCase(tableName).pascalCase;

    final columns = await _parseColumns(element);

    final primaryKey =
        columns.where((c) => c.features.contains(const PrimaryKey())).toSet();

    final table = MoorTable(
      entityClass: element,
      fromClass: null,
      columns: columns,
      sqlName: escapeIfNeeded(tableName),
      dartTypeName: dataClassNameForClassName(dartTableName),
      overriddenName: ReCase(tableName).pascalCase,
      primaryKey: primaryKey,
      declaration: DartTableDeclaration(element, base.step.file),
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

  Future<List<MoorColumn>> _parseColumns(ClassElement element) async {
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

    final columns = <String, MoorColumn>{};

    for (final field in allFields) {
      if (columns.containsKey(field.name)) continue;

      if (field.displayName == 'hashCode' || field.displayName == 'runtimeType')
        continue;

      if (field.isStatic) continue;

      final column = await _fieldToMoorColumn(field as FieldElement);
      if (column != null) {
        columns[field.name] = column;
      }
    }

    return columns.values.toList();
  }

  Future<MoorColumn> _fieldToMoorColumn(FieldElement field) async {
    final columns = await Future.wait(field.metadata
        .map(
            (ElementAnnotation annotation) => annotation.computeConstantValue())
        .where(
            (DartObject i) => isEntityColumnBase.isAssignableFromType(i.type))
        .map((DartObject i) => _makeMoorColumn(field, i)));

    if (columns.length > 1) {
      base.step.reportError(ErrorInDartCode(
          affectedElement: field,
          message: 'Only one EntityColumn annotation is allowed on a Field!'));

      return null;
    }

    if (columns.isEmpty) return null;

    return columns.first;
  }

  Future<MoorColumn> _makeMoorColumn(FieldElement f, DartObject obj) async {
    final columnName = obj.getField('name').toStringValue();
    // final isNullable = obj.getField('isNullable').toBoolValue();
    final autoIncrement = obj.getField('auto').toBoolValue();
    final converterType = obj.getField('converter')?.toTypeValue();
    final defaultArgument = obj.getField('defaultValue')?.toStringValue();

    UsedTypeConverter typeConverter;

    if (converterType != null) {
      final typeArguments =
          (converterType.element as ClassElement).supertype.typeArguments;
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

    MoorColumn referencedColumn;

    var suffix = '';

    if (isPrimaryKey.isExactlyType(obj.type)) {
      foundFeatures.add(const PrimaryKey());
    } else if (isToOne.isExactlyType(obj.type)) {
      final referencedTable = await base.step.parseEntity(f.type);
      referencedColumn = referencedTable.primaryKey.first;
      foundFeatures.add(ToOne(referencedTable, referencedColumn, f.name));
      suffix = 'Id';
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

    final dartGetterName = f.name + suffix;

    return MoorColumn(
      type: type,
      dartGetterName: dartGetterName,
      name: columnName != null
          ? ColumnName.explicitly(columnName)
          : ColumnName.implicitly(ReCase(dartGetterName).snakeCase),
//        overriddenJsonName: _readJsonKey(getterElement),
//        customConstraints: foundCustomConstraint,
//       nullable: isNullable,
      nullable: f.type.nullabilitySuffix == NullabilitySuffix.question,
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
