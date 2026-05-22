class NotificationItem {
  final String   id;
  final String   type;
  final String   title;
  final String   body;
  final String   timeLabel;
  final bool     isRead;
  final DateTime createdAt;

  const NotificationItem({
    required this.id,
    required this.type,
    required this.title,
    required this.body,
    required this.timeLabel,
    required this.isRead,
    required this.createdAt,
  });

  NotificationItem copyWith({bool? isRead}) => NotificationItem(
    id: id, type: type, title: title, body: body,
    timeLabel: timeLabel, createdAt: createdAt,
    isRead: isRead ?? this.isRead,
  );

  factory NotificationItem.fromJson(Map<String, dynamic> j) =>
      NotificationItem(
        id:        j['id']         as String,
        type:      j['type']       as String,
        title:     j['title']      as String,
        body:      j['body']       as String,
        timeLabel: j['time_label'] as String? ?? '',
        isRead:    j['is_read']    as bool?   ?? false,
        createdAt: DateTime.tryParse(j['created_at'] as String? ?? '') ?? DateTime.now(),
      );
}