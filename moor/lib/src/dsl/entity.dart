part of 'dsl.dart';

class Entity {
  const Entity();
}

abstract class EntityColumnBase {
  /// Name of the column in database
  String get name;

  bool get isNullable;

  String get uniqueGroup;

  bool get auto;

  int get length;
}

class EntityColumn implements EntityColumnBase {
  /// Name of the column in database
  final String name;

  final bool isNullable;

  final String uniqueGroup;

  final bool auto;

  final int length;

  final Type converter;

  final String defaultValue;

  const EntityColumn({this.name, this.isNullable = false, this.uniqueGroup, this.auto = false, this.length, this.converter, this.defaultValue});
}

/// Annotation to declare a model property as primary key in database table
class EntityPrimaryKey implements EntityColumnBase {
  /// Name of the column in database
  final String name;

  final bool isNullable = false;

  final String uniqueGroup;

  final bool auto;

  final int length;

  const EntityPrimaryKey({this.name, this.uniqueGroup, this.auto = false, this.length});
}

abstract class ForeignBase implements EntityColumnBase {}

class EntityToOne implements ForeignBase {
  final Type dao;
  /// Name of the column in database
  final String name;

  final bool isNullable;

  final String uniqueGroup;

  final bool auto = false;

  final int length;

  /// The field/column in the foreign bean
  final String refCol;


  const EntityToOne(this.dao, {
    this.name,
    this.isNullable = false,
    this.uniqueGroup,
    this.length,
    this.refCol = 'id',
  });
}
