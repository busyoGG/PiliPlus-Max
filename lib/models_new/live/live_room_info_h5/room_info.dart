class RoomInfo {
  int? uid;
  String? title;
  String? cover;
  String? appBackground;
  int? areaId;
  int? parentAreaId;
  String? areaName;
  String? parentAreaName;

  RoomInfo({
    this.uid,
    this.title,
    this.cover,
    this.appBackground,
    this.areaId,
    this.parentAreaId,
    this.areaName,
    this.parentAreaName,
  });

  factory RoomInfo.fromJson(Map<String, dynamic> json) => RoomInfo(
    uid: json['uid'] as int?,
    title: json['title'] as String?,
    cover: json['cover'] as String?,
    appBackground: json['app_background'] as String?,
    areaId: json['area_id'] as int?,
    parentAreaId: json['parent_area_id'] as int?,
    areaName: json['area_name'] as String?,
    parentAreaName: json['parent_area_name'] as String?,
  );

  /// 赛事分区（parent_area_id 13 / area_id 561）。
  bool get isEsportsArea => parentAreaId == 13 || areaId == 561;
}
