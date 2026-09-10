class AppConfig {
  // Author GitHub profile
  static const String authorGithubUrl = 'https://github.com/RichkovGit';

  // GitHub repository URL
  static const String githubRepositoryUrl =
      'https://github.com/RichkovGit/OpenWrtStudio';

  // GitHub issues URL (Bug Report)
  static const String githubIssuesUrl =
      'https://github.com/RichkovGit/OpenWrtStudio/issues';

  // Author Telegram Channel
  static const String authorTelegramUrl = 'https://t.me/RichkovChannel';

  // Program Telegram Channel
  static const String appTelegramUrl = 'https://t.me/OpenWrtStudio';

  // Reviewer mode configuration
  static const String reviewerModeKey = 'reviewer_mode_enabled';
  static const String mockDataPath = 'assets/mock/';
  static const Duration reviewerModeActivationDuration = Duration(seconds: 5);
  static const String reviewerModeWatermark = 'Reviewer Mode';
}
