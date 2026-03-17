import 'package:hive/hive.dart';

part 'user_model.g.dart';

@HiveType(typeId: 0)
class UserModel extends HiveObject {
  @HiveField(0)
  String id;

  @HiveField(1)
  String username;

  @HiveField(2)
  String name;

  @HiveField(3)
  String role; // 'ADMIN', 'SUPERVISOR', 'FIELD_MONITOR'

  UserModel({
    required this.id,
    required this.username,
    required this.name,
    required this.role,
  });

  factory UserModel.fromJson(Map<String, dynamic> json) => UserModel(
    id: json['id'],
    username: json['username'],
    name: json['name'],
    role: json['role'],
  );
}
