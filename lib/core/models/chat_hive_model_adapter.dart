import 'package:hive/hive.dart';
import 'chat_hive_model.dart';

class ChatHiveModelAdapter extends TypeAdapter<ChatHiveModel> {
  @override
  final int typeId = 1;

  @override
  ChatHiveModel read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return ChatHiveModel(
      id: fields[0] as String,
      type: fields[1] as String,
      name: fields[2] as String,
      profilePicture: fields[3] as String?,
      localImagePath: fields[14] as String?,
      lastMessage: fields[4] as String?,
      lastMessageTime: fields[5] as DateTime?,
      unreadCount: fields[6] as int,
      isPinned: fields[7] as bool,
      attendanceGroup: fields[8] as bool?,
      actualRole: fields[9] as String?,
      createdAt: fields[10] as DateTime,
      updatedAt: fields[11] as DateTime,
      lastReadAt: fields[12] as DateTime?,
      memberCount: fields[13] as int?,
      groupType: fields[15] as String?,
      role: fields[16] as String?,
      mobile: fields[17] as String?,
      className: fields[18] as String?,
      sectionName: fields[19] as String?,
      sortTime: fields[20] as DateTime?,
    );
  }

  @override
  void write(BinaryWriter writer, ChatHiveModel obj) {
    writer
      ..writeByte(21)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.type)
      ..writeByte(2)
      ..write(obj.name)
      ..writeByte(3)
      ..write(obj.profilePicture)
      ..writeByte(14)
      ..write(obj.localImagePath)
      ..writeByte(4)
      ..write(obj.lastMessage)
      ..writeByte(5)
      ..write(obj.lastMessageTime)
      ..writeByte(6)
      ..write(obj.unreadCount)
      ..writeByte(7)
      ..write(obj.isPinned)
      ..writeByte(8)
      ..write(obj.attendanceGroup)
      ..writeByte(9)
      ..write(obj.actualRole)
      ..writeByte(10)
      ..write(obj.createdAt)
      ..writeByte(11)
      ..write(obj.updatedAt)
      ..writeByte(12)
      ..write(obj.lastReadAt)
      ..writeByte(13)
      ..write(obj.memberCount)
      ..writeByte(15)
      ..write(obj.groupType)
      ..writeByte(16)
      ..write(obj.role)
      ..writeByte(17)
      ..write(obj.mobile)
      ..writeByte(18)
      ..write(obj.className)
      ..writeByte(19)
      ..write(obj.sectionName)
      ..writeByte(20)
      ..write(obj.sortTime);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ChatHiveModelAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
