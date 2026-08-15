import 'package:flutter/material.dart';

class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Image.asset(
              'assets/icon/app_icon.png',
              height: 110,
              errorBuilder: (context, error, stackTrace) => const Icon(
                Icons.solar_power,
                size: 100,
                color: Color(0xFF1E88E5),
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'SIYA SOLAR STAFF',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.0,
              ),
            ),
            SizedBox(height: 16),
            Text(
              'SOLAR CRM',
              style: TextStyle(
                fontSize: 18,
                color: Colors.grey,
                letterSpacing: 2,
              ),
            ),
            SizedBox(height: 48),
            CircularProgressIndicator(),
          ],
        ),
      ),
    );
  }
}
