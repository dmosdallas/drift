---

title: Migrations
description: Tooling and APIs to safely change the schema of your database.

---

The strict schema of tables and columns is what enables type-safe queries to
the database.
But since the schema is stored in the database too, changing it needs to happen
through migrations developed as part of your app. Drift provides APIs to make most
migrations easy to write, as well as command-line and testing tools to ensure
the migrations are correct.


## Drift tools

Writing correct migrations is crucial to ensure that your users won't end up with a broken database
in an inconsistent state.
For this reason, drift offers tools that make writing and testing migrations safe and easy. By exporting
each version of your schema to a json file, drift can reconstruct older versions of your database
schema. This is helpful to:

1. Test migrations between any two versions of your app.
2. Write migrations between older versions your app more easily, as the current schema generated by drift
   would also include subsequent changes from newer versions.

For this reason, we recommend using drift's tools based on [exporting schemas](exports.md)
for writing migrations.
These also enable [unit tests](tests.md), giving you confidence that your schema migration
is working correctly.


## Manual setup 

Drift provides a migration API that can be used to gradually apply schema changes after bumping
the `schemaVersion` getter inside the `Database` class. To use it, override the `migration`
getter.

Here's an example: Let's say you wanted to add a due date to your todo entries (`v2` of the schema).
Later, you decide to also add a priority column (`v3` of the schema).

{{ load_snippet('table','lib/snippets/migrations/migrations.dart.excerpt.json') }}

We can now change the `database` class like this:

{{ load_snippet('start','lib/snippets/migrations/migrations.dart.excerpt.json') }}

You can also add individual tables or drop them - see the reference of [Migrator](https://pub.dev/documentation/drift/latest/drift/Migrator-class.html)
for all the available options.

You can also use higher-level query APIs like `select`, `update` or `delete` inside a migration callback.
However, be aware that drift expects the latest schema when creating SQL statements or mapping results.
For instance, when adding a new column to your database, you shouldn't run a `select` on that table before
you've actually added the column. In general, try to avoid running queries in migration callbacks if possible.

Writing migrations without any tooling support isn't easy. Since correct migrations are
essential for app updates to work smoothly, we strongly recommend using the tools and testing
framework provided by drift to ensure your migrations are correct.
To do that, [export old versions](exports.md) to then use easy
[step-by-step migrations](step_by_step.md) or [tests](tests.md).

## General tips 

To ensure your schema stays consistent during a migration, you can wrap it in a `transaction` block.
However, be aware that some pragmas (including `foreign_keys`) can't be changed inside transactions.
Still, it can be useful to:

- always re-enable foreign keys before using the database, by enabling them in [`beforeOpen`](#post-migration-callbacks).
- disable foreign-keys before migrations
- run migrations inside a transaction
- make sure your migrations didn't introduce any inconsistencies with `PRAGMA foreign_key_check`.

With all of this combined, a migration callback can look like this:

{{ load_snippet('structured','lib/snippets/migrations/migrations.dart.excerpt.json') }}

## Post-migration callbacks

The `beforeOpen` parameter in `MigrationStrategy` can be used to populate data after the database has been created.
It runs after migrations, but before any other query. Note that it will be called whenever the database is opened,
regardless of whether a migration actually ran or not. You can use `details.hadUpgrade` or `details.wasCreated` to
check whether migrations were necessary:

```dart
beforeOpen: (details) async {
    if (details.wasCreated) {
      final workId = await into(categories).insert(Category(description: 'Work'));

      await into(todos).insert(TodoEntry(
            content: 'A first todo entry',
            category: null,
            targetDate: DateTime.now(),
      ));

      await into(todos).insert(
            TodoEntry(
              content: 'Rework persistence code',
              category: workId,
              targetDate: DateTime.now().add(const Duration(days: 4)),
      ));
    }
},
```

You could also activate pragma statements that you need:

```dart
beforeOpen: (details) async {
  if (details.wasCreated) {
    // ...
  }
  await customStatement('PRAGMA foreign_keys = ON');
}
```

## During development

During development, you might be changing your schema very often and don't want to write migrations for that
yet. You can just delete your apps' data and reinstall the app - the database will be deleted and all tables
will be created again. Please note that uninstalling is not enough sometimes - Android might have backed up
the database file and will re-create it when installing the app again.

You can also delete and re-create all tables every time your app is opened, see [this comment](https://github.com/simolus3/drift/issues/188#issuecomment-542682912)
on how that can be achieved.

## Verifying a database schema at runtime

Instead (or in addition to) [writing tests](#verifying-a-database-schema-at-runtime) to ensure your migrations work as they should,
you can use a new API from `drift_dev` 1.5.0 to verify the current schema without any additional setup.



{{ load_snippet('(full)','lib/snippets/migrations/runtime_verification.dart.excerpt.json') }}

When you use `validateDatabaseSchema`, drift will transparently:

- collect information about your database by reading from `sqlite3_schema`.
- create a fresh in-memory instance of your database and create a reference schema with `Migrator.createAll()`.
- compare the two. Ideally, your actual schema at runtime should be identical to the fresh one even though it
  grew through different versions of your app.

When a mismatch is found, an exception with a message explaining exactly where another value was expected will
be thrown.
This allows you to find issues with your schema migrations quickly.