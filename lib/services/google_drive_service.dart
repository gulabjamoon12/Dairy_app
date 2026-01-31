import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:googleapis_auth/auth_io.dart' as auth_io;
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:gg/services/backup_service.dart';

/// Service for backing up and restoring the app database via Google Drive.
/// Uses a visible folder "Milk Delivery Backups" in the user's Drive.
class GoogleDriveService {
  static const String _backupFolderName = 'Milk Delivery Backups';

  static const List<String> _scopes = [drive.DriveApi.driveFileScope];

  final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: _scopes,
    serverClientId: '1085930714084-3trpl0msa8d0k3jjeub7bvf2mhtjdosd.apps.googleusercontent.com',
  );

  /// Signs in the user. Returns the account on success, null if cancelled or failed.
  Future<GoogleSignInAccount?> signIn() async {
    try {
      final account = await _googleSignIn.signIn();
      return account;
    } catch (e) {
      debugPrint('GoogleDriveService signIn error: $e');
      return null;
    }
  }

  /// Signs in silently if a previous session exists. Returns the account or null.
  Future<GoogleSignInAccount?> signInSilently() async {
    try {
      final account = await _googleSignIn.signInSilently();
      return account;
    } catch (e) {
      debugPrint('GoogleDriveService signInSilently error: $e');
      return null;
    }
  }

  /// Signs out the current user.
  Future<void> signOut() async {
    try {
      await _googleSignIn.signOut();
    } catch (e) {
      debugPrint('GoogleDriveService signOut error: $e');
    }
  }

  /// Returns the current signed-in account, if any.
  GoogleSignInAccount? get currentUser => _googleSignIn.currentUser;

  /// Returns an authenticated HTTP client for Drive API, or null if not signed in / no token.
  /// Uses account.authHeaders to retrieve the access token from the standard sign-in flow.
  Future<http.Client?> _getAuthenticatedClient() async {
    final account = _googleSignIn.currentUser;
    if (account == null) return null;
    try {
      final headers = await account.authHeaders;
      final authHeader = headers['Authorization'];
      if (authHeader == null || authHeader.isEmpty) return null;
      final token = authHeader.startsWith('Bearer ')
          ? authHeader.substring(7)
          : authHeader;
      if (token.isEmpty) return null;
      final credentials = auth_io.AccessCredentials(
        auth_io.AccessToken(
          'Bearer',
          token,
          DateTime.now().toUtc().add(const Duration(hours: 1)),
        ),
        null,
        _scopes,
      );
      return auth_io.authenticatedClient(http.Client(), credentials);
    } catch (e) {
      debugPrint('GoogleDriveService _getAuthenticatedClient error: $e');
      return null;
    }
  }

  /// Gets or creates the "Milk Delivery Backups" folder. Returns folder ID or null.
  Future<String?> _getOrCreateBackupFolder() async {
    try {
      final client = await _getAuthenticatedClient();
      if (client == null) return null;

      final driveApi = drive.DriveApi(client);

      // Find existing folder
      final listResult = await driveApi.files.list(
        q: "mimeType='application/vnd.google-apps.folder' and name='$_backupFolderName' and trashed=false",
        $fields: 'files(id,name)',
      );

      if (listResult.files != null && listResult.files!.isNotEmpty) {
        return listResult.files!.first.id;
      }

      // Create folder
      final folder = await driveApi.files.create(
        drive.File()
          ..name = _backupFolderName
          ..mimeType = 'application/vnd.google-apps.folder',
      );
      return folder.id;
    } on drive.ApiRequestError catch (e) {
      debugPrint('GoogleDriveService _getOrCreateBackupFolder ApiRequestError: $e');
      return null;
    } catch (e) {
      debugPrint('GoogleDriveService _getOrCreateBackupFolder error: $e');
      return null;
    }
  }

  /// Uploads the latest local backup to the Drive folder. Replaces any existing file in the folder.
  /// Returns true on success.
  Future<bool> uploadLatestBackup() async {
    try {
      final folderId = await _getOrCreateBackupFolder();
      if (folderId == null) return false;

      final file = await BackupService.getLatestLocalBackupFile();
      if (file == null || !await file.exists()) return false;

      final client = await _getAuthenticatedClient();
      if (client == null) return false;

      final driveApi = drive.DriveApi(client);

      // List and delete existing files in the folder
      final listResult = await driveApi.files.list(
        q: "'$folderId' in parents and trashed=false",
        $fields: 'files(id)',
      );
      if (listResult.files != null) {
        for (final f in listResult.files!) {
          if (f.id != null) {
            try {
              await driveApi.files.delete(f.id!);
            } catch (_) {}
          }
        }
      }

      // Upload new file
      final fileName = file.path.split(Platform.pathSeparator).last;
      final length = await file.length();
      final media = drive.Media(file.openRead(), length);

      await driveApi.files.create(
        drive.File()
          ..name = fileName
          ..parents = [folderId],
        uploadMedia: media,
      );
      return true;
    } on drive.ApiRequestError catch (e) {
      debugPrint('GoogleDriveService uploadLatestBackup ApiRequestError: $e');
      return false;
    } catch (e) {
      debugPrint('GoogleDriveService uploadLatestBackup error: $e');
      return false;
    }
  }

  static const String _lastDriveBackupDateKey = 'last_drive_backup_date';

  /// Checks if user is signed in and if a Drive backup is needed today; if so, uploads silently.
  /// Call this periodically (e.g. on app start / resume). Does not block; safe to call unawaited.
  Future<void> checkAndAutoBackup() async {
    try {
      final account = await signInSilently();
      if (account == null) return;

      final prefs = await SharedPreferences.getInstance();
      final today = DateTime.now();
      final todayStr =
          '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
      final lastDate = prefs.getString(_lastDriveBackupDateKey);
      if (lastDate == todayStr) return;

      final ok = await uploadLatestBackup();
      if (ok) {
        await prefs.setString(_lastDriveBackupDateKey, todayStr);
        debugPrint('GoogleDriveService: automatic daily Drive backup succeeded.');
      } else {
        debugPrint('GoogleDriveService: automatic daily Drive backup failed.');
      }
    } catch (e) {
      debugPrint('GoogleDriveService checkAndAutoBackup error: $e');
    }
  }

  /// Restores the database from the backup file in the Drive folder (uses newest by modifiedTime).
  /// Returns true on success.
  Future<bool> restoreFromDrive() async {
    try {
      final folderId = await _getOrCreateBackupFolder();
      if (folderId == null) return false;

      final client = await _getAuthenticatedClient();
      if (client == null) return false;

      final driveApi = drive.DriveApi(client);

      final listResult = await driveApi.files.list(
        q: "'$folderId' in parents and trashed=false",
        $fields: 'files(id,modifiedTime)',
        orderBy: 'modifiedTime desc',
        pageSize: 1,
      );
      if (listResult.files == null || listResult.files!.isEmpty) return false;

      final fileId = listResult.files!.first.id!;

      // Download file content
      final response = await driveApi.files.get(
        fileId,
        downloadOptions: drive.DownloadOptions.fullMedia,
      );
      if (response is! drive.Media) return false;

      final tempDir = await getTemporaryDirectory();
      final tempPath = '${tempDir.path}/milk_restore_${DateTime.now().millisecondsSinceEpoch}.db';
      final tempFile = File(tempPath);
      try {
        await tempFile.writeAsBytes(await response.stream.toList().then((chunks) => chunks.expand((c) => c).toList()));
      } catch (e) {
        debugPrint('GoogleDriveService restoreFromDrive write error: $e');
        return false;
      }

      try {
        final ok = await BackupService.importDatabase(tempPath);
        return ok;
      } finally {
        try {
          if (await tempFile.exists()) await tempFile.delete();
        } catch (_) {}
      }
    } on drive.ApiRequestError catch (e) {
      debugPrint('GoogleDriveService restoreFromDrive ApiRequestError: $e');
      return false;
    } catch (e) {
      debugPrint('GoogleDriveService restoreFromDrive error: $e');
      return false;
    }
  }
}
