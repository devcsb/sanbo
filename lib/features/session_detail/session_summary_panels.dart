import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

/// A controlled, finite pair of panels; the summary above belongs to the caller.
class SessionSummaryPanels extends StatefulWidget {
  const SessionSummaryPanels({
    super.key,
    required this.route,
    required this.week,
    required this.index,
    required this.onPageChanged,
    this.weekLabel = '이번 주',
  });
  final Widget route, week;
  final int index;
  final ValueChanged<int> onPageChanged;
  final String weekLabel;
  @override
  State<SessionSummaryPanels> createState() => _SessionSummaryPanelsState();
}

class _SessionSummaryPanelsState extends State<SessionSummaryPanels>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;
  late final PageController _controller = PageController(
    initialPage: widget.index,
  );
  final _focus = [FocusNode(), FocusNode()];
  final _heights = [0.0, 0.0];
  final _pointers = <int>{};
  int? _pointerOrigin;
  var _restorePointerOrigin = false;
  var _restoringGesture = false;
  @override
  void didUpdateWidget(covariant SessionSummaryPanels oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.index != widget.index &&
        _controller.hasClients &&
        _controller.page?.round() != widget.index) {
      if (MediaQuery.disableAnimationsOf(context)) {
        _controller.jumpToPage(widget.index);
      } else {
        _controller.animateToPage(
          widget.index,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeInOut,
        );
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    for (final node in _focus) {
      node.dispose();
    }
    super.dispose();
  }

  void _select(int index) {
    _focus[index].requestFocus();
    widget.onPageChanged(index);
  }

  void _beginPointer(int pointer) {
    if (_pointers.isEmpty) _pointerOrigin = widget.index;
    _pointers.add(pointer);
    if (_pointers.length > 1) _restorePointerOrigin = true;
  }

  void _endPointer(int pointer, {bool cancelled = false}) {
    if (!_pointers.remove(pointer)) return;
    _restorePointerOrigin |= cancelled;
    if (_pointers.isNotEmpty) return;
    final origin = _pointerOrigin;
    final restore = _restorePointerOrigin;
    _pointerOrigin = null;
    _restorePointerOrigin = false;
    if (!restore || origin == null) return;
    // Run after PageView processes the pointer end and starts any settling.
    // Observing events here does not compete with the OS back gesture.
    scheduleMicrotask(() {
      if (!mounted || !_controller.hasClients) return;
      _restoringGesture = true;
      try {
        _controller.jumpToPage(origin);
      } finally {
        _restoringGesture = false;
      }
      if (widget.index != origin) widget.onPageChanged(origin);
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Focus(
      onKeyEvent: (_, event) {
        if (!_focus.any((node) => node.hasPrimaryFocus)) {
          return KeyEventResult.ignored;
        }
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        final key = event.logicalKey;
        if (key == LogicalKeyboardKey.arrowLeft ||
            key == LogicalKeyboardKey.home) {
          _select(0);
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.arrowRight ||
            key == LogicalKeyboardKey.end) {
          _select(1);
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              for (var i = 0; i < 2; i++)
                Expanded(
                  child: Semantics(
                    selected: widget.index == i,
                    button: true,
                    child: TextButton(
                      key: ValueKey('summary-tab-$i'),
                      focusNode: _focus[i]..skipTraversal = widget.index != i,
                      onPressed: () => _select(i),
                      style: TextButton.styleFrom(
                        minimumSize: const Size(48, 48),
                        backgroundColor: widget.index == i
                            ? Theme.of(context).colorScheme.primaryContainer
                            : null,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: widget.index == i
                              ? BorderSide(
                                  color: Theme.of(context).colorScheme.primary,
                                )
                              : BorderSide.none,
                        ),
                      ),
                      child: Text(i == 0 ? '이번 경로' : widget.weekLabel),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: math.max(1, math.max(_heights[0], _heights[1])),
            child: Listener(
              onPointerDown: (event) => _beginPointer(event.pointer),
              onPointerUp: (event) => _endPointer(event.pointer),
              onPointerCancel: (event) =>
                  _endPointer(event.pointer, cancelled: true),
              child: PageView(
                key: const ValueKey('summary-pages'),
                controller: _controller,
                allowImplicitScrolling: true,
                onPageChanged: (index) {
                  if (!_restoringGesture && index != widget.index) {
                    widget.onPageChanged(index);
                  }
                },
                children: [
                  for (var i = 0; i < 2; i++)
                    _KeepPanelAlive(
                      child: ExcludeSemantics(
                        excluding: widget.index != i,
                        child: ExcludeFocus(
                          excluding: widget.index != i,
                          child: TickerMode(
                            enabled: widget.index == i,
                            child: OverflowBox(
                              alignment: Alignment.topCenter,
                              minHeight: 0,
                              maxHeight: double.infinity,
                              child: _PanelMeasure(
                                onHeight: (height) {
                                  if (mounted && _heights[i] != height) {
                                    setState(() => _heights[i] = height);
                                  }
                                },
                                child: KeyedSubtree(
                                  key: ValueKey('summary-panel-$i'),
                                  child: i == 0 ? widget.route : widget.week,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Semantics(
            liveRegion: true,
            label:
                '${widget.index == 0 ? '이번 경로' : widget.weekLabel}, ${widget.index + 1} / 2',
            child: ExcludeSemantics(
              child: Text(
                '${widget.index + 1} / 2',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// Measure the same mounted panels, not duplicate offstage maps/tile clients.
class _PanelMeasure extends SingleChildRenderObjectWidget {
  const _PanelMeasure({required this.onHeight, required super.child});
  final ValueChanged<double> onHeight;
  @override
  RenderObject createRenderObject(BuildContext context) =>
      _PanelMeasureRender(onHeight);
  @override
  void updateRenderObject(
    BuildContext context,
    covariant _PanelMeasureRender renderObject,
  ) {
    renderObject.onHeight = onHeight;
  }
}

class _PanelMeasureRender extends RenderProxyBox {
  _PanelMeasureRender(this.onHeight);
  ValueChanged<double> onHeight;
  double? _last;
  @override
  void performLayout() {
    super.performLayout();
    if (_last == size.height) return;
    _last = size.height;
    final height = size.height;
    WidgetsBinding.instance.addPostFrameCallback((_) => onHeight(height));
  }
}

class _KeepPanelAlive extends StatefulWidget {
  const _KeepPanelAlive({required this.child});
  final Widget child;
  @override
  State<_KeepPanelAlive> createState() => _KeepPanelAliveState();
}

class _KeepPanelAliveState extends State<_KeepPanelAlive>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;
  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}
