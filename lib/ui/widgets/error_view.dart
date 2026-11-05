import 'package:flutter/material.dart';

import '../../api/client.dart';
import '../../util/labels/common_he.dart';
import 'empty_state.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';

/// Hebrew message for any caught error (ApiException → its messageHe).
String errorTextHe(Object error) =>
    error is ApiException ? error.messageHe : 'משהו השתבש. נסה שוב.';

/// Full-area error with a retry action (spec §6 standard error state:
/// message from errors_he + "נסה שוב"; never a dead end).
class ErrorView extends StatelessWidget {
  const ErrorView({super.key, required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final network = error is ApiException && (error as ApiException).isNetwork;
    return EmptyState(
      icon: network ? Iconsax.wifi_square : Iconsax.danger,
      title: network ? CommonHe.offlineButton : 'משהו השתבש',
      message: errorTextHe(error),
      actionLabel: CommonHe.retry,
      onAction: onRetry,
    );
  }
}

/// Snackbar with the Hebrew error (for actions, not screens).
void showErrorSnack(BuildContext context, Object error) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(errorTextHe(error))));
}
