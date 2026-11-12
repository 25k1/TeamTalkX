import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

part 'app_database.g.dart';

@DataClassName('CertificatePinRow')
class CertificatePins extends Table {
  TextColumn get endpoint => text()();

  TextColumn get sha256 => text().nullable()();
  TextColumn get subject => text()();
  TextColumn get issuer => text()();
  DateTimeColumn get notAfter => dateTime()();
  DateTimeColumn get savedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {endpoint};
}

@DataClassName('ChatMessageRow')
@TableIndex(
  name: 'chat_messages_by_conversation',
  columns: {#server, #conversation, #id},
)
class ChatMessages extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get server => text()();
  TextColumn get conversation => text()();

  TextColumn get kind => text()();
  TextColumn get sender => text()();
  BoolColumn get fromMe => boolean()();
  TextColumn get body => text()();
  DateTimeColumn get sentAt => dateTime()();

  BoolColumn get read => boolean().withDefault(const Constant(false))();
}

@DataClassName('ChatServerRow')
class ChatServers extends Table {
  TextColumn get server => text()();
  TextColumn get name => text()();

  @override
  Set<Column<Object>> get primaryKey => {server};
}

@DriftDatabase(tables: [CertificatePins, ChatMessages, ChatServers])
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.executor);

  AppDatabase.open() : super(driftDatabase(name: 'teamtalkx'));

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onUpgrade: (m, from, to) async {
      if (from < 2) {
        await m.createTable(chatMessages);
        await m.createTable(chatServers);
        await m.createIndex(chatMessagesByConversation);
      }
    },
  );
}
