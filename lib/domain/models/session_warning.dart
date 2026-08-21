enum SessionWarningKind { stationary, duration, highSpeed }

enum SessionWarningAction { stopRecording, continueRecording }

class SessionWarning {
  const SessionWarning({
    required this.kind,
    required this.title,
    required this.message,
    required this.actions,
    this.remaining,
  });

  final SessionWarningKind kind;
  final String title;
  final String message;
  final Set<SessionWarningAction> actions;
  final Duration? remaining;
}
