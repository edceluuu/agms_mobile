import 'package:hive/hive.dart';
part 'plant_model.g.dart';

@HiveType(typeId: 1)
class PlantModel extends HiveObject {
  @HiveField(0)
  String id;

  @HiveField(1)
  String qrCode;

  @HiveField(2)
  String species;

  @HiveField(3)
  String? gridId;

  @HiveField(4)
  String? gridName;

  @HiveField(5)
  double? latitude;

  @HiveField(6)
  double? longitude;

  @HiveField(7)
  bool isActive;

  PlantModel({
    required this.id,
    required this.qrCode,
    required this.species,
    this.gridId,
    this.gridName,
    this.latitude,
    this.longitude,
    required this.isActive,
  });

  factory PlantModel.fromJson(Map<String, dynamic> json) => PlantModel(
    id: json['id'],
    qrCode: json['qrCode'],
    species: json['species'],
    gridId: json['gridId'],
    gridName: json['grid']?['name'],
    latitude: json['latitude']?.toDouble(),
    longitude: json['longitude']?.toDouble(),
    isActive: json['isActive'] ?? true,
  );
}
