// lib/app_router.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'features/auth/sign_in_screen.dart';
import 'features/swipe/swipe_screen.dart';
import 'features/chat/chat_list_screen.dart';
import 'features/chat/chat_screen.dart';
import 'features/profile/edit_profile_screen.dart';

/// Listenable that refreshes the router whenever the stream emits.
class _StreamListenable<T> extends ChangeNotifier {
  late final StreamSubscription<T> _sub;
  _StreamListenable(Stream<T> stream) {
    _sub = stream.listen((_) => notifyListeners());
  }
  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }
}

class AppRouter {
  // Keep a single instance so it isn’t GC’d.
  static final _authRefresh = _StreamListenable<User?>(
    FirebaseAuth.instance.authStateChanges(),
  );

  static final GoRouter router = GoRouter(
    initialLocation: '/',
    debugLogDiagnostics: true,
    refreshListenable: _authRefresh,
    redirect: (context, state) {
      final user = FirebaseAuth.instance.currentUser;
      final loggingIn = state.matchedLocation == '/signin';
      if (user == null) return loggingIn ? null : '/signin';
      if (loggingIn) return '/';
      return null;
    },
    routes: [
      GoRoute(path: '/signin', builder: (_, __) => const SignInScreen()),
      GoRoute(path: '/', builder: (_, __) => const SwipeScreen()),
      GoRoute(
        path: '/edit-profile',
        builder: (_, __) => const EditProfileScreen(),
      ),
      GoRoute(path: '/chats', builder: (_, __) => const ChatListScreen()),
      GoRoute(
        path: '/chats/:id',
        builder: (_, state) => ChatScreen(
          matchId: state.pathParameters['id']!,
          peerUid: (state.extra as Map?)?['peerUid'] as String?,
        ),
      ),
    ],
  );
}
