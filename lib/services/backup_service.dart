import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:share_plus/share_plus.dart';
import 'package:sqflite/sqflite.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:gg/services/database_helper.dart';

/// Service for backing up and restoring the app database.
/// 
/// The database is stored locally on the device. Users can:
/// 1. Export the database to share/copy to another device
/// 2. Import a previously exported database to restore their data
class BackupService {
  static const String _dbName = 'milk_app.db';
  static const String _backupFileName = 'milk_delivery_backup.db';

  /// Request storage permissions for Android
  static Future<bool> requestStoragePermission() async {
    if (!Platform.isAndroid) return true;
    
    // Check Android version
    // For Android 13+ (API 33+), we don't need storage permission for app-specific files
    // For Android 11-12 (API 30-32), we may need MANAGE_EXTERNAL_STORAGE for full access
    // For Android 10 and below, we need READ/WRITE_EXTERNAL_STORAGE
    
    // First, check if we already have permission
    var status = await Permission.storage.status;
    if (status.isGranted) {
      return true;
    }
    
    // Try to request storage permission
    status = await Permission.storage.request();
    if (status.isGranted) {
      return true;
    }
    
    // For Android 11+, try MANAGE_EXTERNAL_STORAGE if regular storage is denied
    if (status.isPermanentlyDenied || status.isDenied) {
      // Check if we can use manage external storage
      var manageStatus = await Permission.manageExternalStorage.status;
      if (!manageStatus.isGranted) {
        manageStatus = await Permission.manageExternalStorage.request();
      }
      if (manageStatus.isGranted) {
        return true;
      }
    }
    
    // If permissions are permanently denied, return false
    // The UI will show appropriate message
    return false;
  }

  /// Check if storage permission is granted
  static Future<bool> hasStoragePermission() async {
    if (!Platform.isAndroid) return true;
    
    final storageStatus = await Permission.storage.status;
    if (storageStatus.isGranted) return true;
    
    final manageStatus = await Permission.manageExternalStorage.status;
    return manageStatus.isGranted;
  }

  /// Open app settings so user can manually grant permissions
  static Future<bool> openSettings() async {
    return await openAppSettings();
  }

  /// Get the path to the current database file
  static Future<String> getDatabasePath() async {
    final dbPath = await getDatabasesPath();
    return join(dbPath, _dbName);
  }

  /// Get the size of the current database in bytes
  static Future<int> getDatabaseSize() async {
    try {
      final path = await getDatabasePath();
      final file = File(path);
      if (await file.exists()) {
        return await file.length();
      }
    } catch (e) {
      debugPrint('Error getting database size: $e');
    }
    return 0;
  }

  /// Format bytes to human-readable string
  static String formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
  }

  /// Export the database file for backup.
  /// Returns true if successful, false otherwise.
  /// Returns null if permission was denied.
  static Future<bool?> exportDatabase() async {
    try {
      await DatabaseHelper.instance.close();

      final sourcePath = await getDatabasePath();
      final sourceFile = File(sourcePath);

      if (!await sourceFile.exists()) {
        debugPrint('Database file does not exist');
        await DatabaseHelper.instance.database;
        return false;
      }

      final tempDir = await getTemporaryDirectory();
      final backupPath = join(tempDir.path, _backupFileName);
      final tempPath = join(tempDir.path, '$_backupFileName.tmp');

      try {
        await sourceFile.copy(tempPath);
        await File(tempPath).rename(backupPath);
      } catch (e) {
        try {
          final f = File(tempPath);
          if (await f.exists()) await f.delete();
        } catch (_) {}
        rethrow;
      }

      await DatabaseHelper.instance.database;

      final result = await SharePlus.instance.share(ShareParams(
        files: [XFile(backupPath)],
        subject: 'Milk Delivery App Backup',
        text: 'Your Milk Delivery app data backup. Copy this file to your new device and use "Restore from Backup" to import your data.',
      ));

      debugPrint('Share result: ${result.status}');
      return true;
    } catch (e) {
      debugPrint('Error exporting database: $e');
      try {
        await DatabaseHelper.instance.database;
      } catch (_) {}
      return false;
    }
  }

  /// Import a database file from a given path.
  /// This will replace the current database with the imported one.
  /// Returns true if successful, false otherwise.
  static Future<bool> importDatabase(String importPath) async {
    try {
      final importFile = File(importPath);
      
      if (!await importFile.exists()) {
        debugPrint('Import file does not exist: $importPath');
        return false;
      }

      // Verify it's a valid SQLite database by checking the header
      final bytes = await importFile.readAsBytes();
      if (bytes.length < 16) {
        debugPrint('File too small to be a valid database');
        return false;
      }
      
      // SQLite files start with "SQLite format 3\000"
      final header = String.fromCharCodes(bytes.sublist(0, 15));
      if (!header.startsWith('SQLite format 3')) {
        debugPrint('Not a valid SQLite database file');
        return false;
      }

      // Close the current database
      await DatabaseHelper.instance.close();
      
      final destPath = await getDatabasePath();
      final destFile = File(destPath);
      
      // Create a backup of current database before replacing
      if (await destFile.exists()) {
        final backupDir = await getTemporaryDirectory();
        final backupPath = join(backupDir.path, 'milk_app_old_backup.db');
        await destFile.copy(backupPath);
      }
      
      // Copy the imported file to the database location
      await importFile.copy(destPath);
      
      // Reopen the database to verify it works
      await DatabaseHelper.instance.database;
      
      // Clear any cached data
      DatabaseHelper.instance.clearPriceCache();
      
      return true;
    } catch (e) {
      debugPrint('Error importing database: $e');
      // Try to reopen the database even if import failed
      try {
        await DatabaseHelper.instance.database;
      } catch (_) {}
      return false;
    }
  }

  /// Get the location where the user can find the database file manually
  static Future<String> getDatabaseDirectory() async {
    final dbPath = await getDatabasesPath();
    return dbPath;
  }

  /// Save backup to a user-selected location using file picker
  /// Returns the path if successful, null otherwise.
  static Future<String?> saveToLocation() async {
    try {
      // Close the database first to ensure all data is written
      await DatabaseHelper.instance.close();
      
      final sourcePath = await getDatabasePath();
      final sourceFile = File(sourcePath);
      
      if (!await sourceFile.exists()) {
        debugPrint('Database file does not exist');
        await DatabaseHelper.instance.database;
        return null;
      }

      // Read the database bytes
      final bytes = await sourceFile.readAsBytes();
      
      // Reopen the database immediately
      await DatabaseHelper.instance.database;
      
      // Let user pick save location using file_picker
      final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-').split('.').first;
      final fileName = 'milk_delivery_backup_$timestamp.db';
      
      final result = await FilePicker.platform.saveFile(
        dialogTitle: 'Save Backup File',
        fileName: fileName,
        type: FileType.any,
        bytes: bytes,
      );
      
      if (result == null) {
        debugPrint('User cancelled save dialog');
        return null;
      }
      
      // On some platforms, saveFile returns path but doesn't write bytes
      final savedFile = File(result);
      if (!await savedFile.exists() || await savedFile.length() == 0) {
        final tempPath = '$result.tmp';
        try {
          await File(tempPath).writeAsBytes(bytes);
          await File(tempPath).rename(result);
        } catch (e) {
          try {
            final f = File(tempPath);
            if (await f.exists()) await f.delete();
          } catch (_) {}
          rethrow;
        }
      }

      debugPrint('Backup saved to: $result');
      return result;
    } catch (e) {
      debugPrint('Error saving backup: $e');
      try {
        await DatabaseHelper.instance.database;
      } catch (_) {}
      return null;
    }
  }

  /// Create a backup in the app's documents directory (accessible via Files app on iOS)
  static Future<String?> createLocalBackup() async {
    try {
      await DatabaseHelper.instance.close();

      final sourcePath = await getDatabasePath();
      final sourceFile = File(sourcePath);

      if (!await sourceFile.exists()) {
        await DatabaseHelper.instance.database;
        return null;
      }

      final docsDir = await getApplicationDocumentsDirectory();
      final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-').split('.').first;
      final backupPath = join(docsDir.path, 'backup_$timestamp.db');
      final tempPath = '$backupPath.tmp';

      try {
        await sourceFile.copy(tempPath);
        await File(tempPath).rename(backupPath);
      } catch (e) {
        try {
          final f = File(tempPath);
          if (await f.exists()) await f.delete();
        } catch (_) {}
        rethrow;
      }

      await DatabaseHelper.instance.database;
      return backupPath;
    } catch (e) {
      debugPrint('Error creating local backup: $e');
      try {
        await DatabaseHelper.instance.database;
      } catch (_) {}
      return null;
    }
  }

  /// Get user-accessible backup directory
  /// Creates "MilkDeliveryBackups" folder in user-accessible location
  /// Android: Downloads/MilkDeliveryBackups (accessible via file manager)
  /// iOS: Documents/MilkDeliveryBackups (accessible via Files app)
  static Future<Directory?> getPersistentBackupDirectory() async {
    try {
      if (Platform.isAndroid) {
        // Use Downloads folder on Android (user-accessible via file manager)
        // Try to get Downloads directory
        try {
          final downloadsDir = Directory('/storage/emulated/0/Download/MilkDeliveryBackups');
          // Check if we have permission or if directory is accessible
          if (await hasStoragePermission()) {
            if (!await downloadsDir.exists()) {
              await downloadsDir.create(recursive: true);
            }
            return downloadsDir;
          }
        } catch (e) {
          debugPrint('Could not access Downloads folder: $e');
        }
        
        // Fallback: Use external storage directory (accessible via file manager)
        // This requires Android 10+ scoped storage or permission
        try {
          final externalDir = await getExternalStorageDirectory();
          if (externalDir != null) {
            final backupDir = Directory(join(externalDir.path, 'MilkDeliveryBackups'));
            if (!await backupDir.exists()) {
              await backupDir.create(recursive: true);
            }
            return backupDir;
          }
        } catch (e) {
          debugPrint('Could not access external storage: $e');
        }
      }
      
      // For iOS or Android fallback: Use Documents directory (accessible via Files app)
      final docsDir = await getApplicationDocumentsDirectory();
      final backupDir = Directory(join(docsDir.path, 'MilkDeliveryBackups'));
      if (!await backupDir.exists()) {
        await backupDir.create(recursive: true);
      }
      return backupDir;
    } catch (e) {
      debugPrint('Error getting user-accessible backup directory: $e');
    }
    return null;
  }

  /// Create daily backup in user-accessible location
  /// Returns the backup path if successful, null otherwise
  static Future<String?> createDailyBackup() async {
    try {
      // Prevent empty backups (e.g. fresh install)
      final hasData = await hasExistingData();
      if (!hasData) return null;

      // On Android, request storage permission if needed for Downloads folder
      if (Platform.isAndroid) {
        var hasPermission = await hasStoragePermission();
        if (!hasPermission) {
          hasPermission = await requestStoragePermission();
        }
      }

      await DatabaseHelper.instance.close();

      final sourcePath = await getDatabasePath();
      final sourceFile = File(sourcePath);

      if (!await sourceFile.exists()) {
        await DatabaseHelper.instance.database;
        return null;
      }

      final backupDir = await getPersistentBackupDirectory();
      if (backupDir == null) {
        await DatabaseHelper.instance.database;
        return null;
      }

      final now = DateTime.now();
      final dateStr = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      final timeStr = '${now.hour.toString().padLeft(2, '0')}-${now.minute.toString().padLeft(2, '0')}-${now.second.toString().padLeft(2, '0')}';
      final timestampStr = '${dateStr}_$timeStr';
      final backupPath = join(backupDir.path, 'milk_app_backup_$timestampStr.db');
      final tempPath = '$backupPath.tmp';

      try {
        await sourceFile.copy(tempPath);
        await File(tempPath).rename(backupPath);
      } catch (e) {
        try {
          final tempFile = File(tempPath);
          if (await tempFile.exists()) await tempFile.delete();
        } catch (_) {}
        rethrow;
      }

      await _cleanupOldBackups(backupDir, daysToKeep: 7);

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('last_backup_date', dateStr);
      await prefs.setString('last_backup_path', backupPath);

      await DatabaseHelper.instance.database;

      debugPrint('Daily backup created: $backupPath');
      return backupPath;
    } catch (e) {
      debugPrint('Error creating daily backup: $e');
      try {
        await DatabaseHelper.instance.database;
      } catch (_) {}
      return null;
    }
  }

  /// Check if daily backup is needed (hasn't been backed up today)
  static Future<bool> isBackupNeeded() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final lastBackupDate = prefs.getString('last_backup_date');
      
      if (lastBackupDate == null) return true;
      
      final today = DateTime.now();
      final todayStr = '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
      
      return lastBackupDate != todayStr;
    } catch (e) {
      debugPrint('Error checking if backup needed: $e');
      return true;
    }
  }

  /// Returns all backup files in the persistent backup directory, sorted newest first.
  /// Used by UI for "Pick a backup to restore" dialog.
  static Future<List<File>> getAvailableBackups() async {
    try {
      final backupDir = await getPersistentBackupDirectory();
      if (backupDir == null) return [];

      final files = backupDir.listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.db'))
          .toList();

      files.sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));
      return files;
    } catch (e) {
      debugPrint('Error getting available backups: $e');
      return [];
    }
  }

  /// Returns the latest local backup file, or creates one and returns it. Returns null on failure.
  static Future<File?> getLatestLocalBackupFile() async {
    try {
      final path = await getLatestBackupPath();
      if (path != null) {
        final file = File(path);
        if (await file.exists()) return file;
      }
      final createdPath = await createDailyBackup();
      if (createdPath != null) return File(createdPath);
    } catch (e) {
      debugPrint('Error getting latest local backup file: $e');
    }
    return null;
  }

  /// Get the latest backup file path
  static Future<String?> getLatestBackupPath() async {
    try {
      final backupDir = await getPersistentBackupDirectory();
      if (backupDir == null) return null;

      // Check SharedPreferences first
      final prefs = await SharedPreferences.getInstance();
      final lastBackupPath = prefs.getString('last_backup_path');
      if (lastBackupPath != null) {
        final file = File(lastBackupPath);
        if (await file.exists()) {
          return lastBackupPath;
        }
      }

      // If not found in prefs, search for latest backup file
      final files = backupDir.listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.db'))
          .toList();
      
      if (files.isEmpty) return null;

      // Sort by modification time and get latest
      files.sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));
      return files.first.path;
    } catch (e) {
      debugPrint('Error getting latest backup path: $e');
      return null;
    }
  }

  /// Restore from the latest backup automatically
  /// Returns true if restored, false if no backup found or restore failed
  static Future<bool> restoreFromLatestBackup() async {
    try {
      final backupPath = await getLatestBackupPath();
      if (backupPath == null) {
        debugPrint('No backup found to restore');
        return false;
      }

      debugPrint('Restoring from backup: $backupPath');
      return await importDatabase(backupPath);
    } catch (e) {
      debugPrint('Error restoring from latest backup: $e');
      return false;
    }
  }

  /// Check if database exists and has data
  static Future<bool> hasExistingData() async {
    try {
      final dbPath = await getDatabasePath();
      final dbFile = File(dbPath);
      if (!await dbFile.exists()) return false;
      
      // Check if database has any customers
      final customers = await DatabaseHelper.instance.getCustomers();
      return customers.isNotEmpty;
    } catch (e) {
      debugPrint('Error checking existing data: $e');
      return false;
    }
  }

  /// Cleanup old backup files. Always keeps the newest backup; deletes others only if older than [daysToKeep].
  static Future<void> _cleanupOldBackups(Directory backupDir, {int daysToKeep = 7}) async {
    try {
      final files = backupDir.listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.db'))
          .toList();

      if (files.isEmpty) return;

      files.sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));
      final toConsider = files.length > 1 ? files.skip(1).toList() : <File>[];
      final cutoffDate = DateTime.now().subtract(Duration(days: daysToKeep));

      for (final file in toConsider) {
        final modified = await file.lastModified();
        if (modified.isBefore(cutoffDate)) {
          await file.delete();
          debugPrint('Deleted old backup: ${file.path}');
        }
      }
    } catch (e) {
      debugPrint('Error cleaning up old backups: $e');
    }
  }
}
