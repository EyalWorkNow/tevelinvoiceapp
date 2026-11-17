// "מסמך לחתימה" (server 0116, routes /sign-requests). A PDF the owner sends to
// a customer with fields placed on it; the customer fills and signs on the
// public page /s/:token. Geometry is normalized to the page (0..1, origin
// top-left) so the editor, the signer page and the flattened PDF agree.

import 'json.dart';

enum SignStatus { draft, sent, viewed, completed, cancelled, expired }

SignStatus signStatusOf(String? s) => switch (s) {
  'SENT' => SignStatus.sent,
  'VIEWED' => SignStatus.viewed,
  'COMPLETED' => SignStatus.completed,
  'CANCELLED' => SignStatus.cancelled,
  'EXPIRED' => SignStatus.expired,
  _ => SignStatus.draft,
};

String signStatusWire(SignStatus s) => s.name.toUpperCase();

enum SignFieldKind { signature, text, date, checkbox, initials }

SignFieldKind signFieldKindOf(String? s) => switch (s) {
  'TEXT' => SignFieldKind.text,
  'DATE' => SignFieldKind.date,
  'CHECKBOX' => SignFieldKind.checkbox,
  'INITIALS' => SignFieldKind.initials,
  _ => SignFieldKind.signature,
};

String signFieldKindWire(SignFieldKind k) => k.name.toUpperCase();

/// Smallest field edge the editor allows (server minimum is 0.01).
const double minFieldSide = 0.02;

/// Server limits (PUT /sign-requests/:id).
const int maxSignFields = 100;
const int maxFieldLabel = 80;

double _clamp(double v, double lo, double hi) =>
    v < lo ? lo : (v > hi ? hi : v);

double _d(Object? v) => v is num ? v.toDouble() : double.tryParse('$v') ?? 0;

/// A page size in PDF points (aspect only matters on the phone).
class SignPage {
  const SignPage(this.width, this.height);
  factory SignPage.fromJson(Map<String, dynamic> j) =>
      SignPage(_d(j['width']), _d(j['height']));
  final double width;
  final double height;

  /// height / width; A4 when the server sent nonsense.
  double get aspect => width > 0 && height > 0 ? height / width : 842 / 595;
}

class SignField {
  const SignField({
    this.id,
    required this.pageIndex,
    required this.kind,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    this.required = true,
    this.label,
    this.placeholder,
    this.value,
    this.filled = false,
  });

  factory SignField.fromJson(Map<String, dynamic> j) => SignField(
    id: jStr(j['id']),
    pageIndex: jIntOrNull(j['pageIndex']) ?? 0,
    kind: signFieldKindOf(jStr(j['kind'])),
    x: _d(j['x']),
    y: _d(j['y']),
    width: _d(j['width']),
    height: _d(j['height']),
    required: j['required'] != false,
    label: jStr(j['label']),
    placeholder: jStr(j['placeholder']),
    value: jStr(j['value']),
    filled: jBool(j['filled']),
  ).normalized();

  final String? id;
  final int pageIndex;
  final SignFieldKind kind;
  final double x;
  final double y;
  final double width;
  final double height;
  final bool required;
  final String? label;
  final String? placeholder;
  final String? value;
  final bool filled;

  /// Default size in page-WIDTH units (w, h); [placeAt] converts h by aspect.
  static (double, double) defaultSize(SignFieldKind kind) => switch (kind) {
    SignFieldKind.signature => (0.36, 0.12),
    SignFieldKind.initials => (0.14, 0.08),
    SignFieldKind.text => (0.36, 0.05),
    SignFieldKind.date => (0.22, 0.05),
    SignFieldKind.checkbox => (0.05, 0.05),
  };

  /// A new field of [kind] centred on the tap ([tx], [ty] normalized),
  /// kept inside the page. [aspect] = page height / width.
  static SignField placeAt(
    SignFieldKind kind,
    int pageIndex,
    double tx,
    double ty, {
    double aspect = 842 / 595,
  }) {
    final (w, hw) = defaultSize(kind);
    final h = hw / (aspect <= 0 ? 1 : aspect);
    return SignField(
      pageIndex: pageIndex,
      kind: kind,
      x: tx - w / 2,
      y: ty - h / 2,
      width: w,
      height: h,
    ).normalized();
  }

  /// Width/height in [minFieldSide, 1], then x/y moved so the box stays
  /// on the page. NaN/∞ become safe values.
  SignField normalized() {
    double f(double v, double fallback) => v.isFinite ? v : fallback;
    final w = _clamp(f(width, 0.2), minFieldSide, 1);
    final h = _clamp(f(height, 0.05), minFieldSide, 1);
    return copyWith(
      width: w,
      height: h,
      x: _clamp(f(x, 0), 0, 1 - w),
      y: _clamp(f(y, 0), 0, 1 - h),
    );
  }

  /// Drag by a normalized delta; the size never changes.
  SignField moved(double dx, double dy) =>
      copyWith(x: x + dx, y: y + dy).normalized();

  /// Resize from the bottom-right corner; the top-left stays put and the
  /// box never crosses the page edge.
  SignField resized(double dw, double dh) => copyWith(
    width: _clamp(width + dw, minFieldSide, 1 - x),
    height: _clamp(height + dh, minFieldSide, 1 - y),
  ).normalized();

  SignField copyWith({
    double? x,
    double? y,
    double? width,
    double? height,
    bool? required,
    String? label,
    String? placeholder,
    bool clearLabel = false,
    bool clearPlaceholder = false,
  }) => SignField(
    id: id,
    pageIndex: pageIndex,
    kind: kind,
    x: x ?? this.x,
    y: y ?? this.y,
    width: width ?? this.width,
    height: height ?? this.height,
    required: required ?? this.required,
    label: clearLabel ? null : (label ?? this.label),
    placeholder: clearPlaceholder ? null : (placeholder ?? this.placeholder),
    value: value,
    filled: filled,
  );

  static String? _short(String? s) {
    final t = s?.trim() ?? '';
    if (t.isEmpty) return null;
    return t.length > maxFieldLabel ? t.substring(0, maxFieldLabel) : t;
  }

  /// PUT body entry (rounded to 4 decimals = ~0.06 mm on A4).
  Map<String, dynamic> toJson() {
    final n = normalized();
    double r(double v) => (v * 10000).floorToDouble() / 10000;
    return {
      'pageIndex': pageIndex,
      'kind': signFieldKindWire(kind),
      'x': r(n.x),
      'y': r(n.y),
      'width': r(n.width),
      'height': r(n.height),
      'required': required,
      'label': _short(label),
      'placeholder': _short(placeholder),
    };
  }
}

class SignEvent {
  const SignEvent({
    required this.type,
    required this.occurredAt,
    this.ip,
    this.userAgent,
    this.signerName,
    this.channel,
  });
  factory SignEvent.fromJson(Map<String, dynamic> j) => SignEvent(
    type: jStr(j['type']) ?? '',
    occurredAt: jStr(j['occurredAt']) ?? '',
    ip: jStr(j['ip']),
    userAgent: jStr(j['userAgent']),
    signerName: jStr(j['signerName']),
    channel: jStr(j['channel']),
  );
  final String type;
  final String occurredAt;
  final String? ip;
  final String? userAgent;
  final String? signerName;
  final String? channel;
}

/// List row (Summary) and full view (View) in one class: the View fields
/// are empty on list rows.
class SignRequest {
  const SignRequest({
    required this.id,
    required this.title,
    required this.status,
    this.signerName,
    this.signerEmail,
    this.signerPhone,
    this.customerId,
    this.message,
    this.createdAt,
    this.sentAt,
    this.viewedAt,
    this.completedAt,
    this.expiresOn,
    this.pageCount = 0,
    this.pages = const [],
    this.fields = const [],
    this.events = const [],
    this.originalSha256,
    this.completedSha256,
    this.sealed,
    this.sealNote,
    this.notifyOnView = false,
  });

  factory SignRequest.fromJson(Map<String, dynamic> j) {
    final pages = [
      for (final p in (j['pages'] is List ? j['pages'] as List : const []))
        if (p is Map<String, dynamic>) SignPage.fromJson(p),
    ];
    return SignRequest(
      id: jStr(j['id']) ?? '',
      title: jStr(j['title']) ?? '',
      status: signStatusOf(jStr(j['status'])),
      signerName: jStr(j['signerName']),
      signerEmail: jStr(j['signerEmail']),
      signerPhone: jStr(j['signerPhone']),
      customerId: jStr(j['customerId']),
      message: jStr(j['message']),
      createdAt: jStr(j['createdAt']),
      sentAt: jStr(j['sentAt']),
      viewedAt: jStr(j['viewedAt']),
      completedAt: jStr(j['completedAt']),
      expiresOn: jStr(j['expiresOn']),
      pageCount: jIntOrNull(j['pageCount']) ?? pages.length,
      pages: pages,
      fields: [
        for (final f in (j['fields'] is List ? j['fields'] as List : const []))
          if (f is Map<String, dynamic>) SignField.fromJson(f),
      ],
      events: [
        for (final e in (j['events'] is List ? j['events'] as List : const []))
          if (e is Map<String, dynamic>) SignEvent.fromJson(e),
      ],
      originalSha256: jStr(j['originalSha256']),
      completedSha256: jStr(j['completedSha256']),
      sealed: j['sealed'] is bool ? j['sealed'] as bool : null,
      sealNote: jStr(j['sealNote']),
      notifyOnView: jBool(j['notifyOnView']),
    );
  }

  final String id;
  final String title;
  final SignStatus status;
  final String? signerName;
  final String? signerEmail;
  final String? signerPhone;
  final String? customerId;
  final String? message;
  final String? createdAt;
  final String? sentAt;
  final String? viewedAt;
  final String? completedAt;
  final String? expiresOn;
  final int pageCount;
  final List<SignPage> pages;
  final List<SignField> fields;
  final List<SignEvent> events;
  final String? originalSha256;
  final String? completedSha256;
  final bool? sealed;
  final String? sealNote;

  /// Push "המסמך נצפה" to the sender (opt-in per request).
  final bool notifyOnView;

  bool get editable => status == SignStatus.draft;
  bool get waiting => status == SignStatus.sent || status == SignStatus.viewed;
  bool get cancellable => editable || waiting;

  /// Page [i] size; A4 portrait when the view has no pages list.
  SignPage page(int i) =>
      i >= 0 && i < pages.length ? pages[i] : const SignPage(595, 842);
}
