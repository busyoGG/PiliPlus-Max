class RoomInfo {
  int? uid;
  String? title;
  String? cover;
  String? appBackground;
  int? areaId;
  int? parentAreaId;

  RoomInfo({
    this.uid,
    this.title,
    this.cover,
    this.appBackground,
    this.areaId,
    this.parentAreaId,
  });

  /// 赛事分区（父分区 13 / 分区 561）的直播间会显示额外的「赛程」入口。
  bool get isEsportsArea => parentAreaId == 13 || areaId == 561;

  factory RoomInfo.fromJson(Map<String, dynamic> json) => RoomInfo(
    uid: json['uid'] as int?,
    title: json['title'] as String?,
    cover: json['cover'] as String?,
    appBackground: json['app_background'] as String?,
    areaId: json['area_id'] as int?,
    parentAreaId: json['parent_area_id'] as int?,
  );
}
