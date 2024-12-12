part of '../../query_builder.dart';

/// Signature of a function that generates an [OrderingTerm] when provided with
/// a table.
typedef OrderClauseGenerator<T> = OrderingTerm Function(T tbl);

/// The abstract base class for all select statements in the drift api.
///
/// Users are not allowed to extend, implement or mix-in this class.
@sealed
abstract class BaseSelectStatement<Row> extends Component with Selectable<Row> {
  Iterable<(Expression, String)> get _expandedColumns;

  /// The name for the given [expression] in the result set, or `null` if
  /// [expression] was not added as a column to this select statement.
  String? _nameForColumn(Expression expression);

  FutureOr<Row> _mapRow(Map<String, Object?> fromDatabase);
}

/// A select statement that doesn't use joins.
///
/// For more information, see [DatabaseConnectionUser.select].
class SimpleSelectStatement<T extends HasResultSet, D> extends Query<T, D>
    with SingleTableQueryMixin<T, D>, LimitContainerMixin<T, D>, Selectable<D>
    implements BaseSelectStatement<D> {
  /// Whether duplicate rows should be eliminated from the result (this is a
  /// `SELECT DISTINCT` statement in sql). Defaults to false.
  final bool distinct;

  /// Used internally by drift, users will want to call
  /// [DatabaseConnectionUser.select] instead.
  SimpleSelectStatement(super.database, super.table, {this.distinct = false});

  /// The tables this select statement reads from.
  @visibleForOverriding
  @Deprecated('Use watchedTables on the GenerationContext')
  Set<ResultSetImplementation> get watchedTables => {table};

  @override
  Iterable<(Expression, String)> get _expandedColumns =>
      table.$columns.map((e) => (e, e.name));

  @override
  String? _nameForColumn(Expression expression) {
    if (table.$columns.contains(expression)) {
      return (expression as Column).name;
    } else {
      return null;
    }
  }

  @override
  void writeStartPart(GenerationContext ctx) {
    ctx.buffer
      ..write(_beginOfSelect(distinct))
      ..write(' * FROM ');
    ctx.writeResultSet(table);
  }

  @override
  Future<List<D>> get() {
    final ctx = constructQuery();
    return _getRaw(ctx).then(_mapResponse);
  }

  @override
  Stream<List<D>> watch() {
    final query = constructQuery();
    final fetcher = QueryStreamFetcher(
      readsFrom: TableUpdateQuery.onAllTables(query.watchedTables),
      fetchData: () => _getRaw(query),
      key: StreamKey(query.sql, query.boundVariables),
    );

    return database.createStream(fetcher).asyncMapPerSubscription(_mapResponse);
  }

  Future<List<Map<String, Object?>>> _getRaw(GenerationContext ctx) {
    return database.withCurrentExecutor((e) {
      return e.runSelect(ctx.sql, ctx.boundVariables);
    });
  }

  @override
  FutureOr<D> _mapRow(Map<String, Object?> row) {
    return table.map(row);
  }

  FutureOr<List<D>> _mapResponse(List<Map<String, Object?>> rows) {
    return rows.mapAsyncAndAwait(table.map);
  }

  /// Creates a select statement that operates on more than one table by
  /// applying the given joins.
  ///
  /// Example from the todolist example which will load the category for each
  /// item:
  /// ```
  /// final results = await select(todos).join([
  ///   leftOuterJoin(categories, categories.id.equalsExp(todos.category))
  /// ]).get();
  ///
  /// return results.map((row) {
  ///   final entry = row.readTable(todos);
  ///   final category = row.readTable(categories);
  ///   return EntryWithCategory(entry, category);
  /// }).toList();
  /// ```
  ///
  /// See also:
  ///  - https://drift.simonbinder.eu/docs/advanced-features/joins/#joins
  ///  - [innerJoin], [leftOuterJoin] and [crossJoin], which can be used to
  ///  construct a [Join].
  ///  - [DatabaseConnectionUser.alias], which can be used to build statements
  ///  that refer to the same table multiple times.
  JoinedSelectStatement join(List<Join> joins) {
    final statement = JoinedSelectStatement(database, table, joins, distinct);

    if (whereExpr != null) {
      statement.where(whereExpr!.predicate);
    }
    if (orderByExpr != null) {
      statement.orderBy(orderByExpr!.terms);
    }
    if (limitExpr != null) {
      statement.limitExpr = limitExpr;
    }

    return statement;
  }

  /// {@macro drift_select_addColumns}
  JoinedSelectStatement addColumns(List<Expression> expressions) {
    return join([])..addColumns(expressions);
  }

  /// Orders the result by the given clauses. The clauses coming first in the
  /// list have a higher priority, the later clauses are only considered if the
  /// first clause considers two rows to be equal.
  ///
  /// Example that first displays the users who are awesome and sorts users by
  /// their id as a secondary criterion:
  /// ```
  /// (db.select(db.users)
  ///    ..orderBy([
  ///      (u) =>
  ///        OrderingTerm(expression: u.isAwesome, mode: OrderingMode.desc),
  ///      (u) => OrderingTerm(expression: u.id)
  ///    ]))
  ///  .get()
  /// ```
  void orderBy(List<OrderClauseGenerator<T>> clauses) {
    orderByExpr = OrderBy(clauses.map((t) => t(table.asDslTable)).toList());
  }
}

String _beginOfSelect(bool distinct) {
  return distinct ? 'SELECT DISTINCT' : 'SELECT';
}

@internal
final class SelectWithoutTables extends BaseSelectStatement<TypedResult>
    with Selectable<TypedResult> {
  /// Map of added columns to chosen aliases.
  final Map<Expression, String> _columns;
  final DatabaseConnectionUser _db;

  SelectWithoutTables(this._db, Iterable<Expression> columns)
      : _columns = {
          for (final (i, column) in columns.indexed) column: 'c$i',
        };

  @override
  Iterable<(Expression<Object>, String)> get _expandedColumns =>
      _columns.entries.map((e) => (e.key, e.value));

  @override
  TypedResult _mapRow(Map<String, Object?> fromDatabase) {
    final queryRow = QueryRow(fromDatabase, _db);
    return TypedResult(
      const {},
      queryRow,
      _LazyExpressionMap(_columns, queryRow),
    );
  }

  @override
  String? _nameForColumn(Expression<Object> expression) {
    return _columns[expression];
  }

  @override
  void writeInto(GenerationContext context) {
    final isRoot = context.buffer.isEmpty;
    context.buffer.write('SELECT ');
    var first = true;
    for (final MapEntry(key: expr, value: alias) in _columns.entries) {
      if (!first) {
        context.buffer.write(', ');
      }
      first = false;
      expr.writeInto(context);
      context.buffer.write(' ${context.identifier(alias)}');
    }

    if (isRoot) context.buffer.write(';');
  }

  GenerationContext _createContext() {
    final context = GenerationContext.fromDb(_db);
    writeInto(context);
    return context;
  }

  Future<List<Map<String, Object?>>> _fetchRaw(GenerationContext context) {
    return _db.withCurrentExecutor((e) {
      return e.runSelect(context.sql, context.boundVariables);
    });
  }

  @override
  Future<List<TypedResult>> get() async {
    final context = _createContext();
    final rows = await _fetchRaw(context);
    return [for (final row in rows) _mapRow(row)];
  }

  @override
  Stream<List<TypedResult>> watch() {
    final context = _createContext();
    return _db
        .createStream(QueryStreamFetcher(
          readsFrom: TableUpdateQuery.onAllTables(context.watchedTables),
          key: StreamKey(context.sql, context.boundVariables),
          fetchData: () => _fetchRaw(context),
        ))
        .map((rows) => [for (final row in rows) _mapRow(row)]);
  }
}

/// A result row in a [JoinedSelectStatement] that can parse the result of
/// multiple entities.
class TypedResult {
  /// Creates the result from the parsed table data.
  TypedResult(this._parsedData, this.rawData,
      [this._parsedExpressions = const {}]);

  final Map<ResultSetImplementation, dynamic> _parsedData;
  final Map<Expression, dynamic> _parsedExpressions;

  /// The raw data contained in this row.
  final QueryRow rawData;

  /// Reads all data that belongs to the given [table] from this row.
  ///
  /// If this row does not contain non-null columns of the [table], this method
  /// will throw an [ArgumentError]. Use [readTableOrNull] for nullable tables.
  D readTable<T extends HasResultSet, D>(ResultSetImplementation<T, D> table) {
    if (!_parsedData.containsKey(table)) {
      throw ArgumentError(
          'Invalid table passed to readTable: ${table.aliasedName}. This row '
          'does not contain values for that table. \n'
          'Please use readTableOrNull for outer joins.');
    }

    return _parsedData[table] as D;
  }

  /// Reads all data that belongs to the given [table] from this row.
  ///
  /// Returns `null` if this row does not contain non-null values of the
  /// [table].
  ///
  /// See also: [readTable], which throws instead of returning `null`.
  D? readTableOrNull<T extends HasResultSet, D>(
      ResultSetImplementation<T, D> table) {
    return _parsedData[table] as D?;
  }

  /// Reads a single column from an [expr]. The expression must have been added
  /// as a column, for instance via [JoinedSelectStatement.addColumns].
  ///
  /// To access the underlying columns directly, use [rawData].
  D? read<D extends Object>(Expression<D> expr) {
    if (_parsedExpressions.containsKey(expr)) {
      return _parsedExpressions[expr] as D?;
    }

    throw ArgumentError(
        'Invalid call to read(): $expr. This result set does not have a column '
        'for that expression.');
  }

  /// Reads a column that has a type converter applied to it from the row.
  ///
  /// This calls [read] internally, which reads the column but without applying
  /// a type converter.
  D? readWithConverter<D, S extends Object>(
      GeneratedColumnWithTypeConverter<D, S> column) {
    return NullAwareTypeConverter.wrapFromSql(
        column.converter, read<S>(column));
  }
}

/// This extension is used to add custom data to a [TypedResult] row outside of this library.
@internal
extension EditTypedResultExtension on TypedResult {
  /// Adds a new expression to this result row.
  void addData(ResultSetImplementation table, dynamic data) {
    _parsedData[table] = data;
  }
}
