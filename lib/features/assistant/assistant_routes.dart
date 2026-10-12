import 'package:flutter/material.dart';

import '../../models/ai.dart';
import '../driver/driver_task_detail_screen.dart';
import '../driver/driver_tasks_screen.dart';
import '../neworder/new_order_screen.dart';
import '../orders/order_details_screen.dart';
import '../orders/orders_screen.dart';
import '../payments/payments_screen.dart';
import '../profile/profile_screen.dart';

/// Maps the channel-neutral route keys the AI returns (`links[].mobileRoute`) onto the app's EXISTING screens.
/// Unknown keys return false so the caller can ignore them — the assistant never invents a screen.
class AssistantRoutes {
  AssistantRoutes._();

  static bool canOpen(AiLink link) => _builder(link) != null || _isDriverHome(link.mobileRoute);

  static Future<bool> open(BuildContext context, AiLink link) async {
    final route = link.mobileRoute;
    if (route == null || route.isEmpty) return false;

    // Driver home lives in the driver shell underneath the assistant — just go back to it.
    if (_isDriverHome(route)) {
      Navigator.of(context).popUntil((r) => r.isFirst);
      return true;
    }
    final builder = _builder(link);
    if (builder == null) return false;
    await Navigator.of(context).push(MaterialPageRoute(builder: builder));
    return true;
  }

  static bool _isDriverHome(String? route) => route == 'driver/home';

  static WidgetBuilder? _builder(AiLink link) {
    final route = link.mobileRoute ?? '';
    final parts = route.split('/');
    switch (parts.first) {
      case 'order':
        if (parts.length < 2 || parts[1].isEmpty) return null;
        return (_) => OrderDetailsScreen(orderId: parts[1], orderNumber: link.label);
      case 'orders':
        return (_) => const OrdersScreen();
      case 'new-order':
        return (_) => const NewOrderScreen();
      case 'payments':
        return (_) => const PaymentsScreen();
      case 'profile':
        return (_) => const ProfileScreen();
      case 'driver':
        if (parts.length < 2) return null;
        if (parts[1] == 'tasks') return (_) => const DriverTasksScreen();
        // The detail screen loads the task by its order number (the link label).
        if (parts[1] == 'task' && link.label.isNotEmpty && link.label != '—') {
          return (_) => DriverTaskDetailScreen(orderNumber: link.label);
        }
        return null;
      default:
        return null;
    }
  }
}
