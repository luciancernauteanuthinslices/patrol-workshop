import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:patrol/patrol.dart';
import 'package:patrol_challenge/main.dart';

void main() {
  patrolTest(
    'app launches successfully',
    ($) async {
      // Simple test to verify app launches
      await $.pumpWidgetAndSettle(const MyApp());
      
      // Verify the app is running
      expect(find.byType(MyApp), findsOneWidget);
      
      print('✓ App launched successfully');
    }
  );

  patrolTest(
    'navigate to quiz screen',
    ($) async {
      await $.pumpWidgetAndSettle(const MyApp());
      
      // Try to find and tap the "Go to the quiz" button
      try {
        await $('Go to the quiz').tap();
        await $.pumpAndSettle();
        print('✓ Successfully navigated to quiz');
      } catch (e) {
        print('✗ Failed to navigate: $e');
        rethrow;
      }
    }
  );
}
