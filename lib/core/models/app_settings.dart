import 'package:hive/hive.dart';

part 'app_settings.g.dart';

@HiveType(typeId: 2)
class AppSettings extends HiveObject {
  @HiveField(0)
  late bool isDarkMode;

  @HiveField(1)
  late String locale; // 'es' for Spanish, 'en' for English

  AppSettings({
    this.isDarkMode = true,
    this.locale = 'es',
  });

  factory AppSettings.defaults() {
    return AppSettings(
      isDarkMode: true,
      locale: 'es',
    );
  }
}
