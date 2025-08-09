// lib/features/auth/auth_gate.dart
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (_, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (snap.data != null) return const _Go('/');
        return const SignInScreen();
      },
    );
  }
}

class _Go extends StatelessWidget {
  final String to;
  const _Go(this.to, {super.key});
  @override
  Widget build(BuildContext context) {
    Future.microtask(() => Navigator.of(context).pushReplacementNamed(to));
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}

class SignInScreen extends StatelessWidget {
  const SignInScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final auth = FirebaseAuth.instance;
    return Scaffold(
      appBar: AppBar(title: const Text('Sign in')),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ElevatedButton(
              onPressed: () async {
                await auth.signInAnonymously(); // quick dev path
              },
              child: const Text('Continue (anonymous)'),
            ),
            const SizedBox(height: 12),
            // TODO: add Google/Apple providers for production
          ],
        ),
      ),
    );
  }
}
