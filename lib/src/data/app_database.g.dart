// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_database.dart';

// ignore_for_file: type=lint
class $CertificatePinsTable extends CertificatePins
    with TableInfo<$CertificatePinsTable, CertificatePinRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CertificatePinsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _endpointMeta = const VerificationMeta(
    'endpoint',
  );
  @override
  late final GeneratedColumn<String> endpoint = GeneratedColumn<String>(
    'endpoint',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sha256Meta = const VerificationMeta('sha256');
  @override
  late final GeneratedColumn<String> sha256 = GeneratedColumn<String>(
    'sha256',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _subjectMeta = const VerificationMeta(
    'subject',
  );
  @override
  late final GeneratedColumn<String> subject = GeneratedColumn<String>(
    'subject',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _issuerMeta = const VerificationMeta('issuer');
  @override
  late final GeneratedColumn<String> issuer = GeneratedColumn<String>(
    'issuer',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _notAfterMeta = const VerificationMeta(
    'notAfter',
  );
  @override
  late final GeneratedColumn<DateTime> notAfter = GeneratedColumn<DateTime>(
    'not_after',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _savedAtMeta = const VerificationMeta(
    'savedAt',
  );
  @override
  late final GeneratedColumn<DateTime> savedAt = GeneratedColumn<DateTime>(
    'saved_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    endpoint,
    sha256,
    subject,
    issuer,
    notAfter,
    savedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'certificate_pins';
  @override
  VerificationContext validateIntegrity(
    Insertable<CertificatePinRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('endpoint')) {
      context.handle(
        _endpointMeta,
        endpoint.isAcceptableOrUnknown(data['endpoint']!, _endpointMeta),
      );
    } else if (isInserting) {
      context.missing(_endpointMeta);
    }
    if (data.containsKey('sha256')) {
      context.handle(
        _sha256Meta,
        sha256.isAcceptableOrUnknown(data['sha256']!, _sha256Meta),
      );
    }
    if (data.containsKey('subject')) {
      context.handle(
        _subjectMeta,
        subject.isAcceptableOrUnknown(data['subject']!, _subjectMeta),
      );
    } else if (isInserting) {
      context.missing(_subjectMeta);
    }
    if (data.containsKey('issuer')) {
      context.handle(
        _issuerMeta,
        issuer.isAcceptableOrUnknown(data['issuer']!, _issuerMeta),
      );
    } else if (isInserting) {
      context.missing(_issuerMeta);
    }
    if (data.containsKey('not_after')) {
      context.handle(
        _notAfterMeta,
        notAfter.isAcceptableOrUnknown(data['not_after']!, _notAfterMeta),
      );
    } else if (isInserting) {
      context.missing(_notAfterMeta);
    }
    if (data.containsKey('saved_at')) {
      context.handle(
        _savedAtMeta,
        savedAt.isAcceptableOrUnknown(data['saved_at']!, _savedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_savedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {endpoint};
  @override
  CertificatePinRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CertificatePinRow(
      endpoint: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}endpoint'],
      )!,
      sha256: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}sha256'],
      ),
      subject: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}subject'],
      )!,
      issuer: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}issuer'],
      )!,
      notAfter: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}not_after'],
      )!,
      savedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}saved_at'],
      )!,
    );
  }

  @override
  $CertificatePinsTable createAlias(String alias) {
    return $CertificatePinsTable(attachedDatabase, alias);
  }
}

class CertificatePinRow extends DataClass
    implements Insertable<CertificatePinRow> {
  /// `host:port`.
  final String endpoint;

  /// The accepted certificate's SHA-256 (hex), or null when a certificate
  /// authority vouched for the server's certificate.
  final String? sha256;
  final String subject;
  final String issuer;
  final DateTime notAfter;
  final DateTime savedAt;
  const CertificatePinRow({
    required this.endpoint,
    this.sha256,
    required this.subject,
    required this.issuer,
    required this.notAfter,
    required this.savedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['endpoint'] = Variable<String>(endpoint);
    if (!nullToAbsent || sha256 != null) {
      map['sha256'] = Variable<String>(sha256);
    }
    map['subject'] = Variable<String>(subject);
    map['issuer'] = Variable<String>(issuer);
    map['not_after'] = Variable<DateTime>(notAfter);
    map['saved_at'] = Variable<DateTime>(savedAt);
    return map;
  }

  CertificatePinsCompanion toCompanion(bool nullToAbsent) {
    return CertificatePinsCompanion(
      endpoint: Value(endpoint),
      sha256: sha256 == null && nullToAbsent
          ? const Value.absent()
          : Value(sha256),
      subject: Value(subject),
      issuer: Value(issuer),
      notAfter: Value(notAfter),
      savedAt: Value(savedAt),
    );
  }

  factory CertificatePinRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CertificatePinRow(
      endpoint: serializer.fromJson<String>(json['endpoint']),
      sha256: serializer.fromJson<String?>(json['sha256']),
      subject: serializer.fromJson<String>(json['subject']),
      issuer: serializer.fromJson<String>(json['issuer']),
      notAfter: serializer.fromJson<DateTime>(json['notAfter']),
      savedAt: serializer.fromJson<DateTime>(json['savedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'endpoint': serializer.toJson<String>(endpoint),
      'sha256': serializer.toJson<String?>(sha256),
      'subject': serializer.toJson<String>(subject),
      'issuer': serializer.toJson<String>(issuer),
      'notAfter': serializer.toJson<DateTime>(notAfter),
      'savedAt': serializer.toJson<DateTime>(savedAt),
    };
  }

  CertificatePinRow copyWith({
    String? endpoint,
    Value<String?> sha256 = const Value.absent(),
    String? subject,
    String? issuer,
    DateTime? notAfter,
    DateTime? savedAt,
  }) => CertificatePinRow(
    endpoint: endpoint ?? this.endpoint,
    sha256: sha256.present ? sha256.value : this.sha256,
    subject: subject ?? this.subject,
    issuer: issuer ?? this.issuer,
    notAfter: notAfter ?? this.notAfter,
    savedAt: savedAt ?? this.savedAt,
  );
  CertificatePinRow copyWithCompanion(CertificatePinsCompanion data) {
    return CertificatePinRow(
      endpoint: data.endpoint.present ? data.endpoint.value : this.endpoint,
      sha256: data.sha256.present ? data.sha256.value : this.sha256,
      subject: data.subject.present ? data.subject.value : this.subject,
      issuer: data.issuer.present ? data.issuer.value : this.issuer,
      notAfter: data.notAfter.present ? data.notAfter.value : this.notAfter,
      savedAt: data.savedAt.present ? data.savedAt.value : this.savedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CertificatePinRow(')
          ..write('endpoint: $endpoint, ')
          ..write('sha256: $sha256, ')
          ..write('subject: $subject, ')
          ..write('issuer: $issuer, ')
          ..write('notAfter: $notAfter, ')
          ..write('savedAt: $savedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(endpoint, sha256, subject, issuer, notAfter, savedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CertificatePinRow &&
          other.endpoint == this.endpoint &&
          other.sha256 == this.sha256 &&
          other.subject == this.subject &&
          other.issuer == this.issuer &&
          other.notAfter == this.notAfter &&
          other.savedAt == this.savedAt);
}

class CertificatePinsCompanion extends UpdateCompanion<CertificatePinRow> {
  final Value<String> endpoint;
  final Value<String?> sha256;
  final Value<String> subject;
  final Value<String> issuer;
  final Value<DateTime> notAfter;
  final Value<DateTime> savedAt;
  final Value<int> rowid;
  const CertificatePinsCompanion({
    this.endpoint = const Value.absent(),
    this.sha256 = const Value.absent(),
    this.subject = const Value.absent(),
    this.issuer = const Value.absent(),
    this.notAfter = const Value.absent(),
    this.savedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CertificatePinsCompanion.insert({
    required String endpoint,
    this.sha256 = const Value.absent(),
    required String subject,
    required String issuer,
    required DateTime notAfter,
    required DateTime savedAt,
    this.rowid = const Value.absent(),
  }) : endpoint = Value(endpoint),
       subject = Value(subject),
       issuer = Value(issuer),
       notAfter = Value(notAfter),
       savedAt = Value(savedAt);
  static Insertable<CertificatePinRow> custom({
    Expression<String>? endpoint,
    Expression<String>? sha256,
    Expression<String>? subject,
    Expression<String>? issuer,
    Expression<DateTime>? notAfter,
    Expression<DateTime>? savedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (endpoint != null) 'endpoint': endpoint,
      if (sha256 != null) 'sha256': sha256,
      if (subject != null) 'subject': subject,
      if (issuer != null) 'issuer': issuer,
      if (notAfter != null) 'not_after': notAfter,
      if (savedAt != null) 'saved_at': savedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CertificatePinsCompanion copyWith({
    Value<String>? endpoint,
    Value<String?>? sha256,
    Value<String>? subject,
    Value<String>? issuer,
    Value<DateTime>? notAfter,
    Value<DateTime>? savedAt,
    Value<int>? rowid,
  }) {
    return CertificatePinsCompanion(
      endpoint: endpoint ?? this.endpoint,
      sha256: sha256 ?? this.sha256,
      subject: subject ?? this.subject,
      issuer: issuer ?? this.issuer,
      notAfter: notAfter ?? this.notAfter,
      savedAt: savedAt ?? this.savedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (endpoint.present) {
      map['endpoint'] = Variable<String>(endpoint.value);
    }
    if (sha256.present) {
      map['sha256'] = Variable<String>(sha256.value);
    }
    if (subject.present) {
      map['subject'] = Variable<String>(subject.value);
    }
    if (issuer.present) {
      map['issuer'] = Variable<String>(issuer.value);
    }
    if (notAfter.present) {
      map['not_after'] = Variable<DateTime>(notAfter.value);
    }
    if (savedAt.present) {
      map['saved_at'] = Variable<DateTime>(savedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CertificatePinsCompanion(')
          ..write('endpoint: $endpoint, ')
          ..write('sha256: $sha256, ')
          ..write('subject: $subject, ')
          ..write('issuer: $issuer, ')
          ..write('notAfter: $notAfter, ')
          ..write('savedAt: $savedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ChatMessagesTable extends ChatMessages
    with TableInfo<$ChatMessagesTable, ChatMessageRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ChatMessagesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _serverMeta = const VerificationMeta('server');
  @override
  late final GeneratedColumn<String> server = GeneratedColumn<String>(
    'server',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _conversationMeta = const VerificationMeta(
    'conversation',
  );
  @override
  late final GeneratedColumn<String> conversation = GeneratedColumn<String>(
    'conversation',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _kindMeta = const VerificationMeta('kind');
  @override
  late final GeneratedColumn<String> kind = GeneratedColumn<String>(
    'kind',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _senderMeta = const VerificationMeta('sender');
  @override
  late final GeneratedColumn<String> sender = GeneratedColumn<String>(
    'sender',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _fromMeMeta = const VerificationMeta('fromMe');
  @override
  late final GeneratedColumn<bool> fromMe = GeneratedColumn<bool>(
    'from_me',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("from_me" IN (0, 1))',
    ),
  );
  static const VerificationMeta _bodyMeta = const VerificationMeta('body');
  @override
  late final GeneratedColumn<String> body = GeneratedColumn<String>(
    'body',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sentAtMeta = const VerificationMeta('sentAt');
  @override
  late final GeneratedColumn<DateTime> sentAt = GeneratedColumn<DateTime>(
    'sent_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _readMeta = const VerificationMeta('read');
  @override
  late final GeneratedColumn<bool> read = GeneratedColumn<bool>(
    'read',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("read" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    server,
    conversation,
    kind,
    sender,
    fromMe,
    body,
    sentAt,
    read,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'chat_messages';
  @override
  VerificationContext validateIntegrity(
    Insertable<ChatMessageRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('server')) {
      context.handle(
        _serverMeta,
        server.isAcceptableOrUnknown(data['server']!, _serverMeta),
      );
    } else if (isInserting) {
      context.missing(_serverMeta);
    }
    if (data.containsKey('conversation')) {
      context.handle(
        _conversationMeta,
        conversation.isAcceptableOrUnknown(
          data['conversation']!,
          _conversationMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_conversationMeta);
    }
    if (data.containsKey('kind')) {
      context.handle(
        _kindMeta,
        kind.isAcceptableOrUnknown(data['kind']!, _kindMeta),
      );
    } else if (isInserting) {
      context.missing(_kindMeta);
    }
    if (data.containsKey('sender')) {
      context.handle(
        _senderMeta,
        sender.isAcceptableOrUnknown(data['sender']!, _senderMeta),
      );
    } else if (isInserting) {
      context.missing(_senderMeta);
    }
    if (data.containsKey('from_me')) {
      context.handle(
        _fromMeMeta,
        fromMe.isAcceptableOrUnknown(data['from_me']!, _fromMeMeta),
      );
    } else if (isInserting) {
      context.missing(_fromMeMeta);
    }
    if (data.containsKey('body')) {
      context.handle(
        _bodyMeta,
        body.isAcceptableOrUnknown(data['body']!, _bodyMeta),
      );
    } else if (isInserting) {
      context.missing(_bodyMeta);
    }
    if (data.containsKey('sent_at')) {
      context.handle(
        _sentAtMeta,
        sentAt.isAcceptableOrUnknown(data['sent_at']!, _sentAtMeta),
      );
    } else if (isInserting) {
      context.missing(_sentAtMeta);
    }
    if (data.containsKey('read')) {
      context.handle(
        _readMeta,
        read.isAcceptableOrUnknown(data['read']!, _readMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ChatMessageRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ChatMessageRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      server: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}server'],
      )!,
      conversation: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}conversation'],
      )!,
      kind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}kind'],
      )!,
      sender: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}sender'],
      )!,
      fromMe: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}from_me'],
      )!,
      body: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}body'],
      )!,
      sentAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}sent_at'],
      )!,
      read: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}read'],
      )!,
    );
  }

  @override
  $ChatMessagesTable createAlias(String alias) {
    return $ChatMessagesTable(attachedDatabase, alias);
  }
}

class ChatMessageRow extends DataClass implements Insertable<ChatMessageRow> {
  final int id;
  final String server;
  final String conversation;

  /// `channel`, `broadcast` or `private`.
  final String kind;
  final String sender;
  final bool fromMe;
  final String body;
  final DateTime sentAt;

  /// Reached on screen (D154); messages of one's own are read.
  final bool read;
  const ChatMessageRow({
    required this.id,
    required this.server,
    required this.conversation,
    required this.kind,
    required this.sender,
    required this.fromMe,
    required this.body,
    required this.sentAt,
    required this.read,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['server'] = Variable<String>(server);
    map['conversation'] = Variable<String>(conversation);
    map['kind'] = Variable<String>(kind);
    map['sender'] = Variable<String>(sender);
    map['from_me'] = Variable<bool>(fromMe);
    map['body'] = Variable<String>(body);
    map['sent_at'] = Variable<DateTime>(sentAt);
    map['read'] = Variable<bool>(read);
    return map;
  }

  ChatMessagesCompanion toCompanion(bool nullToAbsent) {
    return ChatMessagesCompanion(
      id: Value(id),
      server: Value(server),
      conversation: Value(conversation),
      kind: Value(kind),
      sender: Value(sender),
      fromMe: Value(fromMe),
      body: Value(body),
      sentAt: Value(sentAt),
      read: Value(read),
    );
  }

  factory ChatMessageRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ChatMessageRow(
      id: serializer.fromJson<int>(json['id']),
      server: serializer.fromJson<String>(json['server']),
      conversation: serializer.fromJson<String>(json['conversation']),
      kind: serializer.fromJson<String>(json['kind']),
      sender: serializer.fromJson<String>(json['sender']),
      fromMe: serializer.fromJson<bool>(json['fromMe']),
      body: serializer.fromJson<String>(json['body']),
      sentAt: serializer.fromJson<DateTime>(json['sentAt']),
      read: serializer.fromJson<bool>(json['read']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'server': serializer.toJson<String>(server),
      'conversation': serializer.toJson<String>(conversation),
      'kind': serializer.toJson<String>(kind),
      'sender': serializer.toJson<String>(sender),
      'fromMe': serializer.toJson<bool>(fromMe),
      'body': serializer.toJson<String>(body),
      'sentAt': serializer.toJson<DateTime>(sentAt),
      'read': serializer.toJson<bool>(read),
    };
  }

  ChatMessageRow copyWith({
    int? id,
    String? server,
    String? conversation,
    String? kind,
    String? sender,
    bool? fromMe,
    String? body,
    DateTime? sentAt,
    bool? read,
  }) => ChatMessageRow(
    id: id ?? this.id,
    server: server ?? this.server,
    conversation: conversation ?? this.conversation,
    kind: kind ?? this.kind,
    sender: sender ?? this.sender,
    fromMe: fromMe ?? this.fromMe,
    body: body ?? this.body,
    sentAt: sentAt ?? this.sentAt,
    read: read ?? this.read,
  );
  ChatMessageRow copyWithCompanion(ChatMessagesCompanion data) {
    return ChatMessageRow(
      id: data.id.present ? data.id.value : this.id,
      server: data.server.present ? data.server.value : this.server,
      conversation: data.conversation.present
          ? data.conversation.value
          : this.conversation,
      kind: data.kind.present ? data.kind.value : this.kind,
      sender: data.sender.present ? data.sender.value : this.sender,
      fromMe: data.fromMe.present ? data.fromMe.value : this.fromMe,
      body: data.body.present ? data.body.value : this.body,
      sentAt: data.sentAt.present ? data.sentAt.value : this.sentAt,
      read: data.read.present ? data.read.value : this.read,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ChatMessageRow(')
          ..write('id: $id, ')
          ..write('server: $server, ')
          ..write('conversation: $conversation, ')
          ..write('kind: $kind, ')
          ..write('sender: $sender, ')
          ..write('fromMe: $fromMe, ')
          ..write('body: $body, ')
          ..write('sentAt: $sentAt, ')
          ..write('read: $read')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    server,
    conversation,
    kind,
    sender,
    fromMe,
    body,
    sentAt,
    read,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ChatMessageRow &&
          other.id == this.id &&
          other.server == this.server &&
          other.conversation == this.conversation &&
          other.kind == this.kind &&
          other.sender == this.sender &&
          other.fromMe == this.fromMe &&
          other.body == this.body &&
          other.sentAt == this.sentAt &&
          other.read == this.read);
}

class ChatMessagesCompanion extends UpdateCompanion<ChatMessageRow> {
  final Value<int> id;
  final Value<String> server;
  final Value<String> conversation;
  final Value<String> kind;
  final Value<String> sender;
  final Value<bool> fromMe;
  final Value<String> body;
  final Value<DateTime> sentAt;
  final Value<bool> read;
  const ChatMessagesCompanion({
    this.id = const Value.absent(),
    this.server = const Value.absent(),
    this.conversation = const Value.absent(),
    this.kind = const Value.absent(),
    this.sender = const Value.absent(),
    this.fromMe = const Value.absent(),
    this.body = const Value.absent(),
    this.sentAt = const Value.absent(),
    this.read = const Value.absent(),
  });
  ChatMessagesCompanion.insert({
    this.id = const Value.absent(),
    required String server,
    required String conversation,
    required String kind,
    required String sender,
    required bool fromMe,
    required String body,
    required DateTime sentAt,
    this.read = const Value.absent(),
  }) : server = Value(server),
       conversation = Value(conversation),
       kind = Value(kind),
       sender = Value(sender),
       fromMe = Value(fromMe),
       body = Value(body),
       sentAt = Value(sentAt);
  static Insertable<ChatMessageRow> custom({
    Expression<int>? id,
    Expression<String>? server,
    Expression<String>? conversation,
    Expression<String>? kind,
    Expression<String>? sender,
    Expression<bool>? fromMe,
    Expression<String>? body,
    Expression<DateTime>? sentAt,
    Expression<bool>? read,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (server != null) 'server': server,
      if (conversation != null) 'conversation': conversation,
      if (kind != null) 'kind': kind,
      if (sender != null) 'sender': sender,
      if (fromMe != null) 'from_me': fromMe,
      if (body != null) 'body': body,
      if (sentAt != null) 'sent_at': sentAt,
      if (read != null) 'read': read,
    });
  }

  ChatMessagesCompanion copyWith({
    Value<int>? id,
    Value<String>? server,
    Value<String>? conversation,
    Value<String>? kind,
    Value<String>? sender,
    Value<bool>? fromMe,
    Value<String>? body,
    Value<DateTime>? sentAt,
    Value<bool>? read,
  }) {
    return ChatMessagesCompanion(
      id: id ?? this.id,
      server: server ?? this.server,
      conversation: conversation ?? this.conversation,
      kind: kind ?? this.kind,
      sender: sender ?? this.sender,
      fromMe: fromMe ?? this.fromMe,
      body: body ?? this.body,
      sentAt: sentAt ?? this.sentAt,
      read: read ?? this.read,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (server.present) {
      map['server'] = Variable<String>(server.value);
    }
    if (conversation.present) {
      map['conversation'] = Variable<String>(conversation.value);
    }
    if (kind.present) {
      map['kind'] = Variable<String>(kind.value);
    }
    if (sender.present) {
      map['sender'] = Variable<String>(sender.value);
    }
    if (fromMe.present) {
      map['from_me'] = Variable<bool>(fromMe.value);
    }
    if (body.present) {
      map['body'] = Variable<String>(body.value);
    }
    if (sentAt.present) {
      map['sent_at'] = Variable<DateTime>(sentAt.value);
    }
    if (read.present) {
      map['read'] = Variable<bool>(read.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ChatMessagesCompanion(')
          ..write('id: $id, ')
          ..write('server: $server, ')
          ..write('conversation: $conversation, ')
          ..write('kind: $kind, ')
          ..write('sender: $sender, ')
          ..write('fromMe: $fromMe, ')
          ..write('body: $body, ')
          ..write('sentAt: $sentAt, ')
          ..write('read: $read')
          ..write(')'))
        .toString();
  }
}

class $ChatServersTable extends ChatServers
    with TableInfo<$ChatServersTable, ChatServerRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ChatServersTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _serverMeta = const VerificationMeta('server');
  @override
  late final GeneratedColumn<String> server = GeneratedColumn<String>(
    'server',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [server, name];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'chat_servers';
  @override
  VerificationContext validateIntegrity(
    Insertable<ChatServerRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('server')) {
      context.handle(
        _serverMeta,
        server.isAcceptableOrUnknown(data['server']!, _serverMeta),
      );
    } else if (isInserting) {
      context.missing(_serverMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {server};
  @override
  ChatServerRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ChatServerRow(
      server: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}server'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
    );
  }

  @override
  $ChatServersTable createAlias(String alias) {
    return $ChatServersTable(attachedDatabase, alias);
  }
}

class ChatServerRow extends DataClass implements Insertable<ChatServerRow> {
  final String server;
  final String name;
  const ChatServerRow({required this.server, required this.name});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['server'] = Variable<String>(server);
    map['name'] = Variable<String>(name);
    return map;
  }

  ChatServersCompanion toCompanion(bool nullToAbsent) {
    return ChatServersCompanion(server: Value(server), name: Value(name));
  }

  factory ChatServerRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ChatServerRow(
      server: serializer.fromJson<String>(json['server']),
      name: serializer.fromJson<String>(json['name']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'server': serializer.toJson<String>(server),
      'name': serializer.toJson<String>(name),
    };
  }

  ChatServerRow copyWith({String? server, String? name}) =>
      ChatServerRow(server: server ?? this.server, name: name ?? this.name);
  ChatServerRow copyWithCompanion(ChatServersCompanion data) {
    return ChatServerRow(
      server: data.server.present ? data.server.value : this.server,
      name: data.name.present ? data.name.value : this.name,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ChatServerRow(')
          ..write('server: $server, ')
          ..write('name: $name')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(server, name);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ChatServerRow &&
          other.server == this.server &&
          other.name == this.name);
}

class ChatServersCompanion extends UpdateCompanion<ChatServerRow> {
  final Value<String> server;
  final Value<String> name;
  final Value<int> rowid;
  const ChatServersCompanion({
    this.server = const Value.absent(),
    this.name = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ChatServersCompanion.insert({
    required String server,
    required String name,
    this.rowid = const Value.absent(),
  }) : server = Value(server),
       name = Value(name);
  static Insertable<ChatServerRow> custom({
    Expression<String>? server,
    Expression<String>? name,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (server != null) 'server': server,
      if (name != null) 'name': name,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ChatServersCompanion copyWith({
    Value<String>? server,
    Value<String>? name,
    Value<int>? rowid,
  }) {
    return ChatServersCompanion(
      server: server ?? this.server,
      name: name ?? this.name,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (server.present) {
      map['server'] = Variable<String>(server.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ChatServersCompanion(')
          ..write('server: $server, ')
          ..write('name: $name, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $CertificatePinsTable certificatePins = $CertificatePinsTable(
    this,
  );
  late final $ChatMessagesTable chatMessages = $ChatMessagesTable(this);
  late final $ChatServersTable chatServers = $ChatServersTable(this);
  late final Index chatMessagesByConversation = Index(
    'chat_messages_by_conversation',
    'CREATE INDEX chat_messages_by_conversation ON chat_messages (server, conversation, id)',
  );
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    certificatePins,
    chatMessages,
    chatServers,
    chatMessagesByConversation,
  ];
}

typedef $$CertificatePinsTableCreateCompanionBuilder =
    CertificatePinsCompanion Function({
      required String endpoint,
      Value<String?> sha256,
      required String subject,
      required String issuer,
      required DateTime notAfter,
      required DateTime savedAt,
      Value<int> rowid,
    });
typedef $$CertificatePinsTableUpdateCompanionBuilder =
    CertificatePinsCompanion Function({
      Value<String> endpoint,
      Value<String?> sha256,
      Value<String> subject,
      Value<String> issuer,
      Value<DateTime> notAfter,
      Value<DateTime> savedAt,
      Value<int> rowid,
    });

class $$CertificatePinsTableFilterComposer
    extends Composer<_$AppDatabase, $CertificatePinsTable> {
  $$CertificatePinsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get endpoint => $composableBuilder(
    column: $table.endpoint,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sha256 => $composableBuilder(
    column: $table.sha256,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get subject => $composableBuilder(
    column: $table.subject,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get issuer => $composableBuilder(
    column: $table.issuer,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get notAfter => $composableBuilder(
    column: $table.notAfter,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get savedAt => $composableBuilder(
    column: $table.savedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$CertificatePinsTableOrderingComposer
    extends Composer<_$AppDatabase, $CertificatePinsTable> {
  $$CertificatePinsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get endpoint => $composableBuilder(
    column: $table.endpoint,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sha256 => $composableBuilder(
    column: $table.sha256,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get subject => $composableBuilder(
    column: $table.subject,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get issuer => $composableBuilder(
    column: $table.issuer,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get notAfter => $composableBuilder(
    column: $table.notAfter,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get savedAt => $composableBuilder(
    column: $table.savedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$CertificatePinsTableAnnotationComposer
    extends Composer<_$AppDatabase, $CertificatePinsTable> {
  $$CertificatePinsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get endpoint =>
      $composableBuilder(column: $table.endpoint, builder: (column) => column);

  GeneratedColumn<String> get sha256 =>
      $composableBuilder(column: $table.sha256, builder: (column) => column);

  GeneratedColumn<String> get subject =>
      $composableBuilder(column: $table.subject, builder: (column) => column);

  GeneratedColumn<String> get issuer =>
      $composableBuilder(column: $table.issuer, builder: (column) => column);

  GeneratedColumn<DateTime> get notAfter =>
      $composableBuilder(column: $table.notAfter, builder: (column) => column);

  GeneratedColumn<DateTime> get savedAt =>
      $composableBuilder(column: $table.savedAt, builder: (column) => column);
}

class $$CertificatePinsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $CertificatePinsTable,
          CertificatePinRow,
          $$CertificatePinsTableFilterComposer,
          $$CertificatePinsTableOrderingComposer,
          $$CertificatePinsTableAnnotationComposer,
          $$CertificatePinsTableCreateCompanionBuilder,
          $$CertificatePinsTableUpdateCompanionBuilder,
          (
            CertificatePinRow,
            BaseReferences<
              _$AppDatabase,
              $CertificatePinsTable,
              CertificatePinRow
            >,
          ),
          CertificatePinRow,
          PrefetchHooks Function()
        > {
  $$CertificatePinsTableTableManager(
    _$AppDatabase db,
    $CertificatePinsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CertificatePinsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CertificatePinsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CertificatePinsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> endpoint = const Value.absent(),
                Value<String?> sha256 = const Value.absent(),
                Value<String> subject = const Value.absent(),
                Value<String> issuer = const Value.absent(),
                Value<DateTime> notAfter = const Value.absent(),
                Value<DateTime> savedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CertificatePinsCompanion(
                endpoint: endpoint,
                sha256: sha256,
                subject: subject,
                issuer: issuer,
                notAfter: notAfter,
                savedAt: savedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String endpoint,
                Value<String?> sha256 = const Value.absent(),
                required String subject,
                required String issuer,
                required DateTime notAfter,
                required DateTime savedAt,
                Value<int> rowid = const Value.absent(),
              }) => CertificatePinsCompanion.insert(
                endpoint: endpoint,
                sha256: sha256,
                subject: subject,
                issuer: issuer,
                notAfter: notAfter,
                savedAt: savedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$CertificatePinsTable, CertificatePinRow>(table),
                  BaseReferences<
                    _$AppDatabase,
                    $CertificatePinsTable,
                    CertificatePinRow
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$CertificatePinsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $CertificatePinsTable,
      CertificatePinRow,
      $$CertificatePinsTableFilterComposer,
      $$CertificatePinsTableOrderingComposer,
      $$CertificatePinsTableAnnotationComposer,
      $$CertificatePinsTableCreateCompanionBuilder,
      $$CertificatePinsTableUpdateCompanionBuilder,
      (
        CertificatePinRow,
        BaseReferences<_$AppDatabase, $CertificatePinsTable, CertificatePinRow>,
      ),
      CertificatePinRow,
      PrefetchHooks Function()
    >;
typedef $$ChatMessagesTableCreateCompanionBuilder =
    ChatMessagesCompanion Function({
      Value<int> id,
      required String server,
      required String conversation,
      required String kind,
      required String sender,
      required bool fromMe,
      required String body,
      required DateTime sentAt,
      Value<bool> read,
    });
typedef $$ChatMessagesTableUpdateCompanionBuilder =
    ChatMessagesCompanion Function({
      Value<int> id,
      Value<String> server,
      Value<String> conversation,
      Value<String> kind,
      Value<String> sender,
      Value<bool> fromMe,
      Value<String> body,
      Value<DateTime> sentAt,
      Value<bool> read,
    });

class $$ChatMessagesTableFilterComposer
    extends Composer<_$AppDatabase, $ChatMessagesTable> {
  $$ChatMessagesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get server => $composableBuilder(
    column: $table.server,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get conversation => $composableBuilder(
    column: $table.conversation,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sender => $composableBuilder(
    column: $table.sender,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get fromMe => $composableBuilder(
    column: $table.fromMe,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get body => $composableBuilder(
    column: $table.body,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get sentAt => $composableBuilder(
    column: $table.sentAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get read => $composableBuilder(
    column: $table.read,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ChatMessagesTableOrderingComposer
    extends Composer<_$AppDatabase, $ChatMessagesTable> {
  $$ChatMessagesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get server => $composableBuilder(
    column: $table.server,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get conversation => $composableBuilder(
    column: $table.conversation,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sender => $composableBuilder(
    column: $table.sender,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get fromMe => $composableBuilder(
    column: $table.fromMe,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get body => $composableBuilder(
    column: $table.body,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get sentAt => $composableBuilder(
    column: $table.sentAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get read => $composableBuilder(
    column: $table.read,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ChatMessagesTableAnnotationComposer
    extends Composer<_$AppDatabase, $ChatMessagesTable> {
  $$ChatMessagesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get server =>
      $composableBuilder(column: $table.server, builder: (column) => column);

  GeneratedColumn<String> get conversation => $composableBuilder(
    column: $table.conversation,
    builder: (column) => column,
  );

  GeneratedColumn<String> get kind =>
      $composableBuilder(column: $table.kind, builder: (column) => column);

  GeneratedColumn<String> get sender =>
      $composableBuilder(column: $table.sender, builder: (column) => column);

  GeneratedColumn<bool> get fromMe =>
      $composableBuilder(column: $table.fromMe, builder: (column) => column);

  GeneratedColumn<String> get body =>
      $composableBuilder(column: $table.body, builder: (column) => column);

  GeneratedColumn<DateTime> get sentAt =>
      $composableBuilder(column: $table.sentAt, builder: (column) => column);

  GeneratedColumn<bool> get read =>
      $composableBuilder(column: $table.read, builder: (column) => column);
}

class $$ChatMessagesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ChatMessagesTable,
          ChatMessageRow,
          $$ChatMessagesTableFilterComposer,
          $$ChatMessagesTableOrderingComposer,
          $$ChatMessagesTableAnnotationComposer,
          $$ChatMessagesTableCreateCompanionBuilder,
          $$ChatMessagesTableUpdateCompanionBuilder,
          (
            ChatMessageRow,
            BaseReferences<_$AppDatabase, $ChatMessagesTable, ChatMessageRow>,
          ),
          ChatMessageRow,
          PrefetchHooks Function()
        > {
  $$ChatMessagesTableTableManager(_$AppDatabase db, $ChatMessagesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ChatMessagesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ChatMessagesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ChatMessagesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> server = const Value.absent(),
                Value<String> conversation = const Value.absent(),
                Value<String> kind = const Value.absent(),
                Value<String> sender = const Value.absent(),
                Value<bool> fromMe = const Value.absent(),
                Value<String> body = const Value.absent(),
                Value<DateTime> sentAt = const Value.absent(),
                Value<bool> read = const Value.absent(),
              }) => ChatMessagesCompanion(
                id: id,
                server: server,
                conversation: conversation,
                kind: kind,
                sender: sender,
                fromMe: fromMe,
                body: body,
                sentAt: sentAt,
                read: read,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String server,
                required String conversation,
                required String kind,
                required String sender,
                required bool fromMe,
                required String body,
                required DateTime sentAt,
                Value<bool> read = const Value.absent(),
              }) => ChatMessagesCompanion.insert(
                id: id,
                server: server,
                conversation: conversation,
                kind: kind,
                sender: sender,
                fromMe: fromMe,
                body: body,
                sentAt: sentAt,
                read: read,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$ChatMessagesTable, ChatMessageRow>(table),
                  BaseReferences<
                    _$AppDatabase,
                    $ChatMessagesTable,
                    ChatMessageRow
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ChatMessagesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ChatMessagesTable,
      ChatMessageRow,
      $$ChatMessagesTableFilterComposer,
      $$ChatMessagesTableOrderingComposer,
      $$ChatMessagesTableAnnotationComposer,
      $$ChatMessagesTableCreateCompanionBuilder,
      $$ChatMessagesTableUpdateCompanionBuilder,
      (
        ChatMessageRow,
        BaseReferences<_$AppDatabase, $ChatMessagesTable, ChatMessageRow>,
      ),
      ChatMessageRow,
      PrefetchHooks Function()
    >;
typedef $$ChatServersTableCreateCompanionBuilder =
    ChatServersCompanion Function({
      required String server,
      required String name,
      Value<int> rowid,
    });
typedef $$ChatServersTableUpdateCompanionBuilder =
    ChatServersCompanion Function({
      Value<String> server,
      Value<String> name,
      Value<int> rowid,
    });

class $$ChatServersTableFilterComposer
    extends Composer<_$AppDatabase, $ChatServersTable> {
  $$ChatServersTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get server => $composableBuilder(
    column: $table.server,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ChatServersTableOrderingComposer
    extends Composer<_$AppDatabase, $ChatServersTable> {
  $$ChatServersTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get server => $composableBuilder(
    column: $table.server,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ChatServersTableAnnotationComposer
    extends Composer<_$AppDatabase, $ChatServersTable> {
  $$ChatServersTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get server =>
      $composableBuilder(column: $table.server, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);
}

class $$ChatServersTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ChatServersTable,
          ChatServerRow,
          $$ChatServersTableFilterComposer,
          $$ChatServersTableOrderingComposer,
          $$ChatServersTableAnnotationComposer,
          $$ChatServersTableCreateCompanionBuilder,
          $$ChatServersTableUpdateCompanionBuilder,
          (
            ChatServerRow,
            BaseReferences<_$AppDatabase, $ChatServersTable, ChatServerRow>,
          ),
          ChatServerRow,
          PrefetchHooks Function()
        > {
  $$ChatServersTableTableManager(_$AppDatabase db, $ChatServersTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ChatServersTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ChatServersTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ChatServersTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> server = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ChatServersCompanion(
                server: server,
                name: name,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String server,
                required String name,
                Value<int> rowid = const Value.absent(),
              }) => ChatServersCompanion.insert(
                server: server,
                name: name,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$ChatServersTable, ChatServerRow>(table),
                  BaseReferences<
                    _$AppDatabase,
                    $ChatServersTable,
                    ChatServerRow
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ChatServersTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ChatServersTable,
      ChatServerRow,
      $$ChatServersTableFilterComposer,
      $$ChatServersTableOrderingComposer,
      $$ChatServersTableAnnotationComposer,
      $$ChatServersTableCreateCompanionBuilder,
      $$ChatServersTableUpdateCompanionBuilder,
      (
        ChatServerRow,
        BaseReferences<_$AppDatabase, $ChatServersTable, ChatServerRow>,
      ),
      ChatServerRow,
      PrefetchHooks Function()
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$CertificatePinsTableTableManager get certificatePins =>
      $$CertificatePinsTableTableManager(_db, _db.certificatePins);
  $$ChatMessagesTableTableManager get chatMessages =>
      $$ChatMessagesTableTableManager(_db, _db.chatMessages);
  $$ChatServersTableTableManager get chatServers =>
      $$ChatServersTableTableManager(_db, _db.chatServers);
}
