// #docregion setup
import 'package:test/test.dart';
import 'package:drift_dev/api/migrations_native.dart';

// The generated directory from before.
import 'generated_migrations/schema.dart';

// #enddocregion setup
import '../migrations.dart';
// #docregion setup

void main() {
  late SchemaVerifier verifier;

  setUpAll(() {
    // GeneratedHelper() was generated by drift, the verifier is an api
    // provided by drift_dev.
    verifier = SchemaVerifier(GeneratedHelper());
  });

  test('upgrade from v1 to v2', () async {
    // Use startAt(1) to obtain a database connection with all tables
    // from the v1 schema.
    final connection = await verifier.startAt(1);
    final db = MyDatabase(connection);

    // Use this to run a migration to v2 and then validate that the
    // database has the expected schema.
    await verifier.migrateAndValidate(db, 2);
  });
}
// #enddocregion setup
