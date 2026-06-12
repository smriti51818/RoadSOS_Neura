import 'package:postgres/postgres.dart';

void main() async {
  final conn = await Connection.open(
    Endpoint(
      host: 'YOUR_NEON_HOST',
      database: 'neondb',
      username: 'YOUR_NEON_USER',
      password: 'YOUR_NEON_PASSWORD',
    ),
    settings: const ConnectionSettings(sslMode: SslMode.require),
  );

  print('Connected.');

  await conn.execute("ALTER TABLE incidents ADD COLUMN IF NOT EXISTS priority VARCHAR(5) DEFAULT 'P2'");
  await conn.execute("ALTER TABLE incidents ADD COLUMN IF NOT EXISTS notes TEXT DEFAULT ''");
  print('Columns added: priority, notes');

  final users = await conn.execute("SELECT * FROM users");
  print('\n=== USERS TABLE (${users.length} rows) ===');
  for (final row in users) {
    print('  phone=${row[0]}, name=${row[1]}, blood_group=${row[2]}');
  }

  final incidents = await conn.execute("SELECT id, user_phone, service_name, status, priority FROM incidents");
  print('\n=== INCIDENTS TABLE (${incidents.length} rows) ===');
  for (final row in incidents) {
    print('  id=${(row[0] as String).substring(0,8)}... phone=${row[1]}, service=${row[2]}, status=${row[3]}, priority=${row[4]}');
  }

  await conn.close();
  print('\nDone.');
}
