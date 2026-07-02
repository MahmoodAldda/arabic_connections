import 'package:flutter/material.dart';

import 'models.dart';

/// Palette used across levels for category colors.
abstract final class CategoryColors {
  static const teal = Color(0xFF2A9D8F);
  static const coral = Color(0xFFE76F51);
  static const gold = Color(0xFFE9C46A);
  static const purple = Color(0xFF7B68EE);
  static const sky = Color(0xFF4EA8DE);
  static const rose = Color(0xFFE0567A);
  static const olive = Color(0xFF8AB17D);
  static const amber = Color(0xFFF4A261);
  static const indigo = Color(0xFF5C6BC0);
  static const mint = Color(0xFF26A69A);
  static const plum = Color(0xFFAB47BC);
  static const slate = Color(0xFF78909C);
}

/// Hardcoded sample levels — 16 Arabic words, 4 categories each.
final List<Level> sampleLevels = [
  Level(
    number: 1,
    title: 'مفردات أساسية',
    categories: const [
      Category(id: 'fruits', name: 'فواكه', color: CategoryColors.coral),
      Category(id: 'colors', name: 'ألوان', color: CategoryColors.gold),
      Category(id: 'animals', name: 'حيوانات', color: CategoryColors.teal),
      Category(id: 'numbers', name: 'أرقام', color: CategoryColors.purple),
    ],
    words: const [
      WordItem(id: 'w1', text: 'تفاح', categoryId: 'fruits'),
      WordItem(id: 'w2', text: 'موز', categoryId: 'fruits'),
      WordItem(id: 'w3', text: 'عنب', categoryId: 'fruits'),
      WordItem(id: 'w4', text: 'برتقال', categoryId: 'fruits'),
      WordItem(id: 'w5', text: 'أحمر', categoryId: 'colors'),
      WordItem(id: 'w6', text: 'أزرق', categoryId: 'colors'),
      WordItem(id: 'w7', text: 'أخضر', categoryId: 'colors'),
      WordItem(id: 'w8', text: 'أصفر', categoryId: 'colors'),
      WordItem(id: 'w9', text: 'قطة', categoryId: 'animals'),
      WordItem(id: 'w10', text: 'كلب', categoryId: 'animals'),
      WordItem(id: 'w11', text: 'حصان', categoryId: 'animals'),
      WordItem(id: 'w12', text: 'أسد', categoryId: 'animals'),
      WordItem(id: 'w13', text: 'واحد', categoryId: 'numbers'),
      WordItem(id: 'w14', text: 'اثنان', categoryId: 'numbers'),
      WordItem(id: 'w15', text: 'ثلاثة', categoryId: 'numbers'),
      WordItem(id: 'w16', text: 'أربعة', categoryId: 'numbers'),
    ],
  ),
  Level(
    number: 2,
    title: 'الحياة اليومية',
    categories: const [
      Category(id: 'family', name: 'عائلة', color: CategoryColors.rose),
      Category(id: 'weather', name: 'طقس', color: CategoryColors.sky),
      Category(id: 'food', name: 'طعام', color: CategoryColors.amber),
      Category(id: 'body', name: 'جسم', color: CategoryColors.olive),
    ],
    words: const [
      WordItem(id: 'w1', text: 'أب', categoryId: 'family'),
      WordItem(id: 'w2', text: 'أم', categoryId: 'family'),
      WordItem(id: 'w3', text: 'أخ', categoryId: 'family'),
      WordItem(id: 'w4', text: 'أخت', categoryId: 'family'),
      WordItem(id: 'w5', text: 'شمس', categoryId: 'weather'),
      WordItem(id: 'w6', text: 'مطر', categoryId: 'weather'),
      WordItem(id: 'w7', text: 'ريح', categoryId: 'weather'),
      WordItem(id: 'w8', text: 'ثلج', categoryId: 'weather'),
      WordItem(id: 'w9', text: 'خبز', categoryId: 'food'),
      WordItem(id: 'w10', text: 'أرز', categoryId: 'food'),
      WordItem(id: 'w11', text: 'لحم', categoryId: 'food'),
      WordItem(id: 'w12', text: 'جبن', categoryId: 'food'),
      WordItem(id: 'w13', text: 'يد', categoryId: 'body'),
      WordItem(id: 'w14', text: 'عين', categoryId: 'body'),
      WordItem(id: 'w15', text: 'أذن', categoryId: 'body'),
      WordItem(id: 'w16', text: 'قلب', categoryId: 'body'),
    ],
  ),
  Level(
    number: 3,
    title: 'العالم من حولنا',
    categories: const [
      Category(id: 'school', name: 'مدرسة', color: CategoryColors.indigo),
      Category(id: 'transport', name: 'مواصلات', color: CategoryColors.mint),
      Category(id: 'jobs', name: 'مهن', color: CategoryColors.plum),
      Category(id: 'countries', name: 'دول', color: CategoryColors.slate),
    ],
    words: const [
      WordItem(id: 'w1', text: 'كتاب', categoryId: 'school'),
      WordItem(id: 'w2', text: 'قلم', categoryId: 'school'),
      WordItem(id: 'w3', text: 'ممحاة', categoryId: 'school'),
      WordItem(id: 'w4', text: 'دفتر', categoryId: 'school'),
      WordItem(id: 'w5', text: 'سيارة', categoryId: 'transport'),
      WordItem(id: 'w6', text: 'قطار', categoryId: 'transport'),
      WordItem(id: 'w7', text: 'طائرة', categoryId: 'transport'),
      WordItem(id: 'w8', text: 'دراجة', categoryId: 'transport'),
      WordItem(id: 'w9', text: 'طبيب', categoryId: 'jobs'),
      WordItem(id: 'w10', text: 'معلم', categoryId: 'jobs'),
      WordItem(id: 'w11', text: 'مهندس', categoryId: 'jobs'),
      WordItem(id: 'w12', text: 'طيار', categoryId: 'jobs'),
      WordItem(id: 'w13', text: 'مصر', categoryId: 'countries'),
      WordItem(id: 'w14', text: 'السعودية', categoryId: 'countries'),
      WordItem(id: 'w15', text: 'المغرب', categoryId: 'countries'),
      WordItem(id: 'w16', text: 'الأردن', categoryId: 'countries'),
    ],
  ),
];
