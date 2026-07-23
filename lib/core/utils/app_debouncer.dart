import 'dart:async';

import 'package:flutter/foundation.dart';

/// Global singleton debouncer that prevents multiple rapid taps on any UI action.
///
/// Usage — one-shot tap guard (navigation, send, etc.):
///   AppDebouncer.run(() => context.push('/chat/...'));
///
/// Usage — search / text input debounce:
///   AppDebouncer.debounce('search', () => _searchUsers(query));
class AppDebouncer {
  AppDebouncer._();

  // Default cooldown between two accepted taps (navigation, button press, etc.)
  static const Duration _tapCooldown = Duration(milliseconds: 600);

  // Default delay for text-input debounce (search, filter, etc.)
  static const Duration _inputDelay = Duration(milliseconds: 400);

  // Tracks the last accepted tap time per tag so independent actions don't block each other.
  static final Map<String, DateTime> _lastTap = {};

  // Active debounce timers keyed by tag.
  static final Map<String, Timer> _timers = {};

  /// Runs [action] immediately if no tap with the same [tag] occurred within [cooldown].
  /// Use this for navigation, button presses, send actions — anything that must fire once.
  ///
  /// [tag] defaults to 'default' so a single call site needs no tag.
  static void run(
    VoidCallback action, {
    String tag = 'default',
    Duration cooldown = _tapCooldown,
  }) {
    final now = DateTime.now();
    final last = _lastTap[tag];
    if (last != null && now.difference(last) < cooldown) return; // too fast — ignore
    _lastTap[tag] = now;
    action();
  }

  /// Delays [action] by [delay] and cancels any pending call with the same [tag].
  /// Use this for search fields, filter inputs — anything that should wait for the user to stop typing.
  static void debounce(
    String tag,
    VoidCallback action, {
    Duration delay = _inputDelay,
  }) {
    _timers[tag]?.cancel();
    _timers[tag] = Timer(delay, () {
      _timers.remove(tag);
      action();
    });
  }

  /// Cancels a pending debounce timer for [tag].
  static void cancel(String tag) {
    _timers[tag]?.cancel();
    _timers.remove(tag);
  }

  /// Cancels all active timers. Call on app dispose if needed.
  static void cancelAll() {
    for (final t in _timers.values) {
      t.cancel();
    }
    _timers.clear();
  }
}

