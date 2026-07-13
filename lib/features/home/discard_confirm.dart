import 'package:flutter/material.dart';

/// Confirmation gate for discarding an incomplete walk (UX-H01).
/// Returns true only if the user confirms delete.
Future<bool> confirmDiscardIncompleteWalk(BuildContext context) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) {
      final scheme = Theme.of(ctx).colorScheme;
      return AlertDialog(
        title: const Text('기록 지우기'),
        content: const Text(
          '저장하지 않은 산책을 지웁니다. 되돌릴 수 없어요.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: scheme.error,
              foregroundColor: scheme.onError,
              minimumSize: const Size(72, 44),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('삭제'),
          ),
        ],
      );
    },
  );
  return ok == true;
}
