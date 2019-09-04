import 'package:moor_generator/src/model/specified_table.dart';
import 'package:moor_generator/src/state/session.dart';

class UpdateCompanionWriter {
  final SpecifiedTable table;
  final GeneratorSession session;

  UpdateCompanionWriter(this.table, this.session);

  void writeInto(StringBuffer buffer) {
    if (table.fromEntity) {
      _writeCreateCompanion(buffer);
    }

    buffer.write('class ${table.updateCompanionName} '
        'extends UpdateCompanion<${table.dartTypeName}> {\n');
    _writeFields(buffer);
    _writeConstructor(buffer);
    _writeCopyWith(buffer);

    buffer.write('}\n');
  }

  void _writeFields(StringBuffer buffer) {
    for (var column in table.columns) {
      buffer.write('final Value<${column.dartTypeName}>'
          ' ${column.dartGetterName}${column.suffix};\n');
    }
  }

  void _writeConstructor(StringBuffer buffer) {
    buffer.write('const ${table.updateCompanionName}({');

    for (var column in table.columns) {
      buffer.write('this.${column.dartGetterName}${column.suffix} = const Value.absent(),');
    }

    buffer.write('});\n');
  }

  void _writeCopyWith(StringBuffer buffer) {
    buffer.write('${table.updateCompanionName} copyWith({');
    var first = true;
    for (var column in table.columns) {
      if (!first) {
        buffer.write(', ');
      }
      first = false;
      buffer.write('Value<${column.dartTypeName}> ${column.dartGetterName}${column.suffix}');
    }

    buffer
      ..write('}) {\n') //
      ..write('return ${table.updateCompanionName}(');
    for (var column in table.columns) {
      final name = column.dartGetterName;
      final suffix = column.suffix;
      buffer.write('$name$suffix: $name$suffix ?? this.$name$suffix,');
    }
    buffer.write(');\n}\n');
  }

  void _writeCreateCompanion(StringBuffer buffer) {
    final companionClass = table.updateCompanionName;
    buffer.write('\n');
    buffer.write('$companionClass _\$createCompanion(${table.dartTypeName} instance, bool nullToAbsent) {');
    buffer.write('return $companionClass(');
    for (var column in table.columns) {
      final getter = column.dartGetterName;
      var pKey = '';
      var columnSuffix = '';
      if (column.isToOne()) {
        final toOne = column.getToOne();
        pKey = '.${toOne.referencedColumn.name.name}';
        columnSuffix = toOne.columnSuffix;
      }

      buffer.write('$getter$columnSuffix: instance.$getter == null && nullToAbsent ? '
          'const Value.absent() : Value(instance.$getter$pKey),');
    }
    buffer.write(');}');
  }
}
