import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'dart:io';

Future<void> main() async {
  dotenv.env['SUPABASE_URL'] = 'dummy';
  // We can't really run it against the real DB if we don't have the anon key.
}
