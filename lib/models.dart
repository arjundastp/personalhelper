import 'package:material_ui/material_ui.dart';

/// Mirrors RepeatRule in the Android code (Models.kt). See that file for field meanings.
class RepeatRule {
  final String type; // once | daily | weekly | monthly | yearly | hourly
  final int interval; // days/weeks/months/years, or MINUTES for hourly
  final List<int> weekdays; // 1 = Mon .. 7 = Sun
  final int? windowEnd; // hourly: last minute-of-day
  final DateTime? endDate;

  const RepeatRule({this.type = 'once', this.interval = 1, this.weekdays = const [], this.windowEnd, this.endDate});

  RepeatRule copyWith({String? type, int? interval, List<int>? weekdays, int? Function()? windowEnd, DateTime? Function()? endDate}) =>
      RepeatRule(
        type: type ?? this.type,
        interval: interval ?? this.interval,
        weekdays: weekdays ?? this.weekdays,
        windowEnd: windowEnd != null ? windowEnd() : this.windowEnd,
        endDate: endDate != null ? endDate() : this.endDate,
      );

  Map<String, dynamic> toJson() => {
        'type': type,
        'interval': interval,
        'weekdays': weekdays,
        'windowEnd': windowEnd,
        'endDate': endDate == null ? null : isoDate(endDate!),
      };

  factory RepeatRule.fromJson(Map<String, dynamic>? j) {
    if (j == null) return const RepeatRule();
    return RepeatRule(
      type: j['type'] as String? ?? 'once',
      interval: (j['interval'] as num?)?.toInt() ?? 1,
      weekdays: ((j['weekdays'] as List?) ?? const []).map((e) => (e as num).toInt()).toList(),
      windowEnd: (j['windowEnd'] as num?)?.toInt(),
      endDate: j['endDate'] == null ? null : DateTime.tryParse(j['endDate'] as String),
    );
  }
}

class Reminder {
  final int id;
  final String title;
  final String notes;
  final String category;
  final DateTime startDate; // date part only
  final int hour;
  final int minute;
  final RepeatRule repeat;
  final String? soundUri;
  final String? soundName;
  final bool vibrate;
  final bool enabled;
  final int snoozeMinutes;
  final int createdAt;
  final DateTime? nextTrigger;
  final DateTime? snoozedUntil;
  final DateTime? lastFired;

  const Reminder({
    this.id = 0,
    this.title = '',
    this.notes = '',
    this.category = 'custom',
    required this.startDate,
    this.hour = 9,
    this.minute = 0,
    this.repeat = const RepeatRule(),
    this.soundUri,
    this.soundName,
    this.vibrate = true,
    this.enabled = true,
    this.snoozeMinutes = 10,
    this.createdAt = 0,
    this.nextTrigger,
    this.snoozedUntil,
    this.lastFired,
  });

  DateTime get startDateTime => DateTime(startDate.year, startDate.month, startDate.day, hour, minute);

  /// The next time this reminder will alert (a pending snooze counts).
  DateTime? get nextAlert {
    final s = snoozedUntil;
    final n = nextTrigger;
    if (s != null && (n == null || s.isBefore(n))) return s;
    return n;
  }

  Reminder copyWith({
    int? id,
    String? title,
    String? notes,
    String? category,
    DateTime? startDate,
    int? hour,
    int? minute,
    RepeatRule? repeat,
    String? soundUri,
    String? soundName,
    bool? vibrate,
    bool? enabled,
    int? snoozeMinutes,
  }) =>
      Reminder(
        id: id ?? this.id,
        title: title ?? this.title,
        notes: notes ?? this.notes,
        category: category ?? this.category,
        startDate: startDate ?? this.startDate,
        hour: hour ?? this.hour,
        minute: minute ?? this.minute,
        repeat: repeat ?? this.repeat,
        soundUri: soundUri ?? this.soundUri,
        soundName: soundName ?? this.soundName,
        vibrate: vibrate ?? this.vibrate,
        enabled: enabled ?? this.enabled,
        snoozeMinutes: snoozeMinutes ?? this.snoozeMinutes,
        createdAt: createdAt,
        nextTrigger: nextTrigger,
        snoozedUntil: snoozedUntil,
        lastFired: lastFired,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'notes': notes,
        'category': category,
        'startDate': isoDate(startDate),
        'hour': hour,
        'minute': minute,
        'repeat': repeat.toJson(),
        'soundUri': soundUri,
        'soundName': soundName,
        'vibrate': vibrate,
        'enabled': enabled,
        'snoozeMinutes': snoozeMinutes,
        'createdAt': createdAt == 0 ? DateTime.now().millisecondsSinceEpoch : createdAt,
      };

  factory Reminder.fromJson(Map<String, dynamic> j) {
    DateTime? ms(String k) => j[k] == null ? null : DateTime.fromMillisecondsSinceEpoch((j[k] as num).toInt());
    return Reminder(
      id: (j['id'] as num?)?.toInt() ?? 0,
      title: j['title'] as String? ?? '',
      notes: j['notes'] as String? ?? '',
      category: j['category'] as String? ?? 'custom',
      startDate: DateTime.tryParse(j['startDate'] as String? ?? '') ?? DateTime.now(),
      hour: (j['hour'] as num?)?.toInt() ?? 9,
      minute: (j['minute'] as num?)?.toInt() ?? 0,
      repeat: RepeatRule.fromJson(j['repeat'] as Map<String, dynamic>?),
      soundUri: j['soundUri'] as String?,
      soundName: j['soundName'] as String?,
      vibrate: j['vibrate'] as bool? ?? true,
      enabled: j['enabled'] as bool? ?? true,
      snoozeMinutes: (j['snoozeMinutes'] as num?)?.toInt() ?? 10,
      createdAt: (j['createdAt'] as num?)?.toInt() ?? 0,
      nextTrigger: ms('nextTrigger'),
      snoozedUntil: ms('snoozedUntil'),
      lastFired: ms('lastFired'),
    );
  }
}

class HistoryEntry {
  final int reminderId;
  final String title;
  final String category;
  final DateTime dueAt;
  final DateTime at;
  final String status; // done | snoozed | auto_snoozed | missed
  final bool seen;

  HistoryEntry.fromJson(Map<String, dynamic> j)
      : reminderId = (j['reminderId'] as num).toInt(),
        title = j['title'] as String? ?? '',
        category = j['category'] as String? ?? 'custom',
        dueAt = DateTime.fromMillisecondsSinceEpoch((j['dueAt'] as num).toInt()),
        at = DateTime.fromMillisecondsSinceEpoch((j['at'] as num).toInt()),
        status = j['status'] as String? ?? 'done',
        seen = j['seen'] as bool? ?? true;
}

class SoundOption {
  final String uri;
  final String title;
  final String group; // app | alarm | ringtone | notification | file
  const SoundOption(this.uri, this.title, this.group);

  factory SoundOption.fromJson(Map<String, dynamic> j) =>
      SoundOption(j['uri'] as String, j['title'] as String, j['group'] as String? ?? 'app');
}

class Category {
  final String key;
  final String label;
  final IconData icon;
  final Color color;
  const Category(this.key, this.label, this.icon, this.color);
}

/// Colors match Categories.color() in AlarmService.kt so the alert screen looks the same.
const categories = <Category>[
  Category('medicine', 'Medicine', Icons.medication_rounded, Color(0xFFE5484D)),
  Category('water', 'Water', Icons.water_drop_rounded, Color(0xFF0090FF)),
  Category('vehicle', 'Vehicle', Icons.directions_car_rounded, Color(0xFF8E4EC6)),
  Category('bills', 'Bills', Icons.receipt_long_rounded, Color(0xFFF76B15)),
  Category('birthday', 'Birthday', Icons.cake_rounded, Color(0xFFD6409F)),
  Category('doctor', 'Health', Icons.medical_services_rounded, Color(0xFF12A594)),
  Category('exercise', 'Exercise', Icons.directions_run_rounded, Color(0xFF30A46C)),
  Category('meeting', 'Event', Icons.event_rounded, Color(0xFF3E63DD)),
  Category('plants', 'Plants', Icons.local_florist_rounded, Color(0xFF46A758)),
  Category('pets', 'Pets', Icons.pets_rounded, Color(0xFFAD7F58)),
  Category('custom', 'Other', Icons.notifications_active_rounded, Color(0xFF0D74CE)),
];

Category categoryOf(String key) => categories.firstWhere((c) => c.key == key, orElse: () => categories.last);

/// One-tap starting points shown when creating a reminder.
class Template {
  final String label;
  final String category;
  final String title;
  final String notes;
  final int hour;
  final int minute;
  final RepeatRule repeat;
  final String? soundKey;
  const Template(this.label, this.category, this.title,
      {this.notes = '', this.hour = 9, this.minute = 0, this.repeat = const RepeatRule(), this.soundKey});
}

const templates = <Template>[
  Template('Take medicine', 'medicine', 'Take medicine', hour: 9, repeat: RepeatRule(type: 'daily')),
  Template('Drink water', 'water', 'Drink a glass of water',
      hour: 8, repeat: RepeatRule(type: 'hourly', interval: 120, windowEnd: 22 * 60), soundKey: 'water_drop'),
  Template('Pollution check (PUC)', 'vehicle', 'Renew vehicle pollution certificate',
      notes: 'Visit the PUC centre with your vehicle papers.', hour: 10, repeat: RepeatRule(type: 'monthly', interval: 6)),
  Template('Vehicle insurance', 'vehicle', 'Renew vehicle insurance', hour: 10, repeat: RepeatRule(type: 'yearly')),
  Template('Vehicle service', 'vehicle', 'Vehicle service due', hour: 10, repeat: RepeatRule(type: 'monthly', interval: 3)),
  Template('Pay a bill', 'bills', 'Pay electricity bill', hour: 11, repeat: RepeatRule(type: 'monthly')),
  Template('Birthday', 'birthday', 'Birthday', hour: 8, repeat: RepeatRule(type: 'yearly')),
  Template('Doctor visit', 'doctor', 'Doctor appointment', hour: 10),
  Template('Exercise', 'exercise', 'Time to exercise',
      hour: 6, minute: 30, repeat: RepeatRule(type: 'weekly', weekdays: [1, 2, 3, 4, 5])),
  Template('Water the plants', 'plants', 'Water the plants', hour: 7, repeat: RepeatRule(type: 'daily', interval: 2)),
];

String isoDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);
