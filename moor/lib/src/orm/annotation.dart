class Entity {
  const Entity();
}

abstract class EntityColumnBase {
  /// Name of the column in database
  String? get name;

  bool get isNullable;

  bool get auto;

  int? get length;
}

class EntityColumn implements EntityColumnBase {
  /// Name of the column in database
  final String? name;

  final bool isNullable;

  final bool auto;

  final int? length;

  final Type? converter;

  final String? defaultValue;

  const EntityColumn(
      {this.name,
      this.isNullable = true,
      this.auto = false,
      this.length,
      this.converter,
      this.defaultValue});
}

/// Annotation to declare a model property as primary key in database table
class EntityPrimaryKey implements EntityColumnBase {
  /// Name of the column in database
  final String? name;

  final bool isNullable = false;

  final bool auto;

  final int? length;

  const EntityPrimaryKey({this.name, this.auto = false, this.length});
}

abstract class ForeignBase implements EntityColumnBase {}

class EntityToOne implements ForeignBase {
  /// Name of the column in database
  final String? name;

  final bool isNullable;

  final bool auto = false;

  final int? length;

  /// The field/column in the foreign bean
  final String refCol;

  const EntityToOne({
    this.name,
    this.isNullable = true,
    this.length,
    this.refCol = 'id',
  });
}
