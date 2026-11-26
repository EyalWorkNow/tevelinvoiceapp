// 2611 §1: whether the first-run tutorial and its coach marks are due — kept
// on this device only (no server). Armed when a new owner finishes the
// business setup or a new member joins by invitation, and again from "עזרה ←
// הצג שוב את ההדרכה". An existing user updating the app is never armed, so
// never sees it.

import '../../state/cache.dart';

/// The screens that get one coach mark the first time.
abstract final class CoachIds {
  static const home = 'home';
  static const people = 'people';
  static const person = 'person';
  static const all = [home, people, person];
}

/// Where the flags live; tests use [MemoryTutorialStorage].
abstract class TutorialStorage {
  Future<Map<String, dynamic>?> read();
  Future<void> write(Map<String, dynamic> value);
}

class CacheTutorialStorage implements TutorialStorage {
  static const _name = 'tutorial_state';

  @override
  Future<Map<String, dynamic>?> read() async {
    final raw = await AppCache.readUserData(_name);
    return raw is Map ? Map<String, dynamic>.from(raw) : null;
  }

  @override
  Future<void> write(Map<String, dynamic> value) =>
      AppCache.writeUserData(_name, value);
}

class MemoryTutorialStorage implements TutorialStorage {
  Map<String, dynamic>? value;

  @override
  Future<Map<String, dynamic>?> read() async => value;

  @override
  Future<void> write(Map<String, dynamic> v) async => value = {...v};
}

class TutorialState {
  TutorialState([TutorialStorage? storage])
    : storage = storage ?? CacheTutorialStorage();

  TutorialStorage storage;

  Future<Map<String, dynamic>> _read() async {
    try {
      return await storage.read() ?? {};
    } on Object {
      return {};
    }
  }

  Future<void> _write(Map<String, dynamic> v) async {
    try {
      await storage.write(v);
    } on Object {
      // A device-only convenience: never fail a flow on it.
    }
  }

  /// A new owner / member: the cards on the next Home, then the coach marks.
  Future<void> arm() => _write({
    'cards': true,
    'coach': [...CoachIds.all],
  });

  /// "הצג שוב את ההדרכה": the coach marks again (the cards open right away).
  Future<void> replay() => _write({
    'cards': false,
    'coach': [...CoachIds.all],
  });

  /// True once: the cards are due (and are marked as shown).
  Future<bool> takeCards() async {
    final v = await _read();
    if (v['cards'] != true) return false;
    await _write({...v, 'cards': false});
    return true;
  }

  /// Whether the coach mark [id] is due (read only).
  Future<bool> coachDue(String id) async {
    final v = await _read();
    return (v['coach'] as List? ?? const []).contains(id);
  }

  /// True once per screen: its coach mark is due (and is marked as shown).
  Future<bool> takeCoach(String id) async {
    final v = await _read();
    final coach = [for (final c in (v['coach'] as List? ?? const [])) '$c'];
    if (!coach.remove(id)) return false;
    await _write({...v, 'coach': coach});
    return true;
  }
}

final tutorialState = TutorialState();
