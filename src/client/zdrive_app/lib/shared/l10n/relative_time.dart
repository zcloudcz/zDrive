import 'package:timeago/timeago.dart' as timeago;

bool _registered = false;

String formatRelativeTime(DateTime date, String locale, {DateTime? clock}) {
  if (!_registered) {
    final messages = <String, timeago.LookupMessages>{
      'cs': timeago.CsMessages(),
      'sk': _SlovakMessages(),
      'es': timeago.EsMessages(),
      'fi': timeago.FiMessages(),
      'sv': timeago.SvMessages(),
      'de': timeago.DeMessages(),
      'fr': timeago.FrMessages(),
      'nl': timeago.NlMessages(),
      'ja': timeago.JaMessages(),
      'zh': timeago.ZhCnMessages(),
    };
    messages.forEach(timeago.setLocaleMessages);
    _registered = true;
  }
  return timeago.format(date, locale: locale, clock: clock);
}

// timeago provides the other supported languages but has no Slovak messages.
// These timestamps describe past file changes and device synchronization.
class _SlovakMessages implements timeago.LookupMessages {
  @override
  String prefixAgo() => 'pred';
  @override
  String prefixFromNow() => 'o';
  @override
  String suffixAgo() => '';
  @override
  String suffixFromNow() => '';
  @override
  String lessThanOneMinute(int seconds) => 'chvíľou';
  @override
  String aboutAMinute(int minutes) => 'minútou';
  @override
  String minutes(int minutes) => '$minutes minútami';
  @override
  String aboutAnHour(int minutes) => 'hodinou';
  @override
  String hours(int hours) => '$hours hodinami';
  @override
  String aDay(int hours) => 'dňom';
  @override
  String days(int days) => '$days dňami';
  @override
  String aboutAMonth(int days) => 'mesiacom';
  @override
  String months(int months) => '$months mesiacmi';
  @override
  String aboutAYear(int year) => 'rokom';
  @override
  String years(int years) => '$years rokmi';
  @override
  String wordSeparator() => ' ';
}
