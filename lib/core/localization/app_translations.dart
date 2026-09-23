class AppTranslations {
  static const Map<String, Map<String, String>> _localizedValues = {
    'es': {
      // settingsScreen texts
      'settings_title': 'PREFERENCIAS',
      'vault_password': 'Contraseña del Baúl',
      'vault_password_sub': 'Modificado hace 2 días',
      'biometrics': 'Biometría',
      'biometrics_sub': 'Huella y Reconocimiento Facial Activos',
      'notifications': 'Notificaciones',
      'notifications_sub': 'Solo alertas críticas',
      'app_language': 'Idioma de la App',
      'language_dialog_title': 'Seleccionar Idioma',
      'display_title': 'PANTALLA',
      'dark_mode': 'Modo Oscuro',
      'enabled': 'Activado',
      'disabled': 'Desactivado',
      'spanish': 'Español',
      'english': 'Inglés',

      // VaultScreen texts
      'vault_title': 'Grabaciones',
      'vault_subtitle': 'Tu información cifrada y almacenada de forma segura.',
      'vault_status_badge': 'ESTADO DEL SISTEMA',
      'vault_encryption_active': 'Cifrado AES-256',
      'vault_encryption_desc': 'Los protocolos resguardan todos los registros almacenados.',
      'vault_import_btn': 'IMPORTAR GRABACIÓN',
      'vault_recent_assets': 'REGISTROS RECIENTES',
      'vault_sort_by_date': 'ORDENAR POR FECHA',
      'vault_delete_title': '¿Eliminar Grabación?',
      'vault_delete_msg': 'Esta acción es irreversible y el archivo se borrará permanentemente de la memoria segura.',
      'vault_delete_success': 'Grabación eliminada correctamente',
      'vault_delete_action': 'Eliminar',
      'vault_cancel_action': 'Cancelar',

      // HomeScreen texts
      'home_system_status': 'ESTADO DEL SISTEMA',
      'home_all_clear': 'Todo seguro',
      'home_record_camera': 'Cifrado de datos',
      'home_record_camera_desc': 'Almacana de forma segura y cifrada la información en tu dispositivo.',
      'home_record_audio': 'Detección por audio',
      'home_record_audio_desc': 'Registros de eventos violentos con metadatos biométricos y de ubicación.',
      'home_secure_vault': 'Almacenamiento Seguro',
      'home_total_assets': 'Total de Registros',
      'home_total_assets_val': '1,482 Elementos',
      'home_encrypted_space': 'Espacio Cifrado',
      'home_encrypted_space_val': '2.4 TB',
      'home_access_vault_btn': 'ACCEDER AL ALMACENAMIENTO',

      // AuthScreen texts
      'auth_reason': 'Acceder a serene',
      'auth_not_supported': 'Biometría no disponible.\nIntenta de nuevo o contacta soporte.',
      'auth_cancelled': 'Autenticación cancelada. Intenta de nuevo.',
      'auth_preferences_title': 'Preferencias',
      'auth_welcome_title': 'Bienvenido de vuelta',
      'auth_welcome_subtitle': 'Reingresa al círculo de protección.',
      'auth_button': 'AUTENTICAR',
      'auth_close_dialog': 'Cerrar',
      'auth_footer': '© 2026 serene\nTODOS LOS DERECHOS RESERVADOS.',

      'nav_home': 'INICIO',
      'nav_vault': 'ALMACENAMIENTO',
      'nav_settings': 'AJUSTES',
    },
    'en': {
      // SettingsScreen texts
      'settings_title': 'PREFERENCES',
      'vault_password': 'Vault Password',
      'vault_password_sub': 'Last changed 2d ago',
      'biometrics': 'Biometrics',
      'biometrics_sub': 'FaceID & TouchID Active',
      'notifications': 'Notifications',
      'notifications_sub': 'Critical alerts only',
      'app_language': 'App Language',
      'language_dialog_title': 'Select Language',
      'display_title': 'DISPLAY',
      'dark_mode': 'Dark Mode',
      'enabled': 'Enabled',
      'disabled': 'Disabled',
      'spanish': 'Spanish',
      'english': 'English',

      // VaultScreen texts
      'vault_title': 'Recordings',
      'vault_subtitle': 'Your encrypted information stored securely.',
      'vault_status_badge': 'SYSTEM STATUS',
      'vault_encryption_active': 'AES-256 Encryption',
      'vault_encryption_desc': 'The protocols are currently securing all stored assets.',
      'vault_import_btn': 'IMPORT RECORDING',
      'vault_recent_assets': 'RECENT ASSETS',
      'vault_sort_by_date': 'SORT BY DATE',
      'vault_delete_title': 'Delete Recording?',
      'vault_delete_msg': 'This action is irreversible and the asset will be permanently purged from secure memory.',
      'vault_delete_success': 'Recording deleted successfully',
      'vault_delete_action': 'Delete',
      'vault_cancel_action': 'Cancel',

      // HomeScreen texts
      'home_system_status': 'SYSTEM STATUS',
      'home_all_clear': 'All clear',
      'home_record_camera': 'Encrypted data',
      'home_record_camera_desc': 'Securely store encrypted data directly on your device.',
      'home_record_audio': 'Audio detection',
      'home_record_audio_desc': 'Capture and analyze audio events with biometric and location metadata.',
      'home_secure_vault': 'Secure Storage',
      'home_total_assets': 'Total Assets',
      'home_total_assets_val': '1,482 Items',
      'home_encrypted_space': 'Encrypted Space',
      'home_encrypted_space_val': '2.4 TB',
      'home_access_vault_btn': 'ACCESS STORAGE',

      // AuthScreen texts
      'auth_reason': 'Access serene',
      'auth_not_supported': 'Biometrics unavailable.\nPlease retry or contact support.',
      'auth_cancelled': 'Authentication cancelled. Please try again.',
      'auth_preferences_title': 'Preferences',
      'auth_welcome_title': 'Welcome back',
      'auth_welcome_subtitle': 'Re-enter the circle of protection.',
      'auth_button': 'AUTHENTICATE',
      'auth_close_dialog': 'Close',
      'auth_footer': '© 2026 serene\nALL RIGHTS RESERVED.',

      // Bottom Navigation Bar
      'nav_home': 'HOME',
      'nav_vault': 'STORAGE',
      'nav_settings': 'SETTINGS',
    },
  };

  static String tr(String key, String locale) {
    return _localizedValues[locale]?[key] ?? _localizedValues['en']?[key] ?? key;
  }
}