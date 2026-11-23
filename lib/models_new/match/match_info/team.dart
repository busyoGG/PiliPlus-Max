class MatchTeam {
  String? title;
  String? logo;
  String? logoFull;

  MatchTeam({
    this.title,
    this.logo,
    this.logoFull,
  });

  /// 赛程接口返回的是 name/icon，赛事详情接口返回 title/logo。
  factory MatchTeam.fromJson(Map<String, dynamic> json) => MatchTeam(
    title: (json['title'] ?? json['name']) as String?,
    logo: (json['logo'] ?? json['icon']) as String?,
    logoFull: json['logoFull'] as String?,
  );
}
