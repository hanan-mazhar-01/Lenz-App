import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../../services/auth_service.dart';

/// Whether the current session is a guest (no account): guests see their scan
/// report, but nothing is saved to History or Favorites. Safe to call where no
/// [AuthService] is in scope (previews, tests): then it is not a guest.
bool isGuestSession(BuildContext context) {
  try {
    return context.watch<AuthService>().isAnonymous;
  } catch (_) {
    return false;
  }
}
