part of 'parser.dart';

mixin SchemaParser on ParserBase {
  CreateTableStatement _createTable() {
    if (!_matchOne(TokenType.create)) return null;
    final first = _previous;

    _consume(TokenType.table, 'Expected TABLE keyword here');

    var ifNotExists = false;

    if (_matchOne(TokenType.$if)) {
      _consume(TokenType.not, 'Expected IF to be followed by NOT EXISTS');
      _consume(TokenType.exists, 'Expected IF NOT to be followed by EXISTS');
      ifNotExists = true;
    }

    final tableIdentifier =
        _consume(TokenType.identifier, 'Expected a table name')
            as IdentifierToken;

    // we don't currently support CREATE TABLE x AS SELECT ... statements
    _consume(
        TokenType.leftParen, 'Expected opening parenthesis to list columns');

    final columns = <ColumnDefinition>[];
    do {
      columns.add(_columnDefinition());
    } while (_matchOne(TokenType.comma));
    // todo parse table constraints

    _consume(TokenType.rightParen, 'Expected closing parenthesis');

    var withoutRowId = false;
    if (_matchOne(TokenType.without)) {
      _consume(
          TokenType.rowid, 'Expected ROWID to complete the WITHOUT ROWID part');
      withoutRowId = true;
    }

    return CreateTableStatement(
      ifNotExists: ifNotExists,
      tableName: tableIdentifier.identifier,
      withoutRowId: withoutRowId,
      columns: columns,
    )..setSpan(first, _previous);
  }

  ColumnDefinition _columnDefinition() {
    final name = _consume(TokenType.identifier, 'Expected a column name')
        as IdentifierToken;
    IdentifierToken typeName;

    if (_matchOne(TokenType.identifier)) {
      typeName = _previous as IdentifierToken;
    }

    final constraints = <ColumnConstraint>[];
    ColumnConstraint constraint;
    while ((constraint = _columnConstraint(orNull: true)) != null) {
      constraints.add(constraint);
    }

    return ColumnDefinition(
      columnName: name.identifier,
      typeName: typeName?.identifier,
      constraints: constraints,
    )..setSpan(name, _previous);
  }

  ColumnConstraint _columnConstraint({bool orNull = false}) {
    Token first;
    IdentifierToken name;
    if (_matchOne(TokenType.constraint)) {
      first = _previous;
      name = _consume(
              TokenType.identifier, 'Expect a name for the constraint here')
          as IdentifierToken;
    }

    final resolvedName = name?.identifier;

    if (_matchOne(TokenType.primary)) {
      // set reference to first token in this constraint if not set because of
      // the CONSTRAINT token
      first ??= _previous;
      _consume(TokenType.key, 'Expected KEY to complete PRIMARY KEY clause');

      final mode = _orderingModeOrNull();
      final conflict = _conflictClauseOrNull();
      final hasAutoInc = _matchOne(TokenType.autoincrement);

      return PrimaryKey(resolvedName,
          autoIncrement: hasAutoInc, mode: mode, onConflict: conflict)
        ..setSpan(first, _previous);
    }
    if (_matchOne(TokenType.not)) {
      first ??= _previous;
      _consume(TokenType.$null, 'Expected NULL to complete NOT NULL');

      return NotNull(resolvedName, onConflict: _conflictClauseOrNull())
        ..setSpan(first, _previous);
    }
    if (_matchOne(TokenType.unique)) {
      first ??= _previous;
      return Unique(resolvedName, _conflictClauseOrNull())
        ..setSpan(first, _previous);
    }
    if (_matchOne(TokenType.check)) {
      first ??= _previous;
      _consume(TokenType.leftParen, 'Expected opening parenthesis');
      final expr = expression();
      _consume(TokenType.rightParen, 'Expected closing parenthesis');

      return CheckColumn(resolvedName, expr)..setSpan(first, _previous);
    }
    if (_matchOne(TokenType.$default)) {
      first ??= _previous;
      Expression expr = _literalOrNull();

      if (expr == null) {
        // no literal, expect (expression)
        _consume(TokenType.leftParen,
            'Expected opening parenthesis before expression');
        expr = expression();
        _consume(TokenType.rightParen, 'Expected closing parenthesis');
      }

      return Default(resolvedName, expr);
    }
    if (_matchOne(TokenType.collate)) {
      first ??= _previous;
      final collation = _consumeIdentifier('Expected the collation name');

      return CollateConstraint(resolvedName, collation.identifier)
        ..setSpan(first, _previous);
    }
    if (_peek.type == TokenType.references) {
      first ??= _peek;
      final clause = _foreignKeyClause();
      return ForeignKeyColumnConstraint(resolvedName, clause)
        ..setSpan(first, _previous);
    }

    // no known column constraint matched. If orNull is set and we're not
    // guaranteed to be in a constraint clause (started with CONSTRAINT), we
    // can return null
    if (orNull && name == null) {
      return null;
    }
    _error('Expected a constraint (primary key, nullability, etc.)');
  }

  ConflictClause _conflictClauseOrNull() {
    if (_matchOne(TokenType.on)) {
      _consume(TokenType.conflict,
          'Expected CONFLICT to complete ON CONFLICT clause');

      const modes = {
        TokenType.rollback: ConflictClause.rollback,
        TokenType.abort: ConflictClause.abort,
        TokenType.fail: ConflictClause.fail,
        TokenType.ignore: ConflictClause.ignore,
        TokenType.replace: ConflictClause.replace,
      };

      if (_match(modes.keys)) {
        return modes[_previous.type];
      } else {
        _error('Expected a conflict handler (rollback, abort, etc.) here');
      }
    }

    return null;
  }

  ForeignKeyClause _foreignKeyClause() {
    // https://www.sqlite.org/syntax/foreign-key-clause.html
    _consume(TokenType.references, 'Expected REFERENCES');
    final firstToken = _previous;

    final foreignTable = _consumeIdentifier('Expected a table name');
    final foreignTableName = TableReference(foreignTable.identifier, null)
      ..setSpan(foreignTable, foreignTable);

    final columnNames = <Reference>[];
    if (_matchOne(TokenType.leftParen)) {
      do {
        final referenceId = _consumeIdentifier('Expected a column name');
        final reference = Reference(columnName: referenceId.identifier)
          ..setSpan(referenceId, referenceId);
        columnNames.add(reference);
      } while (_matchOne(TokenType.comma));

      _consume(TokenType.rightParen,
          'Expected closing paranthesis after column names');
    }

    ReferenceAction onDelete, onUpdate;

    while (_matchOne(TokenType.on)) {
      if (_matchOne(TokenType.delete)) {
        onDelete = _referenceAction();
      } else if (_matchOne(TokenType.update)) {
        onUpdate = _referenceAction();
      } else {
        _error('Expected either DELETE or UPDATE');
      }
    }

    return ForeignKeyClause(
      foreignTable: foreignTableName,
      columnNames: columnNames,
      onUpdate: onUpdate,
      onDelete: onDelete,
    )..setSpan(firstToken, _previous);
  }

  ReferenceAction _referenceAction() {
    if (_matchOne(TokenType.cascade)) {
      return ReferenceAction.cascade;
    } else if (_matchOne(TokenType.restrict)) {
      return ReferenceAction.restrict;
    } else if (_matchOne(TokenType.no)) {
      _consume(TokenType.action, 'Expect ACTION to complete NO ACTION clause');
      return ReferenceAction.noAction;
    } else if (_matchOne(TokenType.set)) {
      if (_matchOne(TokenType.$null)) {
        return ReferenceAction.setNull;
      } else if (_matchOne(TokenType.$default)) {
        return ReferenceAction.setDefault;
      } else {
        _error('Expected either NULL or DEFAULT as set action here');
      }
    } else {
      _error('Not a valid action, expected CASCADE, SET NULL, etc..');
    }
  }
}
