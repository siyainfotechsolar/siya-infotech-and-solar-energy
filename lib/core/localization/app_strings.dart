class AppStrings {
  // English default strings map for key-based localization
  static const Map<String, String> _en = {
    'loading': 'Loading...',
    'initial_app_loading': 'Starting Siya Solar Staff...',
    'page_loading': 'Loading page...',
    'data_loading': 'Loading data...',
    'save_loading': 'Saving...',
    'update_loading': 'Checking updates...',
    'upload_loading': 'Uploading...',
    'import_loading': 'Importing...',
    'delete_loading': 'Deleting...',
    'sync_loading': 'Syncing...',
    'retry': 'RETRY',
    'unable_to_load': 'Unable to load data.',
    'network_timeout': 'Connection timed out. Please check internet connection.',
    'operation_failed': 'Operation failed.',
    'upload_failed': 'Upload failed.',
    'import_failed': 'Import failed.',
    'saved_successfully': 'Saved successfully.',
    'uploaded_successfully': 'Uploaded successfully.',
    'imported_successfully': 'Imported successfully.',
    'please_wait': 'Please wait...',
    'reading_file': 'Reading file...',
    'validating': 'Validating...',
    'checking_duplicates': 'Checking duplicates...',
    'completed': 'Completed',
  };

  static String get(String key, {String? fallback}) {
    return _en[key] ?? fallback ?? key;
  }

  // Helper getters
  static String get loading => get('loading');
  static String get initialAppLoading => get('initial_app_loading');
  static String get pageLoading => get('page_loading');
  static String get dataLoading => get('data_loading');
  static String get saveLoading => get('save_loading');
  static String get updateLoading => get('update_loading');
  static String get uploadLoading => get('upload_loading');
  static String get importLoading => get('import_loading');
  static String get deleteLoading => get('delete_loading');
  static String get syncLoading => get('sync_loading');
  static String get retry => get('retry');
  static String get unableToLoad => get('unable_to_load');
  static String get networkTimeout => get('network_timeout');
  static String get operationFailed => get('operation_failed');
  static String get uploadFailed => get('upload_failed');
  static String get importFailed => get('import_failed');
  static String get savedSuccessfully => get('saved_successfully');
  static String get uploadedSuccessfully => get('uploaded_successfully');
  static String get importedSuccessfully => get('imported_successfully');
  static String get pleaseWait => get('please_wait');
  static String get readingFile => get('reading_file');
  static String get validating => get('validating');
  static String get checkingDuplicates => get('checking_duplicates');
  static String get completed => get('completed');
}
