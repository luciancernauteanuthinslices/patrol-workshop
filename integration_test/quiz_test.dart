import 'package:patrol/patrol.dart';
import 'package:patrol_challenge/main.dart';
import 'package:patrol_challenge/ui/style/colors.dart';

/// Welcome to our Patrol quiz app :)
/// We're going to test our app with Patrol, a tool for E2E testing Flutter apps.
/// See [PTColors] for color constants
void main() {
  patrolTest(
    'test',
    ($) async {
      await initApp();
      await $.pumpWidgetAndSettle(const MyApp());

      // write your code here

      await $('Start again').waitUntilVisible();
    },
  );
}
