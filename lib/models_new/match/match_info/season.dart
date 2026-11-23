class MatchSeason {
  int? id;
  String? title;
  String? logo;

  Season({
    this.id,
    this.title,
    this.logo,
  });

  factory Season.fromJson(Map<String, dynamic> json) => Season(
    id: json['id'] as int?,
    title: json['title'] as String?,
    logo: json['logo'] as String?,
  );
}
