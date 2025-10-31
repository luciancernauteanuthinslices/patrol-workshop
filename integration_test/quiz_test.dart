import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:patrol/patrol.dart';
import 'package:patrol_challenge/keys.dart';
import 'package:patrol_challenge/main.dart';
import 'package:patrol_challenge/pages/quiz/form_page.dart';
import 'package:patrol_challenge/ui/components/button/elevated_button.dart';
import 'package:patrol_challenge/ui/style/colors.dart';

/// Welcome to our Patrol quiz app :)
/// We're going to test our app with Patrol, a tool for E2E testing Flutter apps.
/// See [PTColors] for color constants
void main() {
  patrolTest(
    'quiz can be completed',
    ($) async {
      await initApp();
      await $.pumpWidgetAndSettle(const MyApp());

      // Handle permissions with timeout and retry logic for cloud devices
      try {
        if(await $.native.isPermissionDialogVisible()){
          await $.native.grantPermissionOnlyThisTime();
        }
      } catch (e) {
        // Permission dialog might not appear on all devices
        print('Permission dialog not found or already granted: $e');
      }

      // Tap "Go to the quiz" button
      await $('Go to the quiz').tap();
      await $.pumpAndSettle();

      // Tap Start on welcome page
      await $('Start').tap();
      await $.pumpAndSettle();

      // Start button pressed, proceed to form

      // Wait for the robot check screen
      // await $.waitUntilVisible($("To confirm you're not a robot, pick LeanCode's colors"), timeout: Duration(seconds: 10));

      // Enter name
      await $(TextField).enterText('John Doe');
      await $.pumpAndSettle();

      // Verify Ready text appears
      expect($(Text).containing('Ready'), findsOneWidget);

      // Select colors for robot check
      await $(SelectableBox).which<SelectableBox>((b) => b.color == PTColors.lcYellow).tap();
      await $.pumpAndSettle();

      await $(SelectableBox).which<SelectableBox>((b) => b.color == PTColors.lcBlack).tap();
      await $.pumpAndSettle();

      await $(SelectableBox).which<SelectableBox>((b) => b.color == PTColors.lcWhite).tap();
      await $.pumpAndSettle();

      // Slide the "Ready" slider to start the quiz
      final arrow = $(Icons.arrow_right_alt);
      await $.tester.drag(arrow, const Offset(300, 0));
      await $.pumpAndSettle();

      // Wait until first question appears (count-down is ~3 s)
      await $.waitUntilVisible($(Text).containing('Question 1/3'), timeout: const Duration(seconds: 15));

      // Question 1 - Select Fluttercon
      await $(PTElevatedButton).containing('Fluttercon').tap();
      await $.pumpAndSettle();

      // Wait for Question 2 to appear
      await $.waitUntilVisible($(Text).containing('Question 2/3'), timeout: const Duration(seconds: 10));

      // Question 2 - Select Flutter Dash
      final dashTile = $(ListTile).containing(Icons.flutter_dash);
      await dashTile.scrollTo();
      await dashTile.$(ElevatedButton).tap();
      await $.pumpAndSettle();

      // Question 3 - Select enabled button
      await $(ElevatedButton)
          .which<ElevatedButton>((b) => b.enabled)
          .at(2)
          .scrollTo()
          .tap();
      await $.pumpAndSettle();

      // Handle notification permission with error handling
        if(await $.native.isPermissionDialogVisible()) {
          await $.native.grantPermissionOnlyThisTime();
        }
    }
  );
}
