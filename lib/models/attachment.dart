class Attachment {
  final String type;
  final String? name;
  final String? path;
  final String? dataBase64;
  final String? mimeType;
  final String? ocrText;

  Attachment({
    required this.type,
    this.name,
    this.path,
    this.dataBase64,
    this.mimeType,
    this.ocrText,
  });

  Map<String, dynamic> toJson() {
    return {
      'type': type,
      if (name != null) 'name': name,
      if (path != null) 'path': path,
      if (dataBase64 != null) 'data_base64': dataBase64,
      if (mimeType != null) 'mime_type': mimeType,
      if (ocrText != null) 'ocr_text': ocrText,
    };
  }

  factory Attachment.fromJson(Map<String, dynamic> json) {
    // 空安全：type 缺失或类型不符时用空字符串兜底，避免整个加载失败
    return Attachment(
      type: json['type'] as String? ?? '',
      name: json['name'] as String?,
      path: json['path'] as String?,
      dataBase64: json['data_base64'] as String?,
      mimeType: json['mime_type'] as String?,
      ocrText: json['ocr_text'] as String?,
    );
  }

  Attachment copyWith({
    String? type,
    String? name,
    String? path,
    String? dataBase64,
    String? mimeType,
    String? ocrText,
  }) {
    return Attachment(
      type: type ?? this.type,
      name: name ?? this.name,
      path: path ?? this.path,
      dataBase64: dataBase64 ?? this.dataBase64,
      mimeType: mimeType ?? this.mimeType,
      ocrText: ocrText ?? this.ocrText,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Attachment &&
        other.type == type &&
        other.name == name &&
        other.path == path &&
        other.dataBase64 == dataBase64 &&
        other.mimeType == mimeType &&
        other.ocrText == ocrText;
  }

  @override
  int get hashCode =>
      type.hashCode ^
      (name?.hashCode ?? 0) ^
      (path?.hashCode ?? 0) ^
      (dataBase64?.hashCode ?? 0) ^
      (mimeType?.hashCode ?? 0) ^
      (ocrText?.hashCode ?? 0);
}
