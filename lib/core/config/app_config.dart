class AppConfig {
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');

  static const supabasePublishableKey = String.fromEnvironment(
    'SUPABASE_PUBLISHABLE_KEY',
  );

  static const apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://10.0.2.2:3000',
  );

  static void validate() {
    if (supabaseUrl.isEmpty) {
      throw StateError('SUPABASE_URL is required');
    }
    if (supabasePublishableKey.isEmpty) {
      throw StateError('SUPABASE_PUBLISHABLE_KEY is required');
    }
  }
}
