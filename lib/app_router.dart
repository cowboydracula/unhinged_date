// lib/app_router.dart
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'features/auth/auth_gate.dart';
import 'features/swipe/swipe_screen.dart';
import 'features/profile/edit_profile_screen.dart';
import 'features/chat/chat_list_screen.dart';

GoRouter buildRouter() {
  return GoRouter(
    initialLocation: '/gate',
    refreshListenable: FirebaseAuth.instance,
    routes: [
      GoRoute(path: '/gate', builder: (_, __) => const AuthGate()),
      GoRoute(path: '/', builder: (_, __) => const SwipeScreen()),
      GoRoute(
        path: '/edit-profile',
        builder: (_, __) => const EditProfileScreen(),
      ),
      GoRoute(path: '/chats', builder: (_, __) => const ChatListScreen()),
    ],
    redirect: (_, state) {
      final authed = FirebaseAuth.instance.currentUser != null;
      final atGate = state.uri.path == '/gate';
      if (!authed && !atGate) return '/gate';
      if (authed && atGate) return '/';
      return null;
    },
  );
}
