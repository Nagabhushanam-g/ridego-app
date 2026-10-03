import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';

const String _databaseId = 'firestore-db-2';

FirebaseFirestore get _firestore => FirebaseFirestore.instanceFor(
      app: Firebase.app(),
      databaseId: _databaseId,
    );

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
}

class RideGoNotificationService {
  RideGoNotificationService._();

  static StreamSubscription<RemoteMessage>? _messageSubscription;
  static StreamSubscription<String>? _tokenSubscription;

  static Future<void> initialize(
    BuildContext context, {
    required String role,
  }) async {
    final messaging = FirebaseMessaging.instance;

    try {
      final settings = await messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );

      if (settings.authorizationStatus == AuthorizationStatus.denied) {
        debugPrint('RideGo FCM permission denied for role=$role.');
        return;
      }

      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

      final token = await messaging.getToken();
      await _saveToken(role, token);

      await _tokenSubscription?.cancel();
      _tokenSubscription = messaging.onTokenRefresh.listen(
        (token) async {
          await _saveToken(role, token);
        },
        onError: (Object error) {
          debugPrint('RideGo FCM token refresh failed: $error');
        },
      );

      await _messageSubscription?.cancel();
      _messageSubscription = FirebaseMessaging.onMessage.listen((message) {
        if (!context.mounted) return;
        final notification = message.notification;
        final title = notification?.title ??
            message.data['title']?.toString() ??
            'RideGo';
        final body = notification?.body ??
            message.data['body']?.toString() ??
            'You have a new RideGo update.';

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            duration: const Duration(seconds: 4),
            content: Text('$title — $body'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      });
    } catch (error, stackTrace) {
      // Notification setup must not prevent the ride app from opening.
      debugPrint('RideGo notification initialization failed for role=$role: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  static Future<void> _saveToken(String role, String? token) async {
    final user = FirebaseAuth.instance.currentUser;
    final uid = user?.uid;
    if (uid == null) {
      debugPrint('RideGo cannot save FCM token: no authenticated user (role=$role).');
      return;
    }
    if (token == null || token.isEmpty) {
      debugPrint('RideGo FCM token is empty for uid=$uid (role=$role).');
      return;
    }

    try {
      // Explicitly create the parent document as well. Firestore permits
      // subcollections without a parent document, which can make the users
      // collection look absent in the console.
      await _firestore.collection('users').doc(uid).set({
        'uid': uid,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      await _firestore
          .collection('users')
          .doc(uid)
          .collection('devices')
          .doc(token)
          .set({
        'token': token,
        'role': role,
        'platform': 'android',
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      debugPrint('RideGo FCM token saved for uid=$uid (role=$role).');
    } catch (error, stackTrace) {
      // Keep app startup resilient, but log the cause so token-write failures
      // can be diagnosed in Android logs.
      debugPrint('RideGo failed to save FCM token for uid=$uid (role=$role): $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }
}
