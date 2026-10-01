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
        return;
      }

      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

      await _saveToken(role, await messaging.getToken());

      await _tokenSubscription?.cancel();
      _tokenSubscription = messaging.onTokenRefresh.listen(
        (token) => _saveToken(role, token),
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
    } catch (_) {
      // Notifications must never prevent the ride app from opening.
    }
  }

  static Future<void> _saveToken(String role, String? token) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || token == null || token.isEmpty) return;

    try {
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
    } catch (_) {
      // Token registration is best-effort and must not break the app.
    }
  }
}
