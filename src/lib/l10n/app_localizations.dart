import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_ja.dart';
import 'app_localizations_ko.dart';
import 'app_localizations_zh.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('ja'),
    Locale('ko'),
    Locale('zh'),
    Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hans'),
    Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'),
  ];

  /// No description provided for @home.
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get home;

  /// No description provided for @courses.
  ///
  /// In en, this message translates to:
  /// **'Courses'**
  String get courses;

  /// No description provided for @studyRoom.
  ///
  /// In en, this message translates to:
  /// **'Study Room'**
  String get studyRoom;

  /// No description provided for @studyRoomTab.
  ///
  /// In en, this message translates to:
  /// **'Study'**
  String get studyRoomTab;

  /// No description provided for @review.
  ///
  /// In en, this message translates to:
  /// **'Review'**
  String get review;

  /// No description provided for @profile.
  ///
  /// In en, this message translates to:
  /// **'Me'**
  String get profile;

  /// No description provided for @unlocked.
  ///
  /// In en, this message translates to:
  /// **'Unlocked'**
  String get unlocked;

  /// No description provided for @locked.
  ///
  /// In en, this message translates to:
  /// **'Locked'**
  String get locked;

  /// No description provided for @startLearning.
  ///
  /// In en, this message translates to:
  /// **'Start learning'**
  String get startLearning;

  /// No description provided for @welcomeTitle.
  ///
  /// In en, this message translates to:
  /// **'Your language journey\nstarts here.'**
  String get welcomeTitle;

  /// No description provided for @welcomeBody.
  ///
  /// In en, this message translates to:
  /// **'Start with a book and a voice. Let words, grammar, and expression take root.'**
  String get welcomeBody;

  /// No description provided for @localRecords.
  ///
  /// In en, this message translates to:
  /// **'No account needed · Learning records stay on this device'**
  String get localRecords;

  /// No description provided for @settings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settings;

  /// No description provided for @interfaceLanguage.
  ///
  /// In en, this message translates to:
  /// **'Interface language'**
  String get interfaceLanguage;

  /// No description provided for @learningTarget.
  ///
  /// In en, this message translates to:
  /// **'Learning target'**
  String get learningTarget;

  /// No description provided for @independentLanguages.
  ///
  /// In en, this message translates to:
  /// **'Interface language, learning target, and selected content are independent.'**
  String get independentLanguages;

  /// No description provided for @followSystem.
  ///
  /// In en, this message translates to:
  /// **'Follow system'**
  String get followSystem;

  /// No description provided for @japanese.
  ///
  /// In en, this message translates to:
  /// **'Japanese'**
  String get japanese;

  /// No description provided for @english.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get english;

  /// No description provided for @appearance.
  ///
  /// In en, this message translates to:
  /// **'Appearance'**
  String get appearance;

  /// No description provided for @light.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get light;

  /// No description provided for @dark.
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get dark;

  /// No description provided for @fontSize.
  ///
  /// In en, this message translates to:
  /// **'Text size'**
  String get fontSize;

  /// No description provided for @dailyGoal.
  ///
  /// In en, this message translates to:
  /// **'Daily goal'**
  String get dailyGoal;

  /// No description provided for @lightGoal.
  ///
  /// In en, this message translates to:
  /// **'Easy · 5 minutes'**
  String get lightGoal;

  /// No description provided for @normalGoal.
  ///
  /// In en, this message translates to:
  /// **'Standard · 10 minutes'**
  String get normalGoal;

  /// No description provided for @advancedGoal.
  ///
  /// In en, this message translates to:
  /// **'Focused · 20 minutes'**
  String get advancedGoal;

  /// No description provided for @information.
  ///
  /// In en, this message translates to:
  /// **'Information'**
  String get information;

  /// No description provided for @privacy.
  ///
  /// In en, this message translates to:
  /// **'Privacy policy'**
  String get privacy;

  /// No description provided for @privacySubtitle.
  ///
  /// In en, this message translates to:
  /// **'How information and privacy are handled'**
  String get privacySubtitle;

  /// No description provided for @copyright.
  ///
  /// In en, this message translates to:
  /// **'Content and copyright'**
  String get copyright;

  /// No description provided for @copyrightSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Content, audio, images, and copyright notices'**
  String get copyrightSubtitle;

  /// No description provided for @about.
  ///
  /// In en, this message translates to:
  /// **'About'**
  String get about;

  /// No description provided for @contact.
  ///
  /// In en, this message translates to:
  /// **'Contact us'**
  String get contact;

  /// No description provided for @qqGroup.
  ///
  /// In en, this message translates to:
  /// **'QQ group: 1103815459'**
  String get qqGroup;

  /// No description provided for @brandSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Where language learning begins'**
  String get brandSubtitle;

  /// No description provided for @resources.
  ///
  /// In en, this message translates to:
  /// **'Resource packs'**
  String get resources;

  /// No description provided for @learningResources.
  ///
  /// In en, this message translates to:
  /// **'Learning resources'**
  String get learningResources;

  /// No description provided for @learningResourcesSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Download and update learning resources'**
  String get learningResourcesSubtitle;

  /// No description provided for @studyResources.
  ///
  /// In en, this message translates to:
  /// **'Study resources'**
  String get studyResources;

  /// No description provided for @studyResourcesSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Download and update study resources'**
  String get studyResourcesSubtitle;

  /// No description provided for @system.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get system;

  /// No description provided for @basicKnowledge.
  ///
  /// In en, this message translates to:
  /// **'Language essentials'**
  String get basicKnowledge;

  /// No description provided for @rate.
  ///
  /// In en, this message translates to:
  /// **'Rate the app'**
  String get rate;

  /// No description provided for @rateSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Rate 语之初 on the App Store'**
  String get rateSubtitle;

  /// No description provided for @rateFailed.
  ///
  /// In en, this message translates to:
  /// **'The review page could not be opened. Please try again later.'**
  String get rateFailed;

  /// No description provided for @tip.
  ///
  /// In en, this message translates to:
  /// **'Support the developer'**
  String get tip;

  /// No description provided for @tipSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Support the developer through the App Store'**
  String get tipSubtitle;

  /// No description provided for @notices.
  ///
  /// In en, this message translates to:
  /// **'Announcements'**
  String get notices;

  /// No description provided for @noticesSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Latest and past announcements'**
  String get noticesSubtitle;

  /// No description provided for @purchaseUnlocked.
  ///
  /// In en, this message translates to:
  /// **'Study Room · Unlocked'**
  String get purchaseUnlocked;

  /// No description provided for @purchaseLocked.
  ///
  /// In en, this message translates to:
  /// **'Study Room · Not purchased'**
  String get purchaseLocked;

  /// No description provided for @purchaseChecking.
  ///
  /// In en, this message translates to:
  /// **'Study Room · Checking purchase…'**
  String get purchaseChecking;

  /// No description provided for @purchaseAvailable.
  ///
  /// In en, this message translates to:
  /// **'Study Room features are available'**
  String get purchaseAvailable;

  /// No description provided for @purchaseDetails.
  ///
  /// In en, this message translates to:
  /// **'View Study Room purchase details'**
  String get purchaseDetails;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @delete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get delete;

  /// No description provided for @close.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get close;

  /// No description provided for @back.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get back;

  /// No description provided for @save.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// No description provided for @saving.
  ///
  /// In en, this message translates to:
  /// **'Saving'**
  String get saving;

  /// No description provided for @retry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get retry;

  /// No description provided for @selectContent.
  ///
  /// In en, this message translates to:
  /// **'Choose content'**
  String get selectContent;

  /// No description provided for @continueLearning.
  ///
  /// In en, this message translates to:
  /// **'Continue learning'**
  String get continueLearning;

  /// No description provided for @chooseToStart.
  ///
  /// In en, this message translates to:
  /// **'Choose content to start learning'**
  String get chooseToStart;

  /// No description provided for @readingContent.
  ///
  /// In en, this message translates to:
  /// **'Loading selected content…'**
  String get readingContent;

  /// No description provided for @loading.
  ///
  /// In en, this message translates to:
  /// **'Loading'**
  String get loading;

  /// No description provided for @unavailable.
  ///
  /// In en, this message translates to:
  /// **'Currently unavailable'**
  String get unavailable;

  /// No description provided for @currentLesson.
  ///
  /// In en, this message translates to:
  /// **'Current lesson'**
  String get currentLesson;

  /// No description provided for @lessonProgress.
  ///
  /// In en, this message translates to:
  /// **'Lesson progress'**
  String get lessonProgress;

  /// No description provided for @contentProgress.
  ///
  /// In en, this message translates to:
  /// **'Content progress'**
  String get contentProgress;

  /// No description provided for @quickStudy.
  ///
  /// In en, this message translates to:
  /// **'Quick study'**
  String get quickStudy;

  /// No description provided for @reviewDue.
  ///
  /// In en, this message translates to:
  /// **'Reviews due'**
  String get reviewDue;

  /// No description provided for @studyOverview.
  ///
  /// In en, this message translates to:
  /// **'Learning overview'**
  String get studyOverview;

  /// No description provided for @practiceRecords.
  ///
  /// In en, this message translates to:
  /// **'Practice history'**
  String get practiceRecords;

  /// No description provided for @mistakeRecords.
  ///
  /// In en, this message translates to:
  /// **'Mistake history'**
  String get mistakeRecords;

  /// No description provided for @completedLessons.
  ///
  /// In en, this message translates to:
  /// **'Completed lessons'**
  String get completedLessons;

  /// No description provided for @answeredCount.
  ///
  /// In en, this message translates to:
  /// **'Total answers'**
  String get answeredCount;

  /// No description provided for @accuracy.
  ///
  /// In en, this message translates to:
  /// **'Accuracy'**
  String get accuracy;

  /// No description provided for @studyAdvice.
  ///
  /// In en, this message translates to:
  /// **'Learning tips'**
  String get studyAdvice;

  /// No description provided for @morning.
  ///
  /// In en, this message translates to:
  /// **'Good morning'**
  String get morning;

  /// No description provided for @afternoon.
  ///
  /// In en, this message translates to:
  /// **'Good afternoon'**
  String get afternoon;

  /// No description provided for @evening.
  ///
  /// In en, this message translates to:
  /// **'Good evening'**
  String get evening;

  /// No description provided for @lessonCompletionHint.
  ///
  /// In en, this message translates to:
  /// **'Complete words, texts, and grammar to reach 100% for this lesson.'**
  String get lessonCompletionHint;

  /// No description provided for @noReviewsToday.
  ///
  /// In en, this message translates to:
  /// **'No cards are due today. Complete a lesson to add new knowledge to your review plan.'**
  String get noReviewsToday;

  /// No description provided for @myCourses.
  ///
  /// In en, this message translates to:
  /// **'My courses'**
  String get myCourses;

  /// No description provided for @noContentSelected.
  ///
  /// In en, this message translates to:
  /// **'No content selected'**
  String get noContentSelected;

  /// No description provided for @chooseBookHint.
  ///
  /// In en, this message translates to:
  /// **'Choose a book and start your language journey with the first lesson.'**
  String get chooseBookHint;

  /// No description provided for @changeContent.
  ///
  /// In en, this message translates to:
  /// **'Change content'**
  String get changeContent;

  /// No description provided for @courseList.
  ///
  /// In en, this message translates to:
  /// **'Lesson list'**
  String get courseList;

  /// No description provided for @recordingsReady.
  ///
  /// In en, this message translates to:
  /// **'Text and word recordings are ready'**
  String get recordingsReady;

  /// No description provided for @memoryReview.
  ///
  /// In en, this message translates to:
  /// **'Memory review'**
  String get memoryReview;

  /// No description provided for @memorySlogan.
  ///
  /// In en, this message translates to:
  /// **'Meet it again before you forget.'**
  String get memorySlogan;

  /// No description provided for @dueToday.
  ///
  /// In en, this message translates to:
  /// **'Due today'**
  String get dueToday;

  /// No description provided for @preparing.
  ///
  /// In en, this message translates to:
  /// **'Preparing'**
  String get preparing;

  /// No description provided for @startReview.
  ///
  /// In en, this message translates to:
  /// **'Start review'**
  String get startReview;

  /// No description provided for @memoryStats.
  ///
  /// In en, this message translates to:
  /// **'Memory statistics'**
  String get memoryStats;

  /// No description provided for @studyCards.
  ///
  /// In en, this message translates to:
  /// **'Learning cards'**
  String get studyCards;

  /// No description provided for @pastMistakes.
  ///
  /// In en, this message translates to:
  /// **'Past mistakes'**
  String get pastMistakes;

  /// No description provided for @reviewRules.
  ///
  /// In en, this message translates to:
  /// **'Review rules'**
  String get reviewRules;

  /// No description provided for @reviewRulesBody.
  ///
  /// In en, this message translates to:
  /// **'Correct cards return after 2, 4, 7, 14, then 30 days. Incorrect cards return at the end of this round until answered correctly. Answers are checked and saved immediately.'**
  String get reviewRulesBody;

  /// No description provided for @practice.
  ///
  /// In en, this message translates to:
  /// **'Practice'**
  String get practice;

  /// No description provided for @practiceResults.
  ///
  /// In en, this message translates to:
  /// **'Practice results'**
  String get practiceResults;

  /// No description provided for @correctAnswer.
  ///
  /// In en, this message translates to:
  /// **'Correct answer'**
  String get correctAnswer;

  /// No description provided for @wrongSelection.
  ///
  /// In en, this message translates to:
  /// **'Incorrect choice'**
  String get wrongSelection;

  /// No description provided for @correct.
  ///
  /// In en, this message translates to:
  /// **'Correct'**
  String get correct;

  /// No description provided for @wrong.
  ///
  /// In en, this message translates to:
  /// **'Incorrect'**
  String get wrong;

  /// No description provided for @unanswered.
  ///
  /// In en, this message translates to:
  /// **'Unanswered'**
  String get unanswered;

  /// No description provided for @answeredCorrectly.
  ///
  /// In en, this message translates to:
  /// **'Correct answer'**
  String get answeredCorrectly;

  /// No description provided for @explanation.
  ///
  /// In en, this message translates to:
  /// **'Explanation'**
  String get explanation;

  /// No description provided for @viewResults.
  ///
  /// In en, this message translates to:
  /// **'View results'**
  String get viewResults;

  /// No description provided for @nextQuestion.
  ///
  /// In en, this message translates to:
  /// **'Next question'**
  String get nextQuestion;

  /// No description provided for @practiceSaved.
  ///
  /// In en, this message translates to:
  /// **'Practice saved. You can revisit mistakes in Mistake history on the home page.'**
  String get practiceSaved;

  /// No description provided for @instantSaveHint.
  ///
  /// In en, this message translates to:
  /// **'Answers are checked and saved immediately. Resume later from Practice history.'**
  String get instantSaveHint;

  /// No description provided for @rateQuestion.
  ///
  /// In en, this message translates to:
  /// **'How did this question feel? (Optional)'**
  String get rateQuestion;

  /// No description provided for @forgotten.
  ///
  /// In en, this message translates to:
  /// **'Forgotten'**
  String get forgotten;

  /// No description provided for @hard.
  ///
  /// In en, this message translates to:
  /// **'Hard'**
  String get hard;

  /// No description provided for @good.
  ///
  /// In en, this message translates to:
  /// **'Okay'**
  String get good;

  /// No description provided for @easy.
  ///
  /// In en, this message translates to:
  /// **'I knew it'**
  String get easy;

  /// No description provided for @completed.
  ///
  /// In en, this message translates to:
  /// **'Completed'**
  String get completed;

  /// No description provided for @incomplete.
  ///
  /// In en, this message translates to:
  /// **'Incomplete'**
  String get incomplete;

  /// No description provided for @continuePractice.
  ///
  /// In en, this message translates to:
  /// **'Continue practice'**
  String get continuePractice;

  /// No description provided for @practiceDetails.
  ///
  /// In en, this message translates to:
  /// **'Practice details'**
  String get practiceDetails;

  /// No description provided for @noPracticeRecords.
  ///
  /// In en, this message translates to:
  /// **'No practice history yet.'**
  String get noPracticeRecords;

  /// No description provided for @noMistakes.
  ///
  /// In en, this message translates to:
  /// **'No mistakes yet'**
  String get noMistakes;

  /// No description provided for @noDueQuestions.
  ///
  /// In en, this message translates to:
  /// **'No reviews due'**
  String get noDueQuestions;

  /// No description provided for @fontSystemHint.
  ///
  /// In en, this message translates to:
  /// **'Use the system text size'**
  String get fontSystemHint;

  /// No description provided for @fontRange.
  ///
  /// In en, this message translates to:
  /// **'90% Smaller · 100% Standard · 150% Largest'**
  String get fontRange;

  /// No description provided for @preview.
  ///
  /// In en, this message translates to:
  /// **'Preview'**
  String get preview;

  /// No description provided for @fontSaveHint.
  ///
  /// In en, this message translates to:
  /// **'Applies throughout the app after saving. A custom size replaces system scaling and is kept after restarting.'**
  String get fontSaveHint;

  /// No description provided for @restoreDefault.
  ///
  /// In en, this message translates to:
  /// **'Reset to default (follow system)'**
  String get restoreDefault;

  /// No description provided for @saveFailed.
  ///
  /// In en, this message translates to:
  /// **'Settings were not saved. Please try again.'**
  String get saveFailed;

  /// No description provided for @playbackSpeed.
  ///
  /// In en, this message translates to:
  /// **'Playback speed'**
  String get playbackSpeed;

  /// No description provided for @stopPlayback.
  ///
  /// In en, this message translates to:
  /// **'Stop playback'**
  String get stopPlayback;

  /// No description provided for @continuousPlayback.
  ///
  /// In en, this message translates to:
  /// **'Continuous playback'**
  String get continuousPlayback;

  /// No description provided for @stopping.
  ///
  /// In en, this message translates to:
  /// **'Stopping'**
  String get stopping;

  /// No description provided for @stoppingEllipsis.
  ///
  /// In en, this message translates to:
  /// **'Stopping…'**
  String get stoppingEllipsis;

  /// No description provided for @paused.
  ///
  /// In en, this message translates to:
  /// **'Paused'**
  String get paused;

  /// No description provided for @playbackGap.
  ///
  /// In en, this message translates to:
  /// **'Between tracks'**
  String get playbackGap;

  /// No description provided for @playing.
  ///
  /// In en, this message translates to:
  /// **'Playing'**
  String get playing;

  /// No description provided for @stopFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not stop playback. Try again.'**
  String get stopFailed;

  /// No description provided for @kana.
  ///
  /// In en, this message translates to:
  /// **'Kana chart'**
  String get kana;

  /// No description provided for @hiragana.
  ///
  /// In en, this message translates to:
  /// **'Hiragana'**
  String get hiragana;

  /// No description provided for @katakana.
  ///
  /// In en, this message translates to:
  /// **'Katakana'**
  String get katakana;

  /// No description provided for @unvoiced.
  ///
  /// In en, this message translates to:
  /// **'Unvoiced sounds'**
  String get unvoiced;

  /// No description provided for @voiced.
  ///
  /// In en, this message translates to:
  /// **'Voiced and semi-voiced sounds'**
  String get voiced;

  /// No description provided for @contracted.
  ///
  /// In en, this message translates to:
  /// **'Contracted sounds'**
  String get contracted;

  /// No description provided for @playListening.
  ///
  /// In en, this message translates to:
  /// **'Play listening audio'**
  String get playListening;

  /// No description provided for @practiceListening.
  ///
  /// In en, this message translates to:
  /// **'Practice listening'**
  String get practiceListening;

  /// No description provided for @practiceImage.
  ///
  /// In en, this message translates to:
  /// **'Practice illustration'**
  String get practiceImage;

  /// No description provided for @interactivePracticeImage.
  ///
  /// In en, this message translates to:
  /// **'Interactive practice illustration'**
  String get interactivePracticeImage;

  /// No description provided for @unsupportedMedia.
  ///
  /// In en, this message translates to:
  /// **'This practice media type is not supported yet.'**
  String get unsupportedMedia;

  /// No description provided for @content.
  ///
  /// In en, this message translates to:
  /// **'Content'**
  String get content;

  /// No description provided for @resourceOperation.
  ///
  /// In en, this message translates to:
  /// **'Resource operation'**
  String get resourceOperation;

  /// No description provided for @resourceUpdate.
  ///
  /// In en, this message translates to:
  /// **'Resource update'**
  String get resourceUpdate;

  /// No description provided for @resourceDownload.
  ///
  /// In en, this message translates to:
  /// **'Resource download'**
  String get resourceDownload;

  /// No description provided for @contentSwitch.
  ///
  /// In en, this message translates to:
  /// **'Content change'**
  String get contentSwitch;

  /// No description provided for @resourceDelete.
  ///
  /// In en, this message translates to:
  /// **'Resource removal'**
  String get resourceDelete;

  /// No description provided for @offlineReady.
  ///
  /// In en, this message translates to:
  /// **'Available offline'**
  String get offlineReady;

  /// No description provided for @installedOffline.
  ///
  /// In en, this message translates to:
  /// **'Content installed. You can learn offline.'**
  String get installedOffline;

  /// No description provided for @localDeleted.
  ///
  /// In en, this message translates to:
  /// **'Local learning resources deleted. Learning records were kept.'**
  String get localDeleted;

  /// No description provided for @serverRemovedReady.
  ///
  /// In en, this message translates to:
  /// **'Removed from server; local content is available offline'**
  String get serverRemovedReady;

  /// No description provided for @serverRemovedBroken.
  ///
  /// In en, this message translates to:
  /// **'Local resources damaged and removed from server. You can delete local data.'**
  String get serverRemovedBroken;

  /// No description provided for @repairAudio.
  ///
  /// In en, this message translates to:
  /// **'Audio is missing or resources need repair. Download again.'**
  String get repairAudio;

  /// No description provided for @brokenLocal.
  ///
  /// In en, this message translates to:
  /// **'Local resources damaged. You can delete local data.'**
  String get brokenLocal;

  /// No description provided for @downloadAfterSelection.
  ///
  /// In en, this message translates to:
  /// **'Select to download'**
  String get downloadAfterSelection;

  /// No description provided for @processingContent.
  ///
  /// In en, this message translates to:
  /// **'Processing content'**
  String get processingContent;

  /// No description provided for @updateContent.
  ///
  /// In en, this message translates to:
  /// **'Update content'**
  String get updateContent;

  /// No description provided for @downloadContent.
  ///
  /// In en, this message translates to:
  /// **'Download content'**
  String get downloadContent;

  /// No description provided for @deleteLocalContent.
  ///
  /// In en, this message translates to:
  /// **'Delete local content'**
  String get deleteLocalContent;

  /// No description provided for @confirmDeleteContent.
  ///
  /// In en, this message translates to:
  /// **'Delete local content?'**
  String get confirmDeleteContent;

  /// No description provided for @checkingContent.
  ///
  /// In en, this message translates to:
  /// **'Checking content'**
  String get checkingContent;

  /// No description provided for @refreshContent.
  ///
  /// In en, this message translates to:
  /// **'Refresh content'**
  String get refreshContent;

  /// No description provided for @whereToStart.
  ///
  /// In en, this message translates to:
  /// **'Where will you start?'**
  String get whereToStart;

  /// No description provided for @contentSwitchHint.
  ///
  /// In en, this message translates to:
  /// **'Switch content at any time. Learning records are kept separately.'**
  String get contentSwitchHint;

  /// No description provided for @localOfflineHint.
  ///
  /// In en, this message translates to:
  /// **'Local content remains available for offline learning.'**
  String get localOfflineHint;

  /// No description provided for @retryDownload.
  ///
  /// In en, this message translates to:
  /// **'Retry download'**
  String get retryDownload;

  /// No description provided for @openSettings.
  ///
  /// In en, this message translates to:
  /// **'Open Settings'**
  String get openSettings;

  /// No description provided for @checkAgain.
  ///
  /// In en, this message translates to:
  /// **'Check again'**
  String get checkAgain;

  /// No description provided for @noCatalog.
  ///
  /// In en, this message translates to:
  /// **'No content catalog yet. Refresh to load it.'**
  String get noCatalog;

  /// No description provided for @resourceStateFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not read resource status. Refresh and try again.'**
  String get resourceStateFailed;

  /// No description provided for @networkSettingsHint.
  ///
  /// In en, this message translates to:
  /// **'Open system Settings, find 语之初, and check wireless data access.'**
  String get networkSettingsHint;

  /// No description provided for @processingFailed.
  ///
  /// In en, this message translates to:
  /// **'Operation failed'**
  String get processingFailed;

  /// No description provided for @catalogUpdateFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not update the content catalog'**
  String get catalogUpdateFailed;

  /// No description provided for @resourcesUpdateFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not update learning resources'**
  String get resourcesUpdateFailed;

  /// No description provided for @validationError.
  ///
  /// In en, this message translates to:
  /// **'Content validation failed'**
  String get validationError;

  /// No description provided for @learningReadFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not load learning data'**
  String get learningReadFailed;

  /// No description provided for @learningRetry.
  ///
  /// In en, this message translates to:
  /// **'Could not load learning data. Try again.'**
  String get learningRetry;

  /// No description provided for @learningUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Learning resources are unavailable. Open Choose content to resolve this.'**
  String get learningUnavailable;

  /// No description provided for @noLessons.
  ///
  /// In en, this message translates to:
  /// **'This content has no lessons. Open Choose content.'**
  String get noLessons;

  /// No description provided for @refreshStale.
  ///
  /// In en, this message translates to:
  /// **'Refresh failed. Showing previous data. Tap to retry.'**
  String get refreshStale;

  /// No description provided for @overviewRetry.
  ///
  /// In en, this message translates to:
  /// **'Could not load the overview. Tap to retry.'**
  String get overviewRetry;

  /// No description provided for @practiceRetry.
  ///
  /// In en, this message translates to:
  /// **'Could not load practice. Tap to retry.'**
  String get practiceRetry;

  /// No description provided for @answersRetry.
  ///
  /// In en, this message translates to:
  /// **'Could not load answers. Tap to retry.'**
  String get answersRetry;

  /// No description provided for @recordsRetry.
  ///
  /// In en, this message translates to:
  /// **'Could not load history. Tap to retry.'**
  String get recordsRetry;

  /// No description provided for @detailsRetry.
  ///
  /// In en, this message translates to:
  /// **'Could not load details. Tap to retry.'**
  String get detailsRetry;

  /// No description provided for @kanaRetry.
  ///
  /// In en, this message translates to:
  /// **'Could not load the kana chart. Tap to retry.'**
  String get kanaRetry;

  /// No description provided for @appIcon.
  ///
  /// In en, this message translates to:
  /// **'语之初 app icon'**
  String get appIcon;

  /// No description provided for @license.
  ///
  /// In en, this message translates to:
  /// **'Glass component open-source license'**
  String get license;

  /// No description provided for @licenseUnavailable.
  ///
  /// In en, this message translates to:
  /// **'License information could not be loaded.'**
  String get licenseUnavailable;

  /// No description provided for @uiError.
  ///
  /// In en, this message translates to:
  /// **'Could not display this page. Please reopen it.'**
  String get uiError;

  /// No description provided for @startupError.
  ///
  /// In en, this message translates to:
  /// **'Local data could not be opened'**
  String get startupError;

  /// No description provided for @startupHint.
  ///
  /// In en, this message translates to:
  /// **'Please reopen the app. Your existing database will not be deleted or rebuilt automatically.'**
  String get startupHint;

  /// No description provided for @operationFailed.
  ///
  /// In en, this message translates to:
  /// **'Operation failed. Please try again.'**
  String get operationFailed;

  /// No description provided for @cancelled.
  ///
  /// In en, this message translates to:
  /// **'Cancelled'**
  String get cancelled;

  /// No description provided for @hashMismatch.
  ///
  /// In en, this message translates to:
  /// **'The pack and catalog versions differ. Refresh the catalog and try again.'**
  String get hashMismatch;

  /// No description provided for @spaceUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Storage space could not be checked. Please try again.'**
  String get spaceUnavailable;

  /// No description provided for @spaceInsufficient.
  ///
  /// In en, this message translates to:
  /// **'Not enough storage. Free up space and try again.'**
  String get spaceInsufficient;

  /// No description provided for @spaceShort.
  ///
  /// In en, this message translates to:
  /// **'Not enough storage'**
  String get spaceShort;

  /// No description provided for @resourceConflict.
  ///
  /// In en, this message translates to:
  /// **'The resource directory conflicts with another book. Original content was kept. Contact the content maintainer.'**
  String get resourceConflict;

  /// No description provided for @extractFailed.
  ///
  /// In en, this message translates to:
  /// **'Extraction failed'**
  String get extractFailed;

  /// No description provided for @packConfigError.
  ///
  /// In en, this message translates to:
  /// **'Resource pack configuration error'**
  String get packConfigError;

  /// No description provided for @urlConfigError.
  ///
  /// In en, this message translates to:
  /// **'Download address configuration error'**
  String get urlConfigError;

  /// No description provided for @notDownloadable.
  ///
  /// In en, this message translates to:
  /// **'Content cannot be downloaded right now'**
  String get notDownloadable;

  /// No description provided for @resourceConfigError.
  ///
  /// In en, this message translates to:
  /// **'Learning resource configuration error'**
  String get resourceConfigError;

  /// No description provided for @resourceBusy.
  ///
  /// In en, this message translates to:
  /// **'Content is being processed. Please try again later.'**
  String get resourceBusy;

  /// No description provided for @contentUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Content is currently unavailable'**
  String get contentUnavailable;

  /// No description provided for @audioMissing.
  ///
  /// In en, this message translates to:
  /// **'Audio resources are missing'**
  String get audioMissing;

  /// No description provided for @noPlayableAudio.
  ///
  /// In en, this message translates to:
  /// **'No audio available to play'**
  String get noPlayableAudio;

  /// No description provided for @lessonRemoved.
  ///
  /// In en, this message translates to:
  /// **'The original lesson is no longer in this content'**
  String get lessonRemoved;

  /// No description provided for @insufficientQuestions.
  ///
  /// In en, this message translates to:
  /// **'This lesson does not have enough available questions'**
  String get insufficientQuestions;

  /// No description provided for @bankUpdated.
  ///
  /// In en, this message translates to:
  /// **'The question bank has changed. Reopen the lesson.'**
  String get bankUpdated;

  /// No description provided for @practiceUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Practice history is currently unavailable'**
  String get practiceUnavailable;

  /// No description provided for @submitMistakeFirst.
  ///
  /// In en, this message translates to:
  /// **'Submit an answer to the missed question first'**
  String get submitMistakeFirst;

  /// No description provided for @operationTimeout.
  ///
  /// In en, this message translates to:
  /// **'The operation timed out. Try again.'**
  String get operationTimeout;

  /// No description provided for @networkFailed.
  ///
  /// In en, this message translates to:
  /// **'Network connection failed'**
  String get networkFailed;

  /// No description provided for @serverFailed.
  ///
  /// In en, this message translates to:
  /// **'Server request failed'**
  String get serverFailed;

  /// No description provided for @fileFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not read or write files. Check free storage and try again.'**
  String get fileFailed;

  /// No description provided for @databaseFailed.
  ///
  /// In en, this message translates to:
  /// **'Local data processing failed'**
  String get databaseFailed;

  /// No description provided for @audioFailed.
  ///
  /// In en, this message translates to:
  /// **'Audio playback failed'**
  String get audioFailed;

  /// No description provided for @formatError.
  ///
  /// In en, this message translates to:
  /// **'Invalid data format'**
  String get formatError;

  /// No description provided for @data.
  ///
  /// In en, this message translates to:
  /// **'Data'**
  String get data;

  /// No description provided for @clearLearning.
  ///
  /// In en, this message translates to:
  /// **'Clear content learning history'**
  String get clearLearning;

  /// No description provided for @clearLearningHint.
  ///
  /// In en, this message translates to:
  /// **'Delete local content learning history and reset appearance and daily goal.'**
  String get clearLearningHint;

  /// No description provided for @clearStudy.
  ///
  /// In en, this message translates to:
  /// **'Clear study history'**
  String get clearStudy;

  /// No description provided for @clearStudyHint.
  ///
  /// In en, this message translates to:
  /// **'Delete local study history.'**
  String get clearStudyHint;

  /// No description provided for @clearStudyConfirm.
  ///
  /// In en, this message translates to:
  /// **'Clear study history?'**
  String get clearStudyConfirm;

  /// No description provided for @clearStudyBody.
  ///
  /// In en, this message translates to:
  /// **'All J Practice and J Test data for this user will be permanently deleted, including history, unfinished progress, answers, mistakes, reviews, level settings, and legacy records. Downloaded question banks, user identity, and data for other Study Room features will be kept.'**
  String get clearStudyBody;

  /// No description provided for @clearLearningConfirm.
  ///
  /// In en, this message translates to:
  /// **'Clear content learning history?'**
  String get clearLearningConfirm;

  /// No description provided for @clearLearningBody.
  ///
  /// In en, this message translates to:
  /// **'This user’s lesson progress, study time, answers, review cards, and last learning position will be permanently deleted. Appearance will follow the system and the daily goal will reset to 10 minutes. Downloaded content, user identity, text size, and Study Room records will be kept.'**
  String get clearLearningBody;

  /// No description provided for @confirmClear.
  ///
  /// In en, this message translates to:
  /// **'Confirm clear'**
  String get confirmClear;

  /// No description provided for @systemRecords.
  ///
  /// In en, this message translates to:
  /// **'System information log'**
  String get systemRecords;

  /// No description provided for @viewInformation.
  ///
  /// In en, this message translates to:
  /// **'View information details'**
  String get viewInformation;

  /// No description provided for @autoEnter.
  ///
  /// In en, this message translates to:
  /// **'Opening in {seconds} seconds'**
  String autoEnter(int seconds);

  /// No description provided for @dayCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 day} other{{count} days}}'**
  String dayCount(int count);

  /// No description provided for @cardCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 card} other{{count} cards}}'**
  String cardCount(int count);

  /// No description provided for @lessonCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 lesson} other{{count} lessons}}'**
  String lessonCount(int count);

  /// No description provided for @completedPracticeCount.
  ///
  /// In en, this message translates to:
  /// **'{count} practices completed'**
  String completedPracticeCount(int count);

  /// No description provided for @mistakeCount.
  ///
  /// In en, this message translates to:
  /// **'{count} past mistakes'**
  String mistakeCount(int count);

  /// No description provided for @reviewAdvice.
  ///
  /// In en, this message translates to:
  /// **'{count} cards are due. Recall the answer before revealing it to strengthen your memory.'**
  String reviewAdvice(int count);

  /// No description provided for @streakDays.
  ///
  /// In en, this message translates to:
  /// **'Learning streak: {count} days'**
  String streakDays(int count);

  /// No description provided for @unitNumber.
  ///
  /// In en, this message translates to:
  /// **'Unit {number}'**
  String unitNumber(String number);

  /// No description provided for @practiceSummary.
  ///
  /// In en, this message translates to:
  /// **'{total} answers · {correct} correct'**
  String practiceSummary(int total, int correct);

  /// No description provided for @wrongAnswer.
  ///
  /// In en, this message translates to:
  /// **'Incorrect · Correct answer: {answer}'**
  String wrongAnswer(String answer);

  /// No description provided for @deleteContentBody.
  ///
  /// In en, this message translates to:
  /// **'This deletes the units, lessons, words, texts, grammar, exercises, and audio for “{name}”. Practice, review, and learning records will be kept. You can only download content still offered by the server; removed content cannot be downloaded again.'**
  String deleteContentBody(String name);

  /// No description provided for @versionUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Version unavailable'**
  String get versionUnavailable;

  /// No description provided for @confirm.
  ///
  /// In en, this message translates to:
  /// **'Confirm'**
  String get confirm;

  /// No description provided for @refresh.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get refresh;

  /// No description provided for @loadMore.
  ///
  /// In en, this message translates to:
  /// **'Load more'**
  String get loadMore;

  /// No description provided for @notRecorded.
  ///
  /// In en, this message translates to:
  /// **'Not recorded'**
  String get notRecorded;

  /// No description provided for @systemInfo.
  ///
  /// In en, this message translates to:
  /// **'System information'**
  String get systemInfo;

  /// No description provided for @clearSystemConfirm.
  ///
  /// In en, this message translates to:
  /// **'Delete all system information?'**
  String get clearSystemConfirm;

  /// No description provided for @clearSystemBody.
  ///
  /// In en, this message translates to:
  /// **'All system information logs on this device will be permanently deleted.'**
  String get clearSystemBody;

  /// No description provided for @deleteAllRecords.
  ///
  /// In en, this message translates to:
  /// **'Delete all records'**
  String get deleteAllRecords;

  /// No description provided for @systemInfoHint.
  ///
  /// In en, this message translates to:
  /// **'Newest events appear first. Tap a record for details.'**
  String get systemInfoHint;

  /// No description provided for @noSystemRecords.
  ///
  /// In en, this message translates to:
  /// **'No system information logs'**
  String get noSystemRecords;

  /// No description provided for @systemReadFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not read information logs. Try again.'**
  String get systemReadFailed;

  /// No description provided for @deleteFailed.
  ///
  /// In en, this message translates to:
  /// **'Deletion failed. Try again.'**
  String get deleteFailed;

  /// No description provided for @userHint.
  ///
  /// In en, this message translates to:
  /// **'User message'**
  String get userHint;

  /// No description provided for @recordLevel.
  ///
  /// In en, this message translates to:
  /// **'Record ID / Level'**
  String get recordLevel;

  /// No description provided for @errorType.
  ///
  /// In en, this message translates to:
  /// **'Exception type / Error code'**
  String get errorType;

  /// No description provided for @errorDetails.
  ///
  /// In en, this message translates to:
  /// **'Error details'**
  String get errorDetails;

  /// No description provided for @stackTrace.
  ///
  /// In en, this message translates to:
  /// **'Stack trace'**
  String get stackTrace;

  /// No description provided for @relatedInfo.
  ///
  /// In en, this message translates to:
  /// **'Related information'**
  String get relatedInfo;

  /// No description provided for @appSystem.
  ///
  /// In en, this message translates to:
  /// **'App version / System'**
  String get appSystem;

  /// No description provided for @userSession.
  ///
  /// In en, this message translates to:
  /// **'User / Startup session'**
  String get userSession;

  /// No description provided for @warning.
  ///
  /// In en, this message translates to:
  /// **'Warning'**
  String get warning;

  /// No description provided for @important.
  ///
  /// In en, this message translates to:
  /// **'Important'**
  String get important;

  /// No description provided for @urgent.
  ///
  /// In en, this message translates to:
  /// **'Urgent'**
  String get urgent;

  /// No description provided for @notice.
  ///
  /// In en, this message translates to:
  /// **'Notice'**
  String get notice;

  /// No description provided for @noticeSaveFailed.
  ///
  /// In en, this message translates to:
  /// **'Acknowledgement was not saved. Please try again.'**
  String get noticeSaveFailed;

  /// No description provided for @noticeTime.
  ///
  /// In en, this message translates to:
  /// **'Published'**
  String get noticeTime;

  /// No description provided for @acknowledged.
  ///
  /// In en, this message translates to:
  /// **'Acknowledged'**
  String get acknowledged;

  /// No description provided for @unacknowledged.
  ///
  /// In en, this message translates to:
  /// **'Not acknowledged'**
  String get unacknowledged;

  /// No description provided for @expired.
  ///
  /// In en, this message translates to:
  /// **'Expired'**
  String get expired;

  /// No description provided for @savingEllipsis.
  ///
  /// In en, this message translates to:
  /// **'Saving…'**
  String get savingEllipsis;

  /// No description provided for @gotIt.
  ///
  /// In en, this message translates to:
  /// **'Got it'**
  String get gotIt;

  /// No description provided for @noNotices.
  ///
  /// In en, this message translates to:
  /// **'No announcements'**
  String get noNotices;

  /// No description provided for @deleteNotice.
  ///
  /// In en, this message translates to:
  /// **'Delete announcement?'**
  String get deleteNotice;

  /// No description provided for @deleteNoticeBody.
  ///
  /// In en, this message translates to:
  /// **'Delete this announcement?'**
  String get deleteNoticeBody;

  /// No description provided for @noticeDeleteFailed.
  ///
  /// In en, this message translates to:
  /// **'The announcement was not deleted. Try again.'**
  String get noticeDeleteFailed;

  /// No description provided for @noticeDetails.
  ///
  /// In en, this message translates to:
  /// **'Announcement details'**
  String get noticeDetails;

  /// No description provided for @deleting.
  ///
  /// In en, this message translates to:
  /// **'Deleting…'**
  String get deleting;

  /// No description provided for @thankSupport.
  ///
  /// In en, this message translates to:
  /// **'Thank you for your support'**
  String get thankSupport;

  /// No description provided for @encouragement.
  ///
  /// In en, this message translates to:
  /// **'Your encouragement helps 语之初 keep improving.'**
  String get encouragement;

  /// No description provided for @tipTerms.
  ///
  /// In en, this message translates to:
  /// **'Tips are one-time, repeatable App Store consumable purchases. They do not unlock extra features and cannot be restored.'**
  String get tipTerms;

  /// No description provided for @productUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Products are unavailable. Please try again later.'**
  String get productUnavailable;

  /// No description provided for @reload.
  ///
  /// In en, this message translates to:
  /// **'Reload'**
  String get reload;

  /// No description provided for @smallTip.
  ///
  /// In en, this message translates to:
  /// **'A little encouragement'**
  String get smallTip;

  /// No description provided for @mediumTip.
  ///
  /// In en, this message translates to:
  /// **'Warm support'**
  String get mediumTip;

  /// No description provided for @largeTip.
  ///
  /// In en, this message translates to:
  /// **'Special support'**
  String get largeTip;

  /// No description provided for @xlargeTip.
  ///
  /// In en, this message translates to:
  /// **'Generous support'**
  String get xlargeTip;

  /// No description provided for @premiumTip.
  ///
  /// In en, this message translates to:
  /// **'Outstanding encouragement'**
  String get premiumTip;

  /// No description provided for @strongTip.
  ///
  /// In en, this message translates to:
  /// **'Amazing support'**
  String get strongTip;

  /// No description provided for @thankSupportSentence.
  ///
  /// In en, this message translates to:
  /// **'Thank you for your support.'**
  String get thankSupportSentence;

  /// No description provided for @passionEcho.
  ///
  /// In en, this message translates to:
  /// **'May every passion find an echo.'**
  String get passionEcho;

  /// No description provided for @skip.
  ///
  /// In en, this message translates to:
  /// **'Skip'**
  String get skip;

  /// No description provided for @tipServiceUnavailable.
  ///
  /// In en, this message translates to:
  /// **'The tipping service is unavailable. Try again later.'**
  String get tipServiceUnavailable;

  /// No description provided for @tipAppleOnly.
  ///
  /// In en, this message translates to:
  /// **'Support the developer on an iPhone or iPad.'**
  String get tipAppleOnly;

  /// No description provided for @purchaseVerifyFailed.
  ///
  /// In en, this message translates to:
  /// **'Purchase verification failed. Try again later.'**
  String get purchaseVerifyFailed;

  /// No description provided for @productReloadUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Products are unavailable. Reload them later.'**
  String get productReloadUnavailable;

  /// No description provided for @purchaseRestricted.
  ///
  /// In en, this message translates to:
  /// **'Purchases are not allowed on this device.'**
  String get purchaseRestricted;

  /// No description provided for @productsLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not load products. Check your connection and try again.'**
  String get productsLoadFailed;

  /// No description provided for @purchaseBusy.
  ///
  /// In en, this message translates to:
  /// **'Processing a purchase. Please wait.'**
  String get purchaseBusy;

  /// No description provided for @reloadProductFirst.
  ///
  /// In en, this message translates to:
  /// **'Please reload the products first.'**
  String get reloadProductFirst;

  /// No description provided for @tipPending.
  ///
  /// In en, this message translates to:
  /// **'Purchase awaiting approval. Your thank-you will appear after approval.'**
  String get tipPending;

  /// No description provided for @tipCancelled.
  ///
  /// In en, this message translates to:
  /// **'Tip cancelled'**
  String get tipCancelled;

  /// No description provided for @purchaseIncomplete.
  ///
  /// In en, this message translates to:
  /// **'Purchase is incomplete. Try again later.'**
  String get purchaseIncomplete;

  /// No description provided for @purchaseFailed.
  ///
  /// In en, this message translates to:
  /// **'Purchase failed. Try again later.'**
  String get purchaseFailed;

  /// No description provided for @networkAddressInvalid.
  ///
  /// In en, this message translates to:
  /// **'Invalid content service address'**
  String get networkAddressInvalid;

  /// No description provided for @networkConfigHint.
  ///
  /// In en, this message translates to:
  /// **'Contact the maintainer to check the content service configuration.'**
  String get networkConfigHint;

  /// No description provided for @serviceConnected.
  ///
  /// In en, this message translates to:
  /// **'Connected to the content service'**
  String get serviceConnected;

  /// No description provided for @serviceReady.
  ///
  /// In en, this message translates to:
  /// **'You can load the catalog and download content.'**
  String get serviceReady;

  /// No description provided for @serviceUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Content service is unavailable'**
  String get serviceUnavailable;

  /// No description provided for @serviceCatalogFailed.
  ///
  /// In en, this message translates to:
  /// **'Connected to the service, but the catalog could not be loaded. Try later or contact the maintainer.'**
  String get serviceCatalogFailed;

  /// No description provided for @catalogUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Content catalog is unavailable'**
  String get catalogUnavailable;

  /// No description provided for @catalogInvalid.
  ///
  /// In en, this message translates to:
  /// **'The service returned an invalid catalog. Try later or contact the maintainer.'**
  String get catalogInvalid;

  /// No description provided for @serviceInsecure.
  ///
  /// In en, this message translates to:
  /// **'Cannot connect securely to the content service'**
  String get serviceInsecure;

  /// No description provided for @certificateHint.
  ///
  /// In en, this message translates to:
  /// **'Contact the maintainer to check the service certificate.'**
  String get certificateHint;

  /// No description provided for @networkRestricted.
  ///
  /// In en, this message translates to:
  /// **'Network access is restricted'**
  String get networkRestricted;

  /// No description provided for @networkRestrictedHint.
  ///
  /// In en, this message translates to:
  /// **'Check wireless data access for 语之初 in Settings, or use available Wi-Fi. Downloaded content remains available offline.'**
  String get networkRestrictedHint;

  /// No description provided for @networkUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Network unavailable; cannot connect to the content server'**
  String get networkUnavailable;

  /// No description provided for @networkRetryHint.
  ///
  /// In en, this message translates to:
  /// **'Check Wi-Fi or cellular data and try again. Downloaded content remains available offline.'**
  String get networkRetryHint;

  /// No description provided for @serverConnectionError.
  ///
  /// In en, this message translates to:
  /// **'Content server connection error'**
  String get serverConnectionError;

  /// No description provided for @serverRetryHint.
  ///
  /// In en, this message translates to:
  /// **'Check your connection and try later. Downloaded content remains available offline.'**
  String get serverRetryHint;

  /// No description provided for @resourceCleanupPending.
  ///
  /// In en, this message translates to:
  /// **'Learning resources deleted. Remaining files will be cleaned up at the next launch.'**
  String get resourceCleanupPending;

  /// No description provided for @activationPending.
  ///
  /// In en, this message translates to:
  /// **'Content installed. Reopen the app to finish activation.'**
  String get activationPending;

  /// No description provided for @installedCleanupPending.
  ///
  /// In en, this message translates to:
  /// **'Installed. Temporary files will be cleaned up at the next launch.'**
  String get installedCleanupPending;

  /// No description provided for @downloadInterrupted.
  ///
  /// In en, this message translates to:
  /// **'The last download was interrupted when the app closed. Original content was restored; you can download again.'**
  String get downloadInterrupted;

  /// No description provided for @cancelledPreserved.
  ///
  /// In en, this message translates to:
  /// **'Cancelled. Learning records were kept. You can download again at any time.'**
  String get cancelledPreserved;

  /// No description provided for @installFailed.
  ///
  /// In en, this message translates to:
  /// **'Resource installation failed'**
  String get installFailed;

  /// No description provided for @recordsPreserved.
  ///
  /// In en, this message translates to:
  /// **'Learning records were kept.'**
  String get recordsPreserved;

  /// No description provided for @practiceReadFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not load practice'**
  String get practiceReadFailed;

  /// No description provided for @packageLanguageError.
  ///
  /// In en, this message translates to:
  /// **'Invalid content language information. Update resources or contact the maintainer.'**
  String get packageLanguageError;

  /// No description provided for @speechVoiceUnavailable.
  ///
  /// In en, this message translates to:
  /// **'The voice for this content language is unavailable. Check system speech settings.'**
  String get speechVoiceUnavailable;

  /// No description provided for @courseReviewMessage0.
  ///
  /// In en, this message translates to:
  /// **'Could not load the lesson'**
  String get courseReviewMessage0;

  /// No description provided for @courseReviewMessage1.
  ///
  /// In en, this message translates to:
  /// **'Could not switch tabs'**
  String get courseReviewMessage1;

  /// No description provided for @courseReviewMessage2.
  ///
  /// In en, this message translates to:
  /// **'Could not load practice content'**
  String get courseReviewMessage2;

  /// No description provided for @courseReviewMessage3.
  ///
  /// In en, this message translates to:
  /// **'Could not load grammar content'**
  String get courseReviewMessage3;

  /// No description provided for @courseReviewMessage4.
  ///
  /// In en, this message translates to:
  /// **'Could not play grammar media'**
  String get courseReviewMessage4;

  /// No description provided for @courseReviewMessage5.
  ///
  /// In en, this message translates to:
  /// **'Could not load vocabulary content'**
  String get courseReviewMessage5;

  /// No description provided for @courseReviewMessage6.
  ///
  /// In en, this message translates to:
  /// **'Could not play vocabulary media'**
  String get courseReviewMessage6;

  /// No description provided for @courseReviewMessage7.
  ///
  /// In en, this message translates to:
  /// **'Could not load lesson text'**
  String get courseReviewMessage7;

  /// No description provided for @courseReviewMessage8.
  ///
  /// In en, this message translates to:
  /// **'Could not play lesson media'**
  String get courseReviewMessage8;

  /// No description provided for @courseReviewMessage9.
  ///
  /// In en, this message translates to:
  /// **'Open practice illustration'**
  String get courseReviewMessage9;

  /// No description provided for @courseReviewMessage10.
  ///
  /// In en, this message translates to:
  /// **'Interactive open practice illustration'**
  String get courseReviewMessage10;

  /// No description provided for @courseReviewMessage11.
  ///
  /// In en, this message translates to:
  /// **'Grammar illustration'**
  String get courseReviewMessage11;

  /// No description provided for @courseReviewMessage12.
  ///
  /// In en, this message translates to:
  /// **'Interactive grammar illustration'**
  String get courseReviewMessage12;

  /// No description provided for @courseReviewMessage13.
  ///
  /// In en, this message translates to:
  /// **'Vocabulary illustration'**
  String get courseReviewMessage13;

  /// No description provided for @courseReviewMessage14.
  ///
  /// In en, this message translates to:
  /// **'Interactive vocabulary illustration'**
  String get courseReviewMessage14;

  /// No description provided for @courseReviewMessage15.
  ///
  /// In en, this message translates to:
  /// **'Dialogue illustration'**
  String get courseReviewMessage15;

  /// No description provided for @courseReviewMessage16.
  ///
  /// In en, this message translates to:
  /// **'Lesson text illustration'**
  String get courseReviewMessage16;

  /// No description provided for @courseReviewMessage17.
  ///
  /// In en, this message translates to:
  /// **'Interactive dialogue illustration'**
  String get courseReviewMessage17;

  /// No description provided for @courseReviewMessage18.
  ///
  /// In en, this message translates to:
  /// **'Interactive lesson text illustration'**
  String get courseReviewMessage18;

  /// No description provided for @courseReviewMessage19.
  ///
  /// In en, this message translates to:
  /// **'No lesson audio is available to play'**
  String get courseReviewMessage19;

  /// No description provided for @courseReviewMessage20.
  ///
  /// In en, this message translates to:
  /// **'No vocabulary audio is available to play'**
  String get courseReviewMessage20;

  /// No description provided for @videoPlaybackRetry.
  ///
  /// In en, this message translates to:
  /// **'Video cannot be played right now. Please try again.'**
  String get videoPlaybackRetry;

  /// No description provided for @videoStopRetry.
  ///
  /// In en, this message translates to:
  /// **'Could not stop the video. Please try again.'**
  String get videoStopRetry;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'ja', 'ko', 'zh'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when language+script codes are specified.
  switch (locale.languageCode) {
    case 'zh':
      {
        switch (locale.scriptCode) {
          case 'Hans':
            return AppLocalizationsZhHans();
          case 'Hant':
            return AppLocalizationsZhHant();
        }
        break;
      }
  }

  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'ja':
      return AppLocalizationsJa();
    case 'ko':
      return AppLocalizationsKo();
    case 'zh':
      return AppLocalizationsZh();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
