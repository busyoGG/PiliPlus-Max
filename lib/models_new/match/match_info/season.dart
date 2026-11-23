class MatchSeason {
  int? id;
  String? title;
  String? logo;

  MatchSeason({
    this.id,
    this.title,
    this.logo,
  });

  factory MatchSeason.fromJson(Map<String, dynamic> json) => MatchSeason(
    id: json['id'] as int?,
    title: json['title'] as String?,
    logo: json['logo'] as String?,
  );
}
