/// Agent definition at the configuration level.
///
/// This is distinct from feat-route's AgentDefinition which is the
/// runtime representation. AgentDef captures what's declared in YAML.
class AgentDef {
  final String name;
  final List<String> skills;
  final String? profileId;
  final String? philosophyId;
  final Map<String, dynamic> options;

  const AgentDef({
    required this.name,
    this.skills = const [],
    this.profileId,
    this.philosophyId,
    this.options = const {},
  });

  factory AgentDef.fromJson(Map<String, dynamic> json) {
    return AgentDef(
      name: json['name'] as String,
      skills: (json['skills'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          const [],
      profileId: json['profileId'] as String?,
      philosophyId: json['philosophyId'] as String?,
      options:
          (json['options'] as Map<String, dynamic>?) ?? const {},
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        if (skills.isNotEmpty) 'skills': skills,
        if (profileId != null) 'profileId': profileId,
        if (philosophyId != null) 'philosophyId': philosophyId,
        if (options.isNotEmpty) 'options': options,
      };
}
