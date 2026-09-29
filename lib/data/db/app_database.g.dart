// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_database.dart';

// ignore_for_file: type=lint
class $CharactersTable extends Characters
    with TableInfo<$CharactersTable, Character> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CharactersTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
      'name', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant(''));
  static const VerificationMeta _displayNameMeta =
      const VerificationMeta('displayName');
  @override
  late final GeneratedColumn<String> displayName = GeneratedColumn<String>(
      'display_name', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant(''));
  static const VerificationMeta _jsonMeta = const VerificationMeta('json');
  @override
  late final GeneratedColumn<String> json = GeneratedColumn<String>(
      'json', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _updatedAtMeta =
      const VerificationMeta('updatedAt');
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
      'updated_at', aliasedName, false,
      type: DriftSqlType.dateTime,
      requiredDuringInsert: false,
      defaultValue: currentDateAndTime);
  @override
  List<GeneratedColumn> get $columns =>
      [id, name, displayName, json, updatedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'characters';
  @override
  VerificationContext validateIntegrity(Insertable<Character> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
          _nameMeta, name.isAcceptableOrUnknown(data['name']!, _nameMeta));
    }
    if (data.containsKey('display_name')) {
      context.handle(
          _displayNameMeta,
          displayName.isAcceptableOrUnknown(
              data['display_name']!, _displayNameMeta));
    }
    if (data.containsKey('json')) {
      context.handle(
          _jsonMeta, json.isAcceptableOrUnknown(data['json']!, _jsonMeta));
    } else if (isInserting) {
      context.missing(_jsonMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(_updatedAtMeta,
          updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Character map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Character(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      name: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}name'])!,
      displayName: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}display_name'])!,
      json: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}json'])!,
      updatedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}updated_at'])!,
    );
  }

  @override
  $CharactersTable createAlias(String alias) {
    return $CharactersTable(attachedDatabase, alias);
  }
}

class Character extends DataClass implements Insertable<Character> {
  final String id;
  final String name;
  final String displayName;

  /// Character.toJson() 完整 JSON
  final String json;

  /// 冗余创建/更新时间（毫秒时间戳）
  final DateTime updatedAt;
  const Character(
      {required this.id,
      required this.name,
      required this.displayName,
      required this.json,
      required this.updatedAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    map['display_name'] = Variable<String>(displayName);
    map['json'] = Variable<String>(json);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  CharactersCompanion toCompanion(bool nullToAbsent) {
    return CharactersCompanion(
      id: Value(id),
      name: Value(name),
      displayName: Value(displayName),
      json: Value(json),
      updatedAt: Value(updatedAt),
    );
  }

  factory Character.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Character(
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      displayName: serializer.fromJson<String>(json['displayName']),
      json: serializer.fromJson<String>(json['json']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String>(name),
      'displayName': serializer.toJson<String>(displayName),
      'json': serializer.toJson<String>(json),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  Character copyWith(
          {String? id,
          String? name,
          String? displayName,
          String? json,
          DateTime? updatedAt}) =>
      Character(
        id: id ?? this.id,
        name: name ?? this.name,
        displayName: displayName ?? this.displayName,
        json: json ?? this.json,
        updatedAt: updatedAt ?? this.updatedAt,
      );
  Character copyWithCompanion(CharactersCompanion data) {
    return Character(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      displayName:
          data.displayName.present ? data.displayName.value : this.displayName,
      json: data.json.present ? data.json.value : this.json,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Character(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('displayName: $displayName, ')
          ..write('json: $json, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, name, displayName, json, updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Character &&
          other.id == this.id &&
          other.name == this.name &&
          other.displayName == this.displayName &&
          other.json == this.json &&
          other.updatedAt == this.updatedAt);
}

class CharactersCompanion extends UpdateCompanion<Character> {
  final Value<String> id;
  final Value<String> name;
  final Value<String> displayName;
  final Value<String> json;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const CharactersCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.displayName = const Value.absent(),
    this.json = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CharactersCompanion.insert({
    required String id,
    this.name = const Value.absent(),
    this.displayName = const Value.absent(),
    required String json,
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        json = Value(json);
  static Insertable<Character> custom({
    Expression<String>? id,
    Expression<String>? name,
    Expression<String>? displayName,
    Expression<String>? json,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (displayName != null) 'display_name': displayName,
      if (json != null) 'json': json,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CharactersCompanion copyWith(
      {Value<String>? id,
      Value<String>? name,
      Value<String>? displayName,
      Value<String>? json,
      Value<DateTime>? updatedAt,
      Value<int>? rowid}) {
    return CharactersCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      displayName: displayName ?? this.displayName,
      json: json ?? this.json,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (displayName.present) {
      map['display_name'] = Variable<String>(displayName.value);
    }
    if (json.present) {
      map['json'] = Variable<String>(json.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CharactersCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('displayName: $displayName, ')
          ..write('json: $json, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $CharacterMetasTable extends CharacterMetas
    with TableInfo<$CharacterMetasTable, CharacterMeta> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CharacterMetasTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _keyMeta = const VerificationMeta('key');
  @override
  late final GeneratedColumn<String> key = GeneratedColumn<String>(
      'key', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _valueMeta = const VerificationMeta('value');
  @override
  late final GeneratedColumn<String> value = GeneratedColumn<String>(
      'value', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns => [key, value];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'character_metas';
  @override
  VerificationContext validateIntegrity(Insertable<CharacterMeta> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('key')) {
      context.handle(
          _keyMeta, key.isAcceptableOrUnknown(data['key']!, _keyMeta));
    } else if (isInserting) {
      context.missing(_keyMeta);
    }
    if (data.containsKey('value')) {
      context.handle(
          _valueMeta, value.isAcceptableOrUnknown(data['value']!, _valueMeta));
    } else if (isInserting) {
      context.missing(_valueMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {key};
  @override
  CharacterMeta map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CharacterMeta(
      key: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}key'])!,
      value: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}value'])!,
    );
  }

  @override
  $CharacterMetasTable createAlias(String alias) {
    return $CharacterMetasTable(attachedDatabase, alias);
  }
}

class CharacterMeta extends DataClass implements Insertable<CharacterMeta> {
  /// `deleted_default_ids` | `visibility_groups`
  final String key;

  /// JSON 字符串
  final String value;
  const CharacterMeta({required this.key, required this.value});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['key'] = Variable<String>(key);
    map['value'] = Variable<String>(value);
    return map;
  }

  CharacterMetasCompanion toCompanion(bool nullToAbsent) {
    return CharacterMetasCompanion(
      key: Value(key),
      value: Value(value),
    );
  }

  factory CharacterMeta.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CharacterMeta(
      key: serializer.fromJson<String>(json['key']),
      value: serializer.fromJson<String>(json['value']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'key': serializer.toJson<String>(key),
      'value': serializer.toJson<String>(value),
    };
  }

  CharacterMeta copyWith({String? key, String? value}) => CharacterMeta(
        key: key ?? this.key,
        value: value ?? this.value,
      );
  CharacterMeta copyWithCompanion(CharacterMetasCompanion data) {
    return CharacterMeta(
      key: data.key.present ? data.key.value : this.key,
      value: data.value.present ? data.value.value : this.value,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CharacterMeta(')
          ..write('key: $key, ')
          ..write('value: $value')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(key, value);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CharacterMeta &&
          other.key == this.key &&
          other.value == this.value);
}

class CharacterMetasCompanion extends UpdateCompanion<CharacterMeta> {
  final Value<String> key;
  final Value<String> value;
  final Value<int> rowid;
  const CharacterMetasCompanion({
    this.key = const Value.absent(),
    this.value = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CharacterMetasCompanion.insert({
    required String key,
    required String value,
    this.rowid = const Value.absent(),
  })  : key = Value(key),
        value = Value(value);
  static Insertable<CharacterMeta> custom({
    Expression<String>? key,
    Expression<String>? value,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (key != null) 'key': key,
      if (value != null) 'value': value,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CharacterMetasCompanion copyWith(
      {Value<String>? key, Value<String>? value, Value<int>? rowid}) {
    return CharacterMetasCompanion(
      key: key ?? this.key,
      value: value ?? this.value,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (key.present) {
      map['key'] = Variable<String>(key.value);
    }
    if (value.present) {
      map['value'] = Variable<String>(value.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CharacterMetasCompanion(')
          ..write('key: $key, ')
          ..write('value: $value, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ConversationsTable extends Conversations
    with TableInfo<$ConversationsTable, Conversation> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ConversationsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _characterIdMeta =
      const VerificationMeta('characterId');
  @override
  late final GeneratedColumn<String> characterId = GeneratedColumn<String>(
      'character_id', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant(''));
  static const VerificationMeta _characterNameMeta =
      const VerificationMeta('characterName');
  @override
  late final GeneratedColumn<String> characterName = GeneratedColumn<String>(
      'character_name', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant(''));
  static const VerificationMeta _jsonMeta = const VerificationMeta('json');
  @override
  late final GeneratedColumn<String> json = GeneratedColumn<String>(
      'json', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _lastMessageMeta =
      const VerificationMeta('lastMessage');
  @override
  late final GeneratedColumn<String> lastMessage = GeneratedColumn<String>(
      'last_message', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant(''));
  static const VerificationMeta _lastMessageTimeMeta =
      const VerificationMeta('lastMessageTime');
  @override
  late final GeneratedColumn<DateTime> lastMessageTime =
      GeneratedColumn<DateTime>('last_message_time', aliasedName, false,
          type: DriftSqlType.dateTime,
          requiredDuringInsert: false,
          defaultValue: currentDateAndTime);
  static const VerificationMeta _unreadCountMeta =
      const VerificationMeta('unreadCount');
  @override
  late final GeneratedColumn<int> unreadCount = GeneratedColumn<int>(
      'unread_count', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  static const VerificationMeta _pinnedMeta = const VerificationMeta('pinned');
  @override
  late final GeneratedColumn<bool> pinned = GeneratedColumn<bool>(
      'pinned', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('CHECK ("pinned" IN (0, 1))'),
      defaultValue: const Constant(false));
  @override
  List<GeneratedColumn> get $columns => [
        id,
        characterId,
        characterName,
        json,
        lastMessage,
        lastMessageTime,
        unreadCount,
        pinned
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'conversations';
  @override
  VerificationContext validateIntegrity(Insertable<Conversation> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('character_id')) {
      context.handle(
          _characterIdMeta,
          characterId.isAcceptableOrUnknown(
              data['character_id']!, _characterIdMeta));
    }
    if (data.containsKey('character_name')) {
      context.handle(
          _characterNameMeta,
          characterName.isAcceptableOrUnknown(
              data['character_name']!, _characterNameMeta));
    }
    if (data.containsKey('json')) {
      context.handle(
          _jsonMeta, json.isAcceptableOrUnknown(data['json']!, _jsonMeta));
    } else if (isInserting) {
      context.missing(_jsonMeta);
    }
    if (data.containsKey('last_message')) {
      context.handle(
          _lastMessageMeta,
          lastMessage.isAcceptableOrUnknown(
              data['last_message']!, _lastMessageMeta));
    }
    if (data.containsKey('last_message_time')) {
      context.handle(
          _lastMessageTimeMeta,
          lastMessageTime.isAcceptableOrUnknown(
              data['last_message_time']!, _lastMessageTimeMeta));
    }
    if (data.containsKey('unread_count')) {
      context.handle(
          _unreadCountMeta,
          unreadCount.isAcceptableOrUnknown(
              data['unread_count']!, _unreadCountMeta));
    }
    if (data.containsKey('pinned')) {
      context.handle(_pinnedMeta,
          pinned.isAcceptableOrUnknown(data['pinned']!, _pinnedMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Conversation map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Conversation(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      characterId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}character_id'])!,
      characterName: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}character_name'])!,
      json: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}json'])!,
      lastMessage: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}last_message'])!,
      lastMessageTime: attachedDatabase.typeMapping.read(
          DriftSqlType.dateTime, data['${effectivePrefix}last_message_time'])!,
      unreadCount: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}unread_count'])!,
      pinned: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}pinned'])!,
    );
  }

  @override
  $ConversationsTable createAlias(String alias) {
    return $ConversationsTable(attachedDatabase, alias);
  }
}

class Conversation extends DataClass implements Insertable<Conversation> {
  final String id;
  final String characterId;
  final String characterName;

  /// Conversation.toJson() 完整 JSON
  final String json;
  final String lastMessage;
  final DateTime lastMessageTime;
  final int unreadCount;
  final bool pinned;
  const Conversation(
      {required this.id,
      required this.characterId,
      required this.characterName,
      required this.json,
      required this.lastMessage,
      required this.lastMessageTime,
      required this.unreadCount,
      required this.pinned});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['character_id'] = Variable<String>(characterId);
    map['character_name'] = Variable<String>(characterName);
    map['json'] = Variable<String>(json);
    map['last_message'] = Variable<String>(lastMessage);
    map['last_message_time'] = Variable<DateTime>(lastMessageTime);
    map['unread_count'] = Variable<int>(unreadCount);
    map['pinned'] = Variable<bool>(pinned);
    return map;
  }

  ConversationsCompanion toCompanion(bool nullToAbsent) {
    return ConversationsCompanion(
      id: Value(id),
      characterId: Value(characterId),
      characterName: Value(characterName),
      json: Value(json),
      lastMessage: Value(lastMessage),
      lastMessageTime: Value(lastMessageTime),
      unreadCount: Value(unreadCount),
      pinned: Value(pinned),
    );
  }

  factory Conversation.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Conversation(
      id: serializer.fromJson<String>(json['id']),
      characterId: serializer.fromJson<String>(json['characterId']),
      characterName: serializer.fromJson<String>(json['characterName']),
      json: serializer.fromJson<String>(json['json']),
      lastMessage: serializer.fromJson<String>(json['lastMessage']),
      lastMessageTime: serializer.fromJson<DateTime>(json['lastMessageTime']),
      unreadCount: serializer.fromJson<int>(json['unreadCount']),
      pinned: serializer.fromJson<bool>(json['pinned']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'characterId': serializer.toJson<String>(characterId),
      'characterName': serializer.toJson<String>(characterName),
      'json': serializer.toJson<String>(json),
      'lastMessage': serializer.toJson<String>(lastMessage),
      'lastMessageTime': serializer.toJson<DateTime>(lastMessageTime),
      'unreadCount': serializer.toJson<int>(unreadCount),
      'pinned': serializer.toJson<bool>(pinned),
    };
  }

  Conversation copyWith(
          {String? id,
          String? characterId,
          String? characterName,
          String? json,
          String? lastMessage,
          DateTime? lastMessageTime,
          int? unreadCount,
          bool? pinned}) =>
      Conversation(
        id: id ?? this.id,
        characterId: characterId ?? this.characterId,
        characterName: characterName ?? this.characterName,
        json: json ?? this.json,
        lastMessage: lastMessage ?? this.lastMessage,
        lastMessageTime: lastMessageTime ?? this.lastMessageTime,
        unreadCount: unreadCount ?? this.unreadCount,
        pinned: pinned ?? this.pinned,
      );
  Conversation copyWithCompanion(ConversationsCompanion data) {
    return Conversation(
      id: data.id.present ? data.id.value : this.id,
      characterId:
          data.characterId.present ? data.characterId.value : this.characterId,
      characterName: data.characterName.present
          ? data.characterName.value
          : this.characterName,
      json: data.json.present ? data.json.value : this.json,
      lastMessage:
          data.lastMessage.present ? data.lastMessage.value : this.lastMessage,
      lastMessageTime: data.lastMessageTime.present
          ? data.lastMessageTime.value
          : this.lastMessageTime,
      unreadCount:
          data.unreadCount.present ? data.unreadCount.value : this.unreadCount,
      pinned: data.pinned.present ? data.pinned.value : this.pinned,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Conversation(')
          ..write('id: $id, ')
          ..write('characterId: $characterId, ')
          ..write('characterName: $characterName, ')
          ..write('json: $json, ')
          ..write('lastMessage: $lastMessage, ')
          ..write('lastMessageTime: $lastMessageTime, ')
          ..write('unreadCount: $unreadCount, ')
          ..write('pinned: $pinned')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, characterId, characterName, json,
      lastMessage, lastMessageTime, unreadCount, pinned);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Conversation &&
          other.id == this.id &&
          other.characterId == this.characterId &&
          other.characterName == this.characterName &&
          other.json == this.json &&
          other.lastMessage == this.lastMessage &&
          other.lastMessageTime == this.lastMessageTime &&
          other.unreadCount == this.unreadCount &&
          other.pinned == this.pinned);
}

class ConversationsCompanion extends UpdateCompanion<Conversation> {
  final Value<String> id;
  final Value<String> characterId;
  final Value<String> characterName;
  final Value<String> json;
  final Value<String> lastMessage;
  final Value<DateTime> lastMessageTime;
  final Value<int> unreadCount;
  final Value<bool> pinned;
  final Value<int> rowid;
  const ConversationsCompanion({
    this.id = const Value.absent(),
    this.characterId = const Value.absent(),
    this.characterName = const Value.absent(),
    this.json = const Value.absent(),
    this.lastMessage = const Value.absent(),
    this.lastMessageTime = const Value.absent(),
    this.unreadCount = const Value.absent(),
    this.pinned = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ConversationsCompanion.insert({
    required String id,
    this.characterId = const Value.absent(),
    this.characterName = const Value.absent(),
    required String json,
    this.lastMessage = const Value.absent(),
    this.lastMessageTime = const Value.absent(),
    this.unreadCount = const Value.absent(),
    this.pinned = const Value.absent(),
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        json = Value(json);
  static Insertable<Conversation> custom({
    Expression<String>? id,
    Expression<String>? characterId,
    Expression<String>? characterName,
    Expression<String>? json,
    Expression<String>? lastMessage,
    Expression<DateTime>? lastMessageTime,
    Expression<int>? unreadCount,
    Expression<bool>? pinned,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (characterId != null) 'character_id': characterId,
      if (characterName != null) 'character_name': characterName,
      if (json != null) 'json': json,
      if (lastMessage != null) 'last_message': lastMessage,
      if (lastMessageTime != null) 'last_message_time': lastMessageTime,
      if (unreadCount != null) 'unread_count': unreadCount,
      if (pinned != null) 'pinned': pinned,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ConversationsCompanion copyWith(
      {Value<String>? id,
      Value<String>? characterId,
      Value<String>? characterName,
      Value<String>? json,
      Value<String>? lastMessage,
      Value<DateTime>? lastMessageTime,
      Value<int>? unreadCount,
      Value<bool>? pinned,
      Value<int>? rowid}) {
    return ConversationsCompanion(
      id: id ?? this.id,
      characterId: characterId ?? this.characterId,
      characterName: characterName ?? this.characterName,
      json: json ?? this.json,
      lastMessage: lastMessage ?? this.lastMessage,
      lastMessageTime: lastMessageTime ?? this.lastMessageTime,
      unreadCount: unreadCount ?? this.unreadCount,
      pinned: pinned ?? this.pinned,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (characterId.present) {
      map['character_id'] = Variable<String>(characterId.value);
    }
    if (characterName.present) {
      map['character_name'] = Variable<String>(characterName.value);
    }
    if (json.present) {
      map['json'] = Variable<String>(json.value);
    }
    if (lastMessage.present) {
      map['last_message'] = Variable<String>(lastMessage.value);
    }
    if (lastMessageTime.present) {
      map['last_message_time'] = Variable<DateTime>(lastMessageTime.value);
    }
    if (unreadCount.present) {
      map['unread_count'] = Variable<int>(unreadCount.value);
    }
    if (pinned.present) {
      map['pinned'] = Variable<bool>(pinned.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ConversationsCompanion(')
          ..write('id: $id, ')
          ..write('characterId: $characterId, ')
          ..write('characterName: $characterName, ')
          ..write('json: $json, ')
          ..write('lastMessage: $lastMessage, ')
          ..write('lastMessageTime: $lastMessageTime, ')
          ..write('unreadCount: $unreadCount, ')
          ..write('pinned: $pinned, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $MessagesTable extends Messages with TableInfo<$MessagesTable, Message> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $MessagesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _conversationIdMeta =
      const VerificationMeta('conversationId');
  @override
  late final GeneratedColumn<String> conversationId = GeneratedColumn<String>(
      'conversation_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _jsonMeta = const VerificationMeta('json');
  @override
  late final GeneratedColumn<String> json = GeneratedColumn<String>(
      'json', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _isFromUserMeta =
      const VerificationMeta('isFromUser');
  @override
  late final GeneratedColumn<bool> isFromUser = GeneratedColumn<bool>(
      'is_from_user', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints: GeneratedColumn.constraintIsAlways(
          'CHECK ("is_from_user" IN (0, 1))'),
      defaultValue: const Constant(false));
  static const VerificationMeta _typeMeta = const VerificationMeta('type');
  @override
  late final GeneratedColumn<String> type = GeneratedColumn<String>(
      'type', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant('text'));
  static const VerificationMeta _createdAtMeta =
      const VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
      'created_at', aliasedName, false,
      type: DriftSqlType.dateTime,
      requiredDuringInsert: false,
      defaultValue: currentDateAndTime);
  @override
  List<GeneratedColumn> get $columns =>
      [id, conversationId, json, isFromUser, type, createdAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'messages';
  @override
  VerificationContext validateIntegrity(Insertable<Message> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('conversation_id')) {
      context.handle(
          _conversationIdMeta,
          conversationId.isAcceptableOrUnknown(
              data['conversation_id']!, _conversationIdMeta));
    } else if (isInserting) {
      context.missing(_conversationIdMeta);
    }
    if (data.containsKey('json')) {
      context.handle(
          _jsonMeta, json.isAcceptableOrUnknown(data['json']!, _jsonMeta));
    } else if (isInserting) {
      context.missing(_jsonMeta);
    }
    if (data.containsKey('is_from_user')) {
      context.handle(
          _isFromUserMeta,
          isFromUser.isAcceptableOrUnknown(
              data['is_from_user']!, _isFromUserMeta));
    }
    if (data.containsKey('type')) {
      context.handle(
          _typeMeta, type.isAcceptableOrUnknown(data['type']!, _typeMeta));
    }
    if (data.containsKey('created_at')) {
      context.handle(_createdAtMeta,
          createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Message map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Message(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      conversationId: attachedDatabase.typeMapping.read(
          DriftSqlType.string, data['${effectivePrefix}conversation_id'])!,
      json: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}json'])!,
      isFromUser: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}is_from_user'])!,
      type: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}type'])!,
      createdAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}created_at'])!,
    );
  }

  @override
  $MessagesTable createAlias(String alias) {
    return $MessagesTable(attachedDatabase, alias);
  }
}

class Message extends DataClass implements Insertable<Message> {
  final String id;
  final String conversationId;

  /// Message.toJson() 完整 JSON
  final String json;
  final bool isFromUser;
  final String type;
  final DateTime createdAt;
  const Message(
      {required this.id,
      required this.conversationId,
      required this.json,
      required this.isFromUser,
      required this.type,
      required this.createdAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['conversation_id'] = Variable<String>(conversationId);
    map['json'] = Variable<String>(json);
    map['is_from_user'] = Variable<bool>(isFromUser);
    map['type'] = Variable<String>(type);
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  MessagesCompanion toCompanion(bool nullToAbsent) {
    return MessagesCompanion(
      id: Value(id),
      conversationId: Value(conversationId),
      json: Value(json),
      isFromUser: Value(isFromUser),
      type: Value(type),
      createdAt: Value(createdAt),
    );
  }

  factory Message.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Message(
      id: serializer.fromJson<String>(json['id']),
      conversationId: serializer.fromJson<String>(json['conversationId']),
      json: serializer.fromJson<String>(json['json']),
      isFromUser: serializer.fromJson<bool>(json['isFromUser']),
      type: serializer.fromJson<String>(json['type']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'conversationId': serializer.toJson<String>(conversationId),
      'json': serializer.toJson<String>(json),
      'isFromUser': serializer.toJson<bool>(isFromUser),
      'type': serializer.toJson<String>(type),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  Message copyWith(
          {String? id,
          String? conversationId,
          String? json,
          bool? isFromUser,
          String? type,
          DateTime? createdAt}) =>
      Message(
        id: id ?? this.id,
        conversationId: conversationId ?? this.conversationId,
        json: json ?? this.json,
        isFromUser: isFromUser ?? this.isFromUser,
        type: type ?? this.type,
        createdAt: createdAt ?? this.createdAt,
      );
  Message copyWithCompanion(MessagesCompanion data) {
    return Message(
      id: data.id.present ? data.id.value : this.id,
      conversationId: data.conversationId.present
          ? data.conversationId.value
          : this.conversationId,
      json: data.json.present ? data.json.value : this.json,
      isFromUser:
          data.isFromUser.present ? data.isFromUser.value : this.isFromUser,
      type: data.type.present ? data.type.value : this.type,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Message(')
          ..write('id: $id, ')
          ..write('conversationId: $conversationId, ')
          ..write('json: $json, ')
          ..write('isFromUser: $isFromUser, ')
          ..write('type: $type, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, conversationId, json, isFromUser, type, createdAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Message &&
          other.id == this.id &&
          other.conversationId == this.conversationId &&
          other.json == this.json &&
          other.isFromUser == this.isFromUser &&
          other.type == this.type &&
          other.createdAt == this.createdAt);
}

class MessagesCompanion extends UpdateCompanion<Message> {
  final Value<String> id;
  final Value<String> conversationId;
  final Value<String> json;
  final Value<bool> isFromUser;
  final Value<String> type;
  final Value<DateTime> createdAt;
  final Value<int> rowid;
  const MessagesCompanion({
    this.id = const Value.absent(),
    this.conversationId = const Value.absent(),
    this.json = const Value.absent(),
    this.isFromUser = const Value.absent(),
    this.type = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  MessagesCompanion.insert({
    required String id,
    required String conversationId,
    required String json,
    this.isFromUser = const Value.absent(),
    this.type = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        conversationId = Value(conversationId),
        json = Value(json);
  static Insertable<Message> custom({
    Expression<String>? id,
    Expression<String>? conversationId,
    Expression<String>? json,
    Expression<bool>? isFromUser,
    Expression<String>? type,
    Expression<DateTime>? createdAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (conversationId != null) 'conversation_id': conversationId,
      if (json != null) 'json': json,
      if (isFromUser != null) 'is_from_user': isFromUser,
      if (type != null) 'type': type,
      if (createdAt != null) 'created_at': createdAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  MessagesCompanion copyWith(
      {Value<String>? id,
      Value<String>? conversationId,
      Value<String>? json,
      Value<bool>? isFromUser,
      Value<String>? type,
      Value<DateTime>? createdAt,
      Value<int>? rowid}) {
    return MessagesCompanion(
      id: id ?? this.id,
      conversationId: conversationId ?? this.conversationId,
      json: json ?? this.json,
      isFromUser: isFromUser ?? this.isFromUser,
      type: type ?? this.type,
      createdAt: createdAt ?? this.createdAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (conversationId.present) {
      map['conversation_id'] = Variable<String>(conversationId.value);
    }
    if (json.present) {
      map['json'] = Variable<String>(json.value);
    }
    if (isFromUser.present) {
      map['is_from_user'] = Variable<bool>(isFromUser.value);
    }
    if (type.present) {
      map['type'] = Variable<String>(type.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('MessagesCompanion(')
          ..write('id: $id, ')
          ..write('conversationId: $conversationId, ')
          ..write('json: $json, ')
          ..write('isFromUser: $isFromUser, ')
          ..write('type: $type, ')
          ..write('createdAt: $createdAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ChatMetasTable extends ChatMetas
    with TableInfo<$ChatMetasTable, ChatMeta> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ChatMetasTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _keyMeta = const VerificationMeta('key');
  @override
  late final GeneratedColumn<String> key = GeneratedColumn<String>(
      'key', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _valueMeta = const VerificationMeta('value');
  @override
  late final GeneratedColumn<String> value = GeneratedColumn<String>(
      'value', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns => [key, value];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'chat_metas';
  @override
  VerificationContext validateIntegrity(Insertable<ChatMeta> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('key')) {
      context.handle(
          _keyMeta, key.isAcceptableOrUnknown(data['key']!, _keyMeta));
    } else if (isInserting) {
      context.missing(_keyMeta);
    }
    if (data.containsKey('value')) {
      context.handle(
          _valueMeta, value.isAcceptableOrUnknown(data['value']!, _valueMeta));
    } else if (isInserting) {
      context.missing(_valueMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {key};
  @override
  ChatMeta map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ChatMeta(
      key: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}key'])!,
      value: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}value'])!,
    );
  }

  @override
  $ChatMetasTable createAlias(String alias) {
    return $ChatMetasTable(attachedDatabase, alias);
  }
}

class ChatMeta extends DataClass implements Insertable<ChatMeta> {
  /// `context_tokens` | `system_tokens` | `roleplay_choices`
  final String key;
  final String value;
  const ChatMeta({required this.key, required this.value});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['key'] = Variable<String>(key);
    map['value'] = Variable<String>(value);
    return map;
  }

  ChatMetasCompanion toCompanion(bool nullToAbsent) {
    return ChatMetasCompanion(
      key: Value(key),
      value: Value(value),
    );
  }

  factory ChatMeta.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ChatMeta(
      key: serializer.fromJson<String>(json['key']),
      value: serializer.fromJson<String>(json['value']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'key': serializer.toJson<String>(key),
      'value': serializer.toJson<String>(value),
    };
  }

  ChatMeta copyWith({String? key, String? value}) => ChatMeta(
        key: key ?? this.key,
        value: value ?? this.value,
      );
  ChatMeta copyWithCompanion(ChatMetasCompanion data) {
    return ChatMeta(
      key: data.key.present ? data.key.value : this.key,
      value: data.value.present ? data.value.value : this.value,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ChatMeta(')
          ..write('key: $key, ')
          ..write('value: $value')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(key, value);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ChatMeta && other.key == this.key && other.value == this.value);
}

class ChatMetasCompanion extends UpdateCompanion<ChatMeta> {
  final Value<String> key;
  final Value<String> value;
  final Value<int> rowid;
  const ChatMetasCompanion({
    this.key = const Value.absent(),
    this.value = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ChatMetasCompanion.insert({
    required String key,
    required String value,
    this.rowid = const Value.absent(),
  })  : key = Value(key),
        value = Value(value);
  static Insertable<ChatMeta> custom({
    Expression<String>? key,
    Expression<String>? value,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (key != null) 'key': key,
      if (value != null) 'value': value,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ChatMetasCompanion copyWith(
      {Value<String>? key, Value<String>? value, Value<int>? rowid}) {
    return ChatMetasCompanion(
      key: key ?? this.key,
      value: value ?? this.value,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (key.present) {
      map['key'] = Variable<String>(key.value);
    }
    if (value.present) {
      map['value'] = Variable<String>(value.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ChatMetasCompanion(')
          ..write('key: $key, ')
          ..write('value: $value, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $MigrationFlagsTable extends MigrationFlags
    with TableInfo<$MigrationFlagsTable, MigrationFlag> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $MigrationFlagsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
      'name', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _completedAtMeta =
      const VerificationMeta('completedAt');
  @override
  late final GeneratedColumn<DateTime> completedAt = GeneratedColumn<DateTime>(
      'completed_at', aliasedName, false,
      type: DriftSqlType.dateTime,
      requiredDuringInsert: false,
      defaultValue: currentDateAndTime);
  @override
  List<GeneratedColumn> get $columns => [name, completedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'migration_flags';
  @override
  VerificationContext validateIntegrity(Insertable<MigrationFlag> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('name')) {
      context.handle(
          _nameMeta, name.isAcceptableOrUnknown(data['name']!, _nameMeta));
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('completed_at')) {
      context.handle(
          _completedAtMeta,
          completedAt.isAcceptableOrUnknown(
              data['completed_at']!, _completedAtMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {name};
  @override
  MigrationFlag map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return MigrationFlag(
      name: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}name'])!,
      completedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}completed_at'])!,
    );
  }

  @override
  $MigrationFlagsTable createAlias(String alias) {
    return $MigrationFlagsTable(attachedDatabase, alias);
  }
}

class MigrationFlag extends DataClass implements Insertable<MigrationFlag> {
  /// 如 `prefs_to_sqlite_v1`
  final String name;
  final DateTime completedAt;
  const MigrationFlag({required this.name, required this.completedAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['name'] = Variable<String>(name);
    map['completed_at'] = Variable<DateTime>(completedAt);
    return map;
  }

  MigrationFlagsCompanion toCompanion(bool nullToAbsent) {
    return MigrationFlagsCompanion(
      name: Value(name),
      completedAt: Value(completedAt),
    );
  }

  factory MigrationFlag.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return MigrationFlag(
      name: serializer.fromJson<String>(json['name']),
      completedAt: serializer.fromJson<DateTime>(json['completedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'name': serializer.toJson<String>(name),
      'completedAt': serializer.toJson<DateTime>(completedAt),
    };
  }

  MigrationFlag copyWith({String? name, DateTime? completedAt}) =>
      MigrationFlag(
        name: name ?? this.name,
        completedAt: completedAt ?? this.completedAt,
      );
  MigrationFlag copyWithCompanion(MigrationFlagsCompanion data) {
    return MigrationFlag(
      name: data.name.present ? data.name.value : this.name,
      completedAt:
          data.completedAt.present ? data.completedAt.value : this.completedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('MigrationFlag(')
          ..write('name: $name, ')
          ..write('completedAt: $completedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(name, completedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is MigrationFlag &&
          other.name == this.name &&
          other.completedAt == this.completedAt);
}

class MigrationFlagsCompanion extends UpdateCompanion<MigrationFlag> {
  final Value<String> name;
  final Value<DateTime> completedAt;
  final Value<int> rowid;
  const MigrationFlagsCompanion({
    this.name = const Value.absent(),
    this.completedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  MigrationFlagsCompanion.insert({
    required String name,
    this.completedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : name = Value(name);
  static Insertable<MigrationFlag> custom({
    Expression<String>? name,
    Expression<DateTime>? completedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (name != null) 'name': name,
      if (completedAt != null) 'completed_at': completedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  MigrationFlagsCompanion copyWith(
      {Value<String>? name, Value<DateTime>? completedAt, Value<int>? rowid}) {
    return MigrationFlagsCompanion(
      name: name ?? this.name,
      completedAt: completedAt ?? this.completedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (completedAt.present) {
      map['completed_at'] = Variable<DateTime>(completedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('MigrationFlagsCompanion(')
          ..write('name: $name, ')
          ..write('completedAt: $completedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $CharactersTable characters = $CharactersTable(this);
  late final $CharacterMetasTable characterMetas = $CharacterMetasTable(this);
  late final $ConversationsTable conversations = $ConversationsTable(this);
  late final $MessagesTable messages = $MessagesTable(this);
  late final $ChatMetasTable chatMetas = $ChatMetasTable(this);
  late final $MigrationFlagsTable migrationFlags = $MigrationFlagsTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
        characters,
        characterMetas,
        conversations,
        messages,
        chatMetas,
        migrationFlags
      ];
}

typedef $$CharactersTableCreateCompanionBuilder = CharactersCompanion Function({
  required String id,
  Value<String> name,
  Value<String> displayName,
  required String json,
  Value<DateTime> updatedAt,
  Value<int> rowid,
});
typedef $$CharactersTableUpdateCompanionBuilder = CharactersCompanion Function({
  Value<String> id,
  Value<String> name,
  Value<String> displayName,
  Value<String> json,
  Value<DateTime> updatedAt,
  Value<int> rowid,
});

class $$CharactersTableFilterComposer
    extends Composer<_$AppDatabase, $CharactersTable> {
  $$CharactersTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get name => $composableBuilder(
      column: $table.name, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get displayName => $composableBuilder(
      column: $table.displayName, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get json => $composableBuilder(
      column: $table.json, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnFilters(column));
}

class $$CharactersTableOrderingComposer
    extends Composer<_$AppDatabase, $CharactersTable> {
  $$CharactersTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get name => $composableBuilder(
      column: $table.name, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get displayName => $composableBuilder(
      column: $table.displayName, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get json => $composableBuilder(
      column: $table.json, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnOrderings(column));
}

class $$CharactersTableAnnotationComposer
    extends Composer<_$AppDatabase, $CharactersTable> {
  $$CharactersTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get displayName => $composableBuilder(
      column: $table.displayName, builder: (column) => column);

  GeneratedColumn<String> get json =>
      $composableBuilder(column: $table.json, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$CharactersTableTableManager extends RootTableManager<
    _$AppDatabase,
    $CharactersTable,
    Character,
    $$CharactersTableFilterComposer,
    $$CharactersTableOrderingComposer,
    $$CharactersTableAnnotationComposer,
    $$CharactersTableCreateCompanionBuilder,
    $$CharactersTableUpdateCompanionBuilder,
    (Character, BaseReferences<_$AppDatabase, $CharactersTable, Character>),
    Character,
    PrefetchHooks Function()> {
  $$CharactersTableTableManager(_$AppDatabase db, $CharactersTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CharactersTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CharactersTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CharactersTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String> name = const Value.absent(),
            Value<String> displayName = const Value.absent(),
            Value<String> json = const Value.absent(),
            Value<DateTime> updatedAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              CharactersCompanion(
            id: id,
            name: name,
            displayName: displayName,
            json: json,
            updatedAt: updatedAt,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            Value<String> name = const Value.absent(),
            Value<String> displayName = const Value.absent(),
            required String json,
            Value<DateTime> updatedAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              CharactersCompanion.insert(
            id: id,
            name: name,
            displayName: displayName,
            json: json,
            updatedAt: updatedAt,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$CharactersTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $CharactersTable,
    Character,
    $$CharactersTableFilterComposer,
    $$CharactersTableOrderingComposer,
    $$CharactersTableAnnotationComposer,
    $$CharactersTableCreateCompanionBuilder,
    $$CharactersTableUpdateCompanionBuilder,
    (Character, BaseReferences<_$AppDatabase, $CharactersTable, Character>),
    Character,
    PrefetchHooks Function()>;
typedef $$CharacterMetasTableCreateCompanionBuilder = CharacterMetasCompanion
    Function({
  required String key,
  required String value,
  Value<int> rowid,
});
typedef $$CharacterMetasTableUpdateCompanionBuilder = CharacterMetasCompanion
    Function({
  Value<String> key,
  Value<String> value,
  Value<int> rowid,
});

class $$CharacterMetasTableFilterComposer
    extends Composer<_$AppDatabase, $CharacterMetasTable> {
  $$CharacterMetasTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get key => $composableBuilder(
      column: $table.key, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get value => $composableBuilder(
      column: $table.value, builder: (column) => ColumnFilters(column));
}

class $$CharacterMetasTableOrderingComposer
    extends Composer<_$AppDatabase, $CharacterMetasTable> {
  $$CharacterMetasTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get key => $composableBuilder(
      column: $table.key, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get value => $composableBuilder(
      column: $table.value, builder: (column) => ColumnOrderings(column));
}

class $$CharacterMetasTableAnnotationComposer
    extends Composer<_$AppDatabase, $CharacterMetasTable> {
  $$CharacterMetasTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get key =>
      $composableBuilder(column: $table.key, builder: (column) => column);

  GeneratedColumn<String> get value =>
      $composableBuilder(column: $table.value, builder: (column) => column);
}

class $$CharacterMetasTableTableManager extends RootTableManager<
    _$AppDatabase,
    $CharacterMetasTable,
    CharacterMeta,
    $$CharacterMetasTableFilterComposer,
    $$CharacterMetasTableOrderingComposer,
    $$CharacterMetasTableAnnotationComposer,
    $$CharacterMetasTableCreateCompanionBuilder,
    $$CharacterMetasTableUpdateCompanionBuilder,
    (
      CharacterMeta,
      BaseReferences<_$AppDatabase, $CharacterMetasTable, CharacterMeta>
    ),
    CharacterMeta,
    PrefetchHooks Function()> {
  $$CharacterMetasTableTableManager(
      _$AppDatabase db, $CharacterMetasTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CharacterMetasTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CharacterMetasTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CharacterMetasTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> key = const Value.absent(),
            Value<String> value = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              CharacterMetasCompanion(
            key: key,
            value: value,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String key,
            required String value,
            Value<int> rowid = const Value.absent(),
          }) =>
              CharacterMetasCompanion.insert(
            key: key,
            value: value,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$CharacterMetasTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $CharacterMetasTable,
    CharacterMeta,
    $$CharacterMetasTableFilterComposer,
    $$CharacterMetasTableOrderingComposer,
    $$CharacterMetasTableAnnotationComposer,
    $$CharacterMetasTableCreateCompanionBuilder,
    $$CharacterMetasTableUpdateCompanionBuilder,
    (
      CharacterMeta,
      BaseReferences<_$AppDatabase, $CharacterMetasTable, CharacterMeta>
    ),
    CharacterMeta,
    PrefetchHooks Function()>;
typedef $$ConversationsTableCreateCompanionBuilder = ConversationsCompanion
    Function({
  required String id,
  Value<String> characterId,
  Value<String> characterName,
  required String json,
  Value<String> lastMessage,
  Value<DateTime> lastMessageTime,
  Value<int> unreadCount,
  Value<bool> pinned,
  Value<int> rowid,
});
typedef $$ConversationsTableUpdateCompanionBuilder = ConversationsCompanion
    Function({
  Value<String> id,
  Value<String> characterId,
  Value<String> characterName,
  Value<String> json,
  Value<String> lastMessage,
  Value<DateTime> lastMessageTime,
  Value<int> unreadCount,
  Value<bool> pinned,
  Value<int> rowid,
});

class $$ConversationsTableFilterComposer
    extends Composer<_$AppDatabase, $ConversationsTable> {
  $$ConversationsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get characterId => $composableBuilder(
      column: $table.characterId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get characterName => $composableBuilder(
      column: $table.characterName, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get json => $composableBuilder(
      column: $table.json, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get lastMessage => $composableBuilder(
      column: $table.lastMessage, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get lastMessageTime => $composableBuilder(
      column: $table.lastMessageTime,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get unreadCount => $composableBuilder(
      column: $table.unreadCount, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get pinned => $composableBuilder(
      column: $table.pinned, builder: (column) => ColumnFilters(column));
}

class $$ConversationsTableOrderingComposer
    extends Composer<_$AppDatabase, $ConversationsTable> {
  $$ConversationsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get characterId => $composableBuilder(
      column: $table.characterId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get characterName => $composableBuilder(
      column: $table.characterName,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get json => $composableBuilder(
      column: $table.json, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get lastMessage => $composableBuilder(
      column: $table.lastMessage, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get lastMessageTime => $composableBuilder(
      column: $table.lastMessageTime,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get unreadCount => $composableBuilder(
      column: $table.unreadCount, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get pinned => $composableBuilder(
      column: $table.pinned, builder: (column) => ColumnOrderings(column));
}

class $$ConversationsTableAnnotationComposer
    extends Composer<_$AppDatabase, $ConversationsTable> {
  $$ConversationsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get characterId => $composableBuilder(
      column: $table.characterId, builder: (column) => column);

  GeneratedColumn<String> get characterName => $composableBuilder(
      column: $table.characterName, builder: (column) => column);

  GeneratedColumn<String> get json =>
      $composableBuilder(column: $table.json, builder: (column) => column);

  GeneratedColumn<String> get lastMessage => $composableBuilder(
      column: $table.lastMessage, builder: (column) => column);

  GeneratedColumn<DateTime> get lastMessageTime => $composableBuilder(
      column: $table.lastMessageTime, builder: (column) => column);

  GeneratedColumn<int> get unreadCount => $composableBuilder(
      column: $table.unreadCount, builder: (column) => column);

  GeneratedColumn<bool> get pinned =>
      $composableBuilder(column: $table.pinned, builder: (column) => column);
}

class $$ConversationsTableTableManager extends RootTableManager<
    _$AppDatabase,
    $ConversationsTable,
    Conversation,
    $$ConversationsTableFilterComposer,
    $$ConversationsTableOrderingComposer,
    $$ConversationsTableAnnotationComposer,
    $$ConversationsTableCreateCompanionBuilder,
    $$ConversationsTableUpdateCompanionBuilder,
    (
      Conversation,
      BaseReferences<_$AppDatabase, $ConversationsTable, Conversation>
    ),
    Conversation,
    PrefetchHooks Function()> {
  $$ConversationsTableTableManager(_$AppDatabase db, $ConversationsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ConversationsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ConversationsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ConversationsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String> characterId = const Value.absent(),
            Value<String> characterName = const Value.absent(),
            Value<String> json = const Value.absent(),
            Value<String> lastMessage = const Value.absent(),
            Value<DateTime> lastMessageTime = const Value.absent(),
            Value<int> unreadCount = const Value.absent(),
            Value<bool> pinned = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              ConversationsCompanion(
            id: id,
            characterId: characterId,
            characterName: characterName,
            json: json,
            lastMessage: lastMessage,
            lastMessageTime: lastMessageTime,
            unreadCount: unreadCount,
            pinned: pinned,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            Value<String> characterId = const Value.absent(),
            Value<String> characterName = const Value.absent(),
            required String json,
            Value<String> lastMessage = const Value.absent(),
            Value<DateTime> lastMessageTime = const Value.absent(),
            Value<int> unreadCount = const Value.absent(),
            Value<bool> pinned = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              ConversationsCompanion.insert(
            id: id,
            characterId: characterId,
            characterName: characterName,
            json: json,
            lastMessage: lastMessage,
            lastMessageTime: lastMessageTime,
            unreadCount: unreadCount,
            pinned: pinned,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$ConversationsTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $ConversationsTable,
    Conversation,
    $$ConversationsTableFilterComposer,
    $$ConversationsTableOrderingComposer,
    $$ConversationsTableAnnotationComposer,
    $$ConversationsTableCreateCompanionBuilder,
    $$ConversationsTableUpdateCompanionBuilder,
    (
      Conversation,
      BaseReferences<_$AppDatabase, $ConversationsTable, Conversation>
    ),
    Conversation,
    PrefetchHooks Function()>;
typedef $$MessagesTableCreateCompanionBuilder = MessagesCompanion Function({
  required String id,
  required String conversationId,
  required String json,
  Value<bool> isFromUser,
  Value<String> type,
  Value<DateTime> createdAt,
  Value<int> rowid,
});
typedef $$MessagesTableUpdateCompanionBuilder = MessagesCompanion Function({
  Value<String> id,
  Value<String> conversationId,
  Value<String> json,
  Value<bool> isFromUser,
  Value<String> type,
  Value<DateTime> createdAt,
  Value<int> rowid,
});

class $$MessagesTableFilterComposer
    extends Composer<_$AppDatabase, $MessagesTable> {
  $$MessagesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get conversationId => $composableBuilder(
      column: $table.conversationId,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get json => $composableBuilder(
      column: $table.json, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get isFromUser => $composableBuilder(
      column: $table.isFromUser, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get type => $composableBuilder(
      column: $table.type, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnFilters(column));
}

class $$MessagesTableOrderingComposer
    extends Composer<_$AppDatabase, $MessagesTable> {
  $$MessagesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get conversationId => $composableBuilder(
      column: $table.conversationId,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get json => $composableBuilder(
      column: $table.json, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get isFromUser => $composableBuilder(
      column: $table.isFromUser, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get type => $composableBuilder(
      column: $table.type, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnOrderings(column));
}

class $$MessagesTableAnnotationComposer
    extends Composer<_$AppDatabase, $MessagesTable> {
  $$MessagesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get conversationId => $composableBuilder(
      column: $table.conversationId, builder: (column) => column);

  GeneratedColumn<String> get json =>
      $composableBuilder(column: $table.json, builder: (column) => column);

  GeneratedColumn<bool> get isFromUser => $composableBuilder(
      column: $table.isFromUser, builder: (column) => column);

  GeneratedColumn<String> get type =>
      $composableBuilder(column: $table.type, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);
}

class $$MessagesTableTableManager extends RootTableManager<
    _$AppDatabase,
    $MessagesTable,
    Message,
    $$MessagesTableFilterComposer,
    $$MessagesTableOrderingComposer,
    $$MessagesTableAnnotationComposer,
    $$MessagesTableCreateCompanionBuilder,
    $$MessagesTableUpdateCompanionBuilder,
    (Message, BaseReferences<_$AppDatabase, $MessagesTable, Message>),
    Message,
    PrefetchHooks Function()> {
  $$MessagesTableTableManager(_$AppDatabase db, $MessagesTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$MessagesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$MessagesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$MessagesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String> conversationId = const Value.absent(),
            Value<String> json = const Value.absent(),
            Value<bool> isFromUser = const Value.absent(),
            Value<String> type = const Value.absent(),
            Value<DateTime> createdAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              MessagesCompanion(
            id: id,
            conversationId: conversationId,
            json: json,
            isFromUser: isFromUser,
            type: type,
            createdAt: createdAt,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            required String conversationId,
            required String json,
            Value<bool> isFromUser = const Value.absent(),
            Value<String> type = const Value.absent(),
            Value<DateTime> createdAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              MessagesCompanion.insert(
            id: id,
            conversationId: conversationId,
            json: json,
            isFromUser: isFromUser,
            type: type,
            createdAt: createdAt,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$MessagesTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $MessagesTable,
    Message,
    $$MessagesTableFilterComposer,
    $$MessagesTableOrderingComposer,
    $$MessagesTableAnnotationComposer,
    $$MessagesTableCreateCompanionBuilder,
    $$MessagesTableUpdateCompanionBuilder,
    (Message, BaseReferences<_$AppDatabase, $MessagesTable, Message>),
    Message,
    PrefetchHooks Function()>;
typedef $$ChatMetasTableCreateCompanionBuilder = ChatMetasCompanion Function({
  required String key,
  required String value,
  Value<int> rowid,
});
typedef $$ChatMetasTableUpdateCompanionBuilder = ChatMetasCompanion Function({
  Value<String> key,
  Value<String> value,
  Value<int> rowid,
});

class $$ChatMetasTableFilterComposer
    extends Composer<_$AppDatabase, $ChatMetasTable> {
  $$ChatMetasTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get key => $composableBuilder(
      column: $table.key, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get value => $composableBuilder(
      column: $table.value, builder: (column) => ColumnFilters(column));
}

class $$ChatMetasTableOrderingComposer
    extends Composer<_$AppDatabase, $ChatMetasTable> {
  $$ChatMetasTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get key => $composableBuilder(
      column: $table.key, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get value => $composableBuilder(
      column: $table.value, builder: (column) => ColumnOrderings(column));
}

class $$ChatMetasTableAnnotationComposer
    extends Composer<_$AppDatabase, $ChatMetasTable> {
  $$ChatMetasTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get key =>
      $composableBuilder(column: $table.key, builder: (column) => column);

  GeneratedColumn<String> get value =>
      $composableBuilder(column: $table.value, builder: (column) => column);
}

class $$ChatMetasTableTableManager extends RootTableManager<
    _$AppDatabase,
    $ChatMetasTable,
    ChatMeta,
    $$ChatMetasTableFilterComposer,
    $$ChatMetasTableOrderingComposer,
    $$ChatMetasTableAnnotationComposer,
    $$ChatMetasTableCreateCompanionBuilder,
    $$ChatMetasTableUpdateCompanionBuilder,
    (ChatMeta, BaseReferences<_$AppDatabase, $ChatMetasTable, ChatMeta>),
    ChatMeta,
    PrefetchHooks Function()> {
  $$ChatMetasTableTableManager(_$AppDatabase db, $ChatMetasTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ChatMetasTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ChatMetasTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ChatMetasTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> key = const Value.absent(),
            Value<String> value = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              ChatMetasCompanion(
            key: key,
            value: value,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String key,
            required String value,
            Value<int> rowid = const Value.absent(),
          }) =>
              ChatMetasCompanion.insert(
            key: key,
            value: value,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$ChatMetasTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $ChatMetasTable,
    ChatMeta,
    $$ChatMetasTableFilterComposer,
    $$ChatMetasTableOrderingComposer,
    $$ChatMetasTableAnnotationComposer,
    $$ChatMetasTableCreateCompanionBuilder,
    $$ChatMetasTableUpdateCompanionBuilder,
    (ChatMeta, BaseReferences<_$AppDatabase, $ChatMetasTable, ChatMeta>),
    ChatMeta,
    PrefetchHooks Function()>;
typedef $$MigrationFlagsTableCreateCompanionBuilder = MigrationFlagsCompanion
    Function({
  required String name,
  Value<DateTime> completedAt,
  Value<int> rowid,
});
typedef $$MigrationFlagsTableUpdateCompanionBuilder = MigrationFlagsCompanion
    Function({
  Value<String> name,
  Value<DateTime> completedAt,
  Value<int> rowid,
});

class $$MigrationFlagsTableFilterComposer
    extends Composer<_$AppDatabase, $MigrationFlagsTable> {
  $$MigrationFlagsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get name => $composableBuilder(
      column: $table.name, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get completedAt => $composableBuilder(
      column: $table.completedAt, builder: (column) => ColumnFilters(column));
}

class $$MigrationFlagsTableOrderingComposer
    extends Composer<_$AppDatabase, $MigrationFlagsTable> {
  $$MigrationFlagsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get name => $composableBuilder(
      column: $table.name, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get completedAt => $composableBuilder(
      column: $table.completedAt, builder: (column) => ColumnOrderings(column));
}

class $$MigrationFlagsTableAnnotationComposer
    extends Composer<_$AppDatabase, $MigrationFlagsTable> {
  $$MigrationFlagsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<DateTime> get completedAt => $composableBuilder(
      column: $table.completedAt, builder: (column) => column);
}

class $$MigrationFlagsTableTableManager extends RootTableManager<
    _$AppDatabase,
    $MigrationFlagsTable,
    MigrationFlag,
    $$MigrationFlagsTableFilterComposer,
    $$MigrationFlagsTableOrderingComposer,
    $$MigrationFlagsTableAnnotationComposer,
    $$MigrationFlagsTableCreateCompanionBuilder,
    $$MigrationFlagsTableUpdateCompanionBuilder,
    (
      MigrationFlag,
      BaseReferences<_$AppDatabase, $MigrationFlagsTable, MigrationFlag>
    ),
    MigrationFlag,
    PrefetchHooks Function()> {
  $$MigrationFlagsTableTableManager(
      _$AppDatabase db, $MigrationFlagsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$MigrationFlagsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$MigrationFlagsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$MigrationFlagsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> name = const Value.absent(),
            Value<DateTime> completedAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              MigrationFlagsCompanion(
            name: name,
            completedAt: completedAt,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String name,
            Value<DateTime> completedAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              MigrationFlagsCompanion.insert(
            name: name,
            completedAt: completedAt,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$MigrationFlagsTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $MigrationFlagsTable,
    MigrationFlag,
    $$MigrationFlagsTableFilterComposer,
    $$MigrationFlagsTableOrderingComposer,
    $$MigrationFlagsTableAnnotationComposer,
    $$MigrationFlagsTableCreateCompanionBuilder,
    $$MigrationFlagsTableUpdateCompanionBuilder,
    (
      MigrationFlag,
      BaseReferences<_$AppDatabase, $MigrationFlagsTable, MigrationFlag>
    ),
    MigrationFlag,
    PrefetchHooks Function()>;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$CharactersTableTableManager get characters =>
      $$CharactersTableTableManager(_db, _db.characters);
  $$CharacterMetasTableTableManager get characterMetas =>
      $$CharacterMetasTableTableManager(_db, _db.characterMetas);
  $$ConversationsTableTableManager get conversations =>
      $$ConversationsTableTableManager(_db, _db.conversations);
  $$MessagesTableTableManager get messages =>
      $$MessagesTableTableManager(_db, _db.messages);
  $$ChatMetasTableTableManager get chatMetas =>
      $$ChatMetasTableTableManager(_db, _db.chatMetas);
  $$MigrationFlagsTableTableManager get migrationFlags =>
      $$MigrationFlagsTableTableManager(_db, _db.migrationFlags);
}
