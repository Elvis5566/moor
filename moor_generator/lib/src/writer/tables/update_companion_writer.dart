import 'package:moor_generator/src/model/specified_column.dart';
import 'package:moor_generator/src/model/specified_table.dart';
import 'package:moor_generator/src/writer/writer.dart';

class UpdateCompanionWriter {
  final SpecifiedTable table;
  final Scope scope;

  StringBuffer _buffer;

  UpdateCompanionWriter(this.table, this.scope) {
    _buffer = scope.leaf();
  }

  void write() {
    if (table.fromEntity) {
      _writeCreateCompanion(_buffer);
    }

    _buffer.write('class ${table.getNameForCompanionClass(scope.options)} '
        'extends UpdateCompanion<${table.dartTypeName}> {\n');
    _writeFields();
    _writeConstructor();
    _writeInsertConstructor();
    _writeCopyWith();

    _buffer.write('}\n');
  }

  void _writeFields() {
    for (var column in table.columns) {
      _buffer.write('final Value<${column.dartTypeName}>'
        ' ${column.dartGetterName}${column.suffix};\n');
    }
  }

  void _writeConstructor() {
    _buffer.write('const ${table.getNameForCompanionClass(scope.options)}({');

    for (var column in table.columns) {
      _buffer.write('this.${column.dartGetterName}${column.suffix} = const Value.absent(),');
    }

    _buffer.write('});\n');
  }

  /// Writes a special `.insert` constructor. All columns which may not be
  /// absent during insert are marked `@required` here. Also, we don't need to
  /// use value wrappers here - `Value.absent` simply isn't an option.
  void _writeInsertConstructor() {
    final requiredColumns = <SpecifiedColumn>{};

    // can't be constant because we use initializers (this.a = Value(a)).
    // for a parameter a which is only potentially constant.
    _buffer.write('${table.getNameForCompanionClass(scope.options)}.insert({');

    // Say we had two required columns a and c, and an optional column b.
    // .insert({
    //    @required String a,
    //    this.b = const Value.absent(),
    //    @required String b}): a = Value(a), b = Value(b);
    // We don't need to use this. for the initializers, Dart figures that out.

    for (var column in table.columns) {
      final param = column.dartGetterName;

      if (column.requiredDuringInsert) {
        requiredColumns.add(column);

        _buffer.write('@required ${column.dartTypeName} $param${column.suffix},');
      } else {
        _buffer.write('this.$param${column.suffix} = const Value.absent(),');
      }
    }
    _buffer.write('})');

    var first = true;
    for (var required in requiredColumns) {
      if (first) {
        _buffer.write(': ');
        first = false;
      } else {
        _buffer.write(', ');
      }

      final param = required.dartGetterName;
      _buffer.write('$param${required.suffix} = Value($param${required.suffix})');
    }

    _buffer.write(';\n');
  }

  void _writeCopyWith() {
    _buffer
      ..write(table.getNameForCompanionClass(scope.options))
      ..write(' copyWith({');
    var first = true;
    for (var column in table.columns) {
      if (!first) {
        _buffer.write(', ');
      }
      first = false;
      _buffer.write('Value<${column.dartTypeName}> ${column.dartGetterName}${column.suffix}');
    }

    _buffer
      ..write('}) {\n') //
      ..write('return ${table.getNameForCompanionClass(scope.options)}(');
    for (var column in table.columns) {
      final name = column.dartGetterName;
      final suffix = column.suffix;
      _buffer.write('$name$suffix: $name$suffix ?? this.$name$suffix,');
    }
    _buffer.write(');\n}\n');
  }

  void _writeCreateCompanion(StringBuffer buffer) {
    final companionClass = table.getNameForCompanionClass(scope.options);
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
