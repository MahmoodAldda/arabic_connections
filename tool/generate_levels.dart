// Deterministic generator for assets/levels.json.
//
// The game is one continuous, level-less journey: `progression.dart` picks a
// level's *content* by the player's skill (which controls how many categories
// the board has). To give that engine a deep, varied pool we generate 500
// levels from a hand-curated word bank instead of authoring each by hand.
//
// Difficulty is tied to board size so it slots into the existing skill scaling:
//   • 3 categories → kid-friendly / picture (emoji) vocabulary
//   • 4 categories → everyday vocabulary
//   • 5 categories → richer, mixed vocabulary
//   • 6 categories → advanced / academic vocabulary
//
// Each category carries a *pool* of words (often 6); the generator picks four
// per level so recurring categories feel fresh. Titles and stories use the
// definite ([def]) form of each name so every intro reads like natural Arabic.
//
// Run from the project root:  dart run tool/generate_levels.dart
import 'dart:convert';
import 'dart:io';
import 'dart:math';

/// A category in the word bank. [words] is a pool (≥4); the generator samples
/// four per level. When [emojis] is present it aligns 1:1 with [words] and the
/// category can appear as a "picture" card. [def] is the definite display form
/// used inside generated titles/stories (e.g. "المواصلات").
class Cat {
  const Cat(this.id, this.name, this.def, this.color, this.tier, this.words,
      [this.emojis]);

  final String id;
  final String name;
  final String def;
  final String color;
  final String tier; // basic | intermediate | advanced
  final List<String> words;
  final List<String>? emojis;

  bool get hasEmoji => emojis != null;

  int get _seed => id.codeUnits.fold(0, (a, b) => a + b);
}

// ---------------------------------------------------------------------------
// Word bank
// ---------------------------------------------------------------------------

// Basic tier — kid-friendly; the emoji entries double as picture categories.
const List<Cat> _basic = [
  Cat('fruits', 'فواكه', 'الفواكه', '#E76F51', 'basic',
      ['تفاح', 'موز', 'عنب', 'برتقال', 'فراولة', 'أناناس'],
      ['🍎', '🍌', '🍇', '🍊', '🍓', '🍍']),
  Cat('vegetables', 'خضروات', 'الخضروات', '#58CC02', 'basic',
      ['جزر', 'بطاطا', 'طماطم', 'خيار', 'باذنجان', 'بصل'],
      ['🥕', '🥔', '🍅', '🥒', '🍆', '🧅']),
  Cat('animals', 'حيوانات', 'الحيوانات', '#2A9D8F', 'basic',
      ['قطة', 'كلب', 'حصان', 'أسد', 'فيل', 'أرنب'],
      ['🐱', '🐶', '🐴', '🦁', '🐘', '🐰']),
  Cat('birds', 'طيور', 'الطيور', '#E9C46A', 'basic',
      ['نسر', 'حمامة', 'عصفور', 'بطة', 'بومة', 'ديك'],
      ['🦅', '🕊️', '🐦', '🦆', '🦉', '🐔']),
  Cat('transport', 'مواصلات', 'المواصلات', '#26A69A', 'basic',
      ['سيارة', 'قطار', 'طائرة', 'دراجة', 'حافلة', 'سفينة'],
      ['🚗', '🚆', '✈️', '🚲', '🚌', '🚢']),
  Cat('weather', 'طقس', 'الطقس', '#4EA8DE', 'basic',
      ['شمس', 'مطر', 'ريح', 'ثلج', 'غيمة', 'برق'],
      ['☀️', '🌧️', '💨', '❄️', '☁️', '⚡']),
  Cat('sports', 'رياضة', 'الرياضة', '#E76F51', 'basic',
      ['كرة', 'سباحة', 'تنس', 'ملاكمة', 'جري', 'سلة'],
      ['⚽', '🏊', '🎾', '🥊', '🏃', '🏀']),
  Cat('food', 'طعام', 'الطعام', '#F4A261', 'basic',
      ['خبز', 'أرز', 'لحم', 'جبن', 'بيض', 'سمك'],
      ['🍞', '🍚', '🍖', '🧀', '🥚', '🐟']),
  Cat('sea', 'كائنات بحرية', 'الكائنات البحرية', '#1CB0F6', 'basic',
      ['حوت', 'دولفين', 'سلحفاة', 'أخطبوط', 'سرطان', 'قنديل'],
      ['🐳', '🐬', '🐢', '🐙', '🦀', '🪼']),
  Cat('insects', 'حشرات', 'الحشرات', '#8AB17D', 'basic',
      ['نحلة', 'نملة', 'فراشة', 'بعوضة', 'خنفساء', 'جرادة'],
      ['🐝', '🐜', '🦋', '🦟', '🪲', '🦗']),
  Cat('wild', 'حيوانات برية', 'الحيوانات البرية', '#E07E00', 'basic',
      ['نمر', 'فهد', 'ذئب', 'دب', 'ثعلب', 'غزال'],
      ['🐯', '🐆', '🐺', '🐻', '🦊', '🦌']),
  Cat('drinks', 'مشروبات', 'المشروبات', '#F4A261', 'basic',
      ['ماء', 'حليب', 'شاي', 'قهوة', 'عصير', 'كولا'],
      ['💧', '🥛', '🍵', '☕', '🧃', '🥤']),
  Cat('colors', 'ألوان', 'الألوان', '#E9C46A', 'basic',
      ['أحمر', 'أزرق', 'أخضر', 'أصفر', 'برتقالي', 'بنفسجي'],
      ['🔴', '🔵', '🟢', '🟡', '🟠', '🟣']),
  Cat('family', 'عائلة', 'العائلة', '#E0567A', 'basic',
      ['أب', 'أم', 'أخ', 'أخت', 'جد', 'جدة'],
      ['👨', '👩', '👦', '👧', '👴', '👵']),
  Cat('body', 'جسم', 'الجسم', '#8AB17D', 'basic',
      ['يد', 'عين', 'أذن', 'قلب', 'أنف', 'قدم'],
      ['✋', '👁️', '👂', '❤️', '👃', '🦶']),
  Cat('clothes', 'ملابس', 'الملابس', '#7B68EE', 'basic',
      ['قميص', 'حذاء', 'قبعة', 'معطف', 'جورب', 'وشاح'],
      ['👕', '👟', '🧢', '🧥', '🧦', '🧣']),
  Cat('kitchen', 'أدوات مطبخ', 'أدوات المطبخ', '#78909C', 'basic',
      ['ملعقة', 'شوكة', 'سكين', 'صحن', 'كوب', 'قِدر'],
      ['🥄', '🍴', '🔪', '🍽️', '🥤', '🍲']),
  Cat('school', 'مدرسة', 'المدرسة', '#5C6BC0', 'basic',
      ['كتاب', 'قلم', 'ممحاة', 'دفتر', 'مسطرة', 'حقيبة'],
      ['📖', '✏️', '🧽', '📓', '📏', '🎒']),
  Cat('flowers', 'زهور', 'الزهور', '#CE82FF', 'basic',
      ['ورد', 'ياسمين', 'فل', 'لوتس', 'زنبق', 'توليب'],
      ['🌹', '🌼', '🌸', '🌺', '🌷', '🏵️']),
  Cat('emotions', 'مشاعر', 'المشاعر', '#E0567A', 'basic',
      ['فرح', 'حزن', 'خوف', 'غضب', 'حب', 'دهشة'],
      ['😀', '😢', '😨', '😠', '🥰', '😲']),
  Cat('numbers', 'أرقام', 'الأرقام', '#7B68EE', 'basic',
      ['واحد', 'اثنان', 'ثلاثة', 'أربعة', 'خمسة', 'ستة'],
      ['1️⃣', '2️⃣', '3️⃣', '4️⃣', '5️⃣', '6️⃣']),
  Cat('trees', 'أشجار', 'الأشجار', '#58CC02', 'basic',
      ['نخيل', 'صنوبر', 'زيتون', 'تين'], ['🌴', '🌲', '🫒', '🌳']),
  Cat('shapes', 'أشكال', 'الأشكال', '#7B68EE', 'basic',
      ['مربع', 'دائرة', 'مثلث', 'مستطيل', 'معيّن', 'خماسي']),
  Cat('days', 'أيام', 'الأيام', '#4EA8DE', 'basic',
      ['أحد', 'اثنين', 'ثلاثاء', 'أربعاء', 'خميس', 'جمعة']),
  Cat('sweets', 'حلويات', 'الحلويات', '#E0567A', 'basic',
      ['بقلاوة', 'كنافة', 'بسبوسة', 'معمول', 'قطايف', 'مهلبية']),
  Cat('senses', 'حواس', 'الحواس', '#FF9600', 'basic',
      ['بصر', 'سمع', 'شم', 'لمس', 'ذوق']),
];

// Intermediate tier — everyday but less childish vocabulary.
const List<Cat> _intermediate = [
  Cat('jobs', 'مهن', 'المهن', '#AB47BC', 'intermediate',
      ['طبيب', 'معلم', 'مهندس', 'طيار', 'شرطي', 'طباخ']),
  Cat('tools', 'أدوات', 'الأدوات', '#78909C', 'intermediate',
      ['مطرقة', 'منشار', 'مفك', 'مسمار', 'مفتاح', 'كماشة']),
  Cat('months', 'شهور', 'الشهور', '#F4A261', 'intermediate',
      ['يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو']),
  Cat('seasons', 'فصول', 'الفصول', '#FF9600', 'intermediate',
      ['شتاء', 'صيف', 'خريف', 'ربيع']),
  Cat('planets', 'كواكب', 'الكواكب', '#5C6BC0', 'intermediate',
      ['مريخ', 'زهرة', 'عطارد', 'زحل', 'مشتري', 'نبتون']),
  Cat('metals', 'معادن', 'المعادن', '#78909C', 'intermediate',
      ['ذهب', 'فضة', 'حديد', 'نحاس', 'ألمنيوم', 'رصاص']),
  Cat('oceans', 'محيطات', 'المحيطات', '#1CB0F6', 'intermediate',
      ['هادئ', 'أطلسي', 'هندي', 'متجمد']),
  Cat('rivers', 'أنهار', 'الأنهار', '#4EA8DE', 'intermediate',
      ['نيل', 'دجلة', 'فرات', 'أردن']),
  Cat('continents', 'قارات', 'القارات', '#5C6BC0', 'intermediate',
      ['آسيا', 'أفريقيا', 'أوروبا', 'أستراليا', 'أمريكا']),
  Cat('capitals', 'عواصم', 'العواصم', '#AB47BC', 'intermediate',
      ['القاهرة', 'الرياض', 'بغداد', 'دمشق', 'عمّان', 'بيروت']),
  Cat('countries', 'دول', 'الدول', '#78909C', 'intermediate',
      ['مصر', 'السعودية', 'المغرب', 'الأردن', 'تونس', 'ليبيا']),
  Cat('arab', 'دول عربية', 'الدول العربية', '#E9C46A', 'intermediate',
      ['الجزائر', 'السودان', 'الكويت', 'اليمن', 'قطر', 'عُمان']),
  Cat('languages', 'لغات', 'اللغات', '#26A69A', 'intermediate',
      ['عربية', 'إنجليزية', 'فرنسية', 'صينية', 'ألمانية', 'يابانية']),
  Cat('instruments', 'آلات موسيقية', 'الآلات الموسيقية', '#E0567A',
      'intermediate', ['عود', 'ناي', 'طبلة', 'كمان', 'قانون', 'بيانو']),
  Cat('gems', 'جواهر', 'الجواهر', '#CE82FF', 'intermediate',
      ['ماس', 'ياقوت', 'زمرد', 'لؤلؤ', 'عقيق', 'فيروز']),
  Cat('reptiles', 'زواحف', 'الزواحف', '#7CB342', 'intermediate',
      ['ثعبان', 'تمساح', 'سحلية', 'حرباء']),
  Cat('fish', 'أسماك', 'الأسماك', '#26A69A', 'intermediate',
      ['سلمون', 'تونة', 'سردين', 'هامور', 'قرش', 'بلطي']),
  Cat('furniture', 'أثاث', 'الأثاث', '#F4A261', 'intermediate',
      ['كرسي', 'طاولة', 'سرير', 'خزانة', 'أريكة', 'مكتب']),
  Cat('organs', 'أعضاء', 'الأعضاء', '#AB47BC', 'intermediate',
      ['كبد', 'رئة', 'كلية', 'معدة', 'دماغ', 'طحال']),
  Cat('spices', 'توابل', 'التوابل', '#F4A261', 'intermediate',
      ['فلفل', 'كمون', 'قرفة', 'زعتر', 'كركم', 'هيل']),
];

// Advanced tier — academic vocabulary for adult players.
const List<Cat> _advanced = [
  Cat('science', 'علوم', 'العلوم', '#26A69A', 'advanced',
      ['ذرّة', 'جزيء', 'خلية', 'قوة', 'تجربة', 'فرضية']),
  Cat('geography', 'جغرافيا', 'الجغرافيا', '#78909C', 'advanced',
      ['هضبة', 'وادي', 'مضيق', 'أرخبيل', 'سهل', 'دلتا']),
  Cat('literature', 'أدب', 'الأدب', '#AB47BC', 'advanced',
      ['رواية', 'قصيدة', 'ملحمة', 'سيرة', 'مقالة', 'مسرحية']),
  Cat('economics', 'اقتصاد', 'الاقتصاد', '#F4A261', 'advanced',
      ['تضخّم', 'ركود', 'عرض', 'طلب', 'سوق', 'رأسمال']),
  Cat('medicine', 'طب', 'الطب', '#E0567A', 'advanced',
      ['جراحة', 'مناعة', 'لقاح', 'تشخيص', 'دواء', 'عدوى']),
  Cat('philosophy', 'فلسفة', 'الفلسفة', '#5C6BC0', 'advanced',
      ['منطق', 'وجود', 'أخلاق', 'معرفة', 'جمال', 'وعي']),
  Cat('chemistry', 'كيمياء', 'الكيمياء', '#58CC02', 'advanced',
      ['حمض', 'قاعدة', 'تفاعل', 'عنصر', 'مركّب', 'أيون']),
  Cat('astronomy', 'فلك', 'الفلك', '#4EA8DE', 'advanced',
      ['سديم', 'مذنّب', 'كسوف', 'مدار', 'مجرّة', 'نجم']),
  Cat('law', 'قانون', 'القانون', '#78909C', 'advanced',
      ['دستور', 'عقد', 'قضاء', 'تشريع', 'دعوى', 'حكم']),
  Cat('physics', 'فيزياء', 'الفيزياء', '#7B68EE', 'advanced',
      ['جاذبية', 'احتكاك', 'كتلة', 'سرعة', 'تسارع', 'زخم']),
  Cat('history', 'تاريخ', 'التاريخ', '#F4A261', 'advanced',
      ['حضارة', 'إمبراطورية', 'ثورة', 'معاهدة', 'سلالة', 'حقبة']),
  Cat('mathematics', 'رياضيات', 'الرياضيات', '#26A69A', 'advanced',
      ['جبر', 'هندسة', 'معادلة', 'تكامل', 'كسر', 'مصفوفة']),
];

List<Cat> get _basicEmoji => _basic.where((c) => c.hasEmoji).toList();

/// The candidate pool for a level of [count] categories. Larger boards draw on
/// harder vocabulary so difficulty rises with the player's skill.
List<Cat> _poolFor(int count, int n) {
  switch (count) {
    case 3:
      return (n % 4 == 0) ? _basicEmoji : _basic; // every 4th is a picture set
    case 4:
      return [..._basic, ..._intermediate];
    case 5:
      return [..._intermediate, ..._advanced, ..._basic.take(8)];
    default: // 6
      return [..._intermediate, ..._advanced];
  }
}

List<Cat> _pickDistinct(List<Cat> pool, int count, int seed) {
  final copy = List<Cat>.from(pool);
  copy.shuffle(Random(seed * 9301 + 49297));
  return copy.take(count).toList();
}

/// Four indices into a category's word pool, chosen deterministically.
List<int> _choose4(Cat c, int n) {
  final idx = List<int>.generate(c.words.length, (i) => i);
  idx.shuffle(Random(n * 131 + c._seed));
  return (idx.take(4).toList())..sort();
}

String _makeTitle(List<String> defs, int n, bool allEmoji, bool advanced) {
  final a = defs[0];
  final b = defs.length > 1 ? defs[1] : a;
  if (allEmoji) return 'صور $a و$b';
  if (advanced) {
    const advTitles = ['معرفة متقدمة', 'تحدٍّ فكري', 'عقول كبيرة', 'قمة العلوم'];
    return advTitles[n % advTitles.length];
  }
  const templates = [
    'عالم', 'رحلة في', 'أسرار', 'كنوز', 'في رحاب', 'لمسة من', 'حكاية', 'ديوان',
  ];
  if (n % 3 == 0) return 'بين $a و$b';
  return '${templates[n % templates.length]} $a';
}

String _makeStory(List<String> defs, int n, bool allEmoji, bool advanced) {
  final a = defs[0];
  final b = defs.length > 1 ? defs[1] : a;
  final c = defs.length > 2 ? defs[2] : b;
  if (allEmoji) {
    return 'طابِق كل صورة بمكانها الصحيح، واستمتع بترتيب $a و$b بمرح.';
  }
  final base = [
    'رتّب $a و$b وما بينهما، وأثبت أنك سيّد الترتيب.',
    'من $a إلى $b، مجموعاتٌ متشابكة تنتظر يدك الماهرة.',
    'هل تفرّق بين $a و$b و$c؟ حان وقت التحدّي.',
    'اجمع شتات $a و$b، ثم توّج انتصارك بذكاء.',
    'لكل كلمة مكانها بين $a و$b… اعثر عليه بهدوء.',
    'مجموعاتٌ مختلطة من $a و$b و$c… خطّط لكل حركة.',
  ];
  final tpl = base[n % base.length];
  if (advanced) return '$tpl تحدٍّ يليق بالعقول الناضجة.';
  return tpl;
}

/// Assembles a level from [cats]. Returns null (so the caller can re-pick) if
/// two categories would contribute the exact same word — which is ambiguous.
Map<String, dynamic>? _assemble(int n, int count, List<Cat> cats,
    {bool allowDuplicates = false}) {
  final categories = [
    for (final c in cats) {'id': c.id, 'name': c.name, 'color': c.color},
  ];
  final words = <Map<String, dynamic>>[];
  final seenText = <String>{};
  var duplicate = false;
  for (final c in cats) {
    for (final i in _choose4(c, n)) {
      final text = c.words[i];
      if (!seenText.add(text)) duplicate = true;
      final word = <String, dynamic>{
        'id': '${c.id}_w${i + 1}',
        'text': text,
        'categoryId': c.id,
      };
      if (c.hasEmoji) word['emoji'] = c.emojis![i];
      words.add(word);
    }
  }
  if (duplicate && !allowDuplicates) return null;

  final defs = [for (final c in cats) c.def];
  final allEmoji = cats.every((c) => c.hasEmoji);
  final advanced = cats.any((c) => c.tier == 'advanced');
  return {
    'number': n,
    'title': _makeTitle(defs, n, allEmoji, advanced),
    'story': _makeStory(defs, n, allEmoji, advanced),
    'categories': categories,
    'words': words,
  };
}

Map<String, dynamic> _buildLevel(int n) {
  final count = 3 + ((n - 1) % 4); // cycles 3,4,5,6 → ~125 of each
  for (var attempt = 0; attempt < 12; attempt++) {
    final cats = _pickDistinct(_poolFor(count, n), count, n + attempt * 777);
    final level = _assemble(n, count, cats);
    if (level != null) return level;
  }
  // Extremely unlikely: accept duplicates rather than fail.
  final cats = _pickDistinct(_poolFor(count, n), count, n);
  return _assemble(n, count, cats, allowDuplicates: true)!;
}

void main() {
  // Sanity: every picture category's emoji list must align with its words.
  for (final c in [..._basic, ..._intermediate, ..._advanced]) {
    if (c.hasEmoji && c.emojis!.length != c.words.length) {
      stderr.writeln('Category ${c.id}: ${c.emojis!.length} emojis vs '
          '${c.words.length} words');
      exit(1);
    }
  }

  const total = 500;
  final levels = [for (var n = 1; n <= total; n++) _buildLevel(n)];

  final json = const JsonEncoder.withIndent('  ').convert({'levels': levels});
  File('assets/levels.json').writeAsStringSync('$json\n');

  final counts = <int, int>{};
  for (final l in levels) {
    final n = (l['categories'] as List).length;
    counts[n] = (counts[n] ?? 0) + 1;
  }
  stdout.writeln('Wrote ${levels.length} levels to assets/levels.json');
  stdout.writeln('Category-count distribution: $counts');
}
