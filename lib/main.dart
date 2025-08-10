import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
// import 'package:firebase_app_check/firebase_app_check.dart'; // 🔹 Commented out
import 'package:google_sign_in/google_sign_in.dart';
import 'firebase_options.dart';
import 'app_router.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await GoogleSignIn.instance.initialize();

  // 🔹 Disable Firebase App Check by commenting out activation
  /*
await FirebaseAppCheck.instance.activate(
  // androidProvider: kDebugMode ? AndroidProvider.debug : AndroidProvider.playIntegrity,
  // appleProvider: AppleProvider.appAttestWithDeviceCheckFallback,
);
*/

  runApp(const UnhingedApp());
}

class UnhingedApp extends StatelessWidget {
  const UnhingedApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Unhinged',
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF6E59A5),
        useMaterial3: true,
      ),
      // home: const HomeShell(), // ❌ Not needed when using routerConfig
      routerConfig: AppRouter.router,
    );
  }
}
