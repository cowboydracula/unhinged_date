// lib/app_router.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'features/auth/auth_gate.dart';
import 'features/auth/sign_in_screen.dart';
import 'features/profile/edit_profile_screen.dart';
import 'features/profile/onboarding_flow.dart';
import 'features/swipe/swipe_screen.dart';
import 'features/chat/chat_list_screen.dart';
import 'features/chat/chat_screen.dart';

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
  static final _authRefresh = _StreamListenable<User?>(
    FirebaseAuth.instance.authStateChanges(),
  );

  static final GoRouter router = GoRouter(
    initialLocation: '/',
    debugLogDiagnostics: true,
    refreshListenable: _authRefresh,
    redirect: (context, state) {
      // let the AuthGate decide; only handle the login page redirect here
      final user = FirebaseAuth.instance.currentUser;
      final atSignin = state.matchedLocation == '/signin';
      if (user == null) return atSignin ? null : '/signin';
      if (atSignin) return '/';
      return null;
    },
    routes: [
      GoRoute(path: '/signin', builder: (_, __) => const SignInScreen()),
      GoRoute(path: '/', builder: (_, __) => const AuthGate()), // 👈 gate
      GoRoute(path: '/onboarding', builder: (_, __) => const OnboardingFlow()),
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
