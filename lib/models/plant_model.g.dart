// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'plant_model.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class PlantModelAdapter extends TypeAdapter<PlantModel> {
  @override
  final int typeId = 1;

  @override
  PlantModel read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return PlantModel(
      id: fields[0] as String,
      qrCode: fields[1] as String,
      species: fields[2] as String,
      gridId: fields[3] as String?,
      gridName: fields[4] as String?,
      latitude: fields[5] as double?,
      longitude: fields[6] as double?,
      isActive: fields[7] as bool,
    );
  }

  @override
  void write(BinaryWriter writer, PlantModel obj) {
    writer
      ..writeByte(8)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.qrCode)
      ..writeByte(2)
      ..write(obj.species)
      ..writeByte(3)
      ..write(obj.gridId)
      ..writeByte(4)
      ..write(obj.gridName)
      ..writeByte(5)
      ..write(obj.latitude)
      ..writeByte(6)
      ..write(obj.longitude)
      ..writeByte(7)
      ..write(obj.isActive);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PlantModelAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
