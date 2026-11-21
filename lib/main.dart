import 'package:flutter/material.dart';

import 'app.dart';
import 'data/app_database.dart';
import 'platform/feed_notifications.dart';
import 'state/app_state.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await FeedNotifications.init();
  final db = await AppDatabase.open();
  final state = AppState(db);
  await state.init();
  runApp(YuyingApp(state: state));
}
