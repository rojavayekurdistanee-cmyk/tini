import 'package:flutter/material.dart';
import 'crop_basic_effects_export.dart';
import 'crop_vibe_effects_spec.dart';
import 'crop_dynamic_effects_export.dart';
import 'crop_lighting_effects_export.dart';
import 'crop_amazing_next8_export.dart';
import 'crop_amazing_ten_export.dart';
import 'crop_amazing_effects_export.dart';
import 'crop_glitch_effects_export.dart';
import 'crop_distortion_effects_export.dart';
import 'crop_classic_effects_export.dart';
import 'crop_screen_effects_export.dart';
import 'crop_nature_effects_export.dart';
import 'crop_texture_effects_export.dart';
import 'crop_body_fx_names.dart';

/// Recorded names from the supplied Effects reference. Truncated source labels
/// deliberately remain truncated: they must not be silently invented.
class TiniEffectCategory {
  final String name;
  final List<String> names;
  const TiniEffectCategory(this.name, this.names);
}

class TiniEffectDescriptor {
  final String category;
  final String name;
  final int occurrence;
  const TiniEffectDescriptor(this.category, this.name, {this.occurrence = 1});
  String get id => '$category/$name${occurrence > 1 ? '#$occurrence' : ''}';
  bool get available => TiniEffectsCatalog.isRenderable(name, category);
  Color get color => TiniEffectsCatalog.colorFor(id);
}

class TiniEffectsCatalog {
  static List<String> _names(String text) => text.split('|').map((e) => e.trim())
      .where((e) => e.isNotEmpty).toList(growable: false);

  // Preserve the reference's 15 tabs, excluding its 'جديد' tab entirely.
  static final List<TiniEffectCategory> categories = [
    TiniEffectCategory('مقدمة وخاتمة', _names('Transform to Fall|Axis Rotation|Starry Zoom|Gradual Focusing|Vertical Open|Horizontal Close|Low Exposure|Camera Focus 1|Zoom In|Horizontal Open|Horizontal Open|The End|Switch Off|Switch On|Shooting Frame|Countdown|Slip|Scroll|Rotate|Circle|Vertical|Horizon')),
    TiniEffectCategory('أساسية', _names('Chrome Blur|Screenshot ...|Chromatic A...|Noise|Halo Blur|Hazy|Rotary Focus|Vertical Blur|Zoom Lens|Blurry Focus|Blur Close|Rebound Swi...|Vignette|Blur|Fisheye III|Diamond Zoo...|Motion Blur|Magnifying ...|Mini Zoom|Slanted Blur|TV Jitter|Window|Zoom|Background ...|HDR|Zoom Sketch')),
    TiniEffectCategory('Vibe', _names('Super Love B...|Rose petals|Heart Project...|Love Spotlig...|Bokeh Shower|Sparkly Conf...|Glitter Bomb|Hearts trail|In Love|Christmas D...|Christmas D...|Snow Bokeh|Fireworks|Spiderweb|Floating Can...|Snow Storm|Christmas Or...|Flickering Lig...|Stars|Romantic Sp...|Love Zoom|Magic Transf...|Sequin Rain|Cyberpunk Li...|Pizzazz 2|Girl Heart|Color Riot|Fairy Glitter|Mini stars 3|Starlight|Twinkle 2|Pink Hearts|Cute Hearts|Star Shine|Shining Moon|Snowflakes|Iridescent|Snowburst|Star Rain 1|Heart Rays|Mini stars 2|Streamers|July 4th Fire...|Watercolor|Flowers|Star Rain 2|Butterfly Fea...|Milky Way|Burning Love...|Utopia|Christmas St...|Gleam|Heartbeat|Whimsical|Star Power|Winter Aesth...|Starburst|Confetti|Heart Kisses|In My Heart|Color Hearts|Butterflies|Sparkle|Fireworks III|Color Diamo...|Sparkling|Romantic He...|Shooting Sta...|Stellar|Pink Sparkles|Rainbow Hea...|Fireworks II|Falling Gold ...|Moonlight Ex...|Radiating He...|Glowworm|Star Rain III|Color Confetti|Gold Glitter III|Fireworks I|Refraction|Meteor Show...|Starscape|Xmas Stars|Shards of Lig...|Starry Night|Butterfly Dre...|Gold Glitter|Beating Heart|Gold Powder|Firefly|Gold Sparkles|Spark I|Butterfly|Bling|Heart|Fluorescence|Winter Lights|Spring Bloss...|Circling Spar...')),
    TiniEffectCategory('ديناميكية', _names('Disco|Club Mood|Club lights|Orange Nega...|Shake + Scre...|Shaky Camer...|Shake 1|Shake 2|Shake|Trembling|Colorful|RGB Border|Neon|Chromatic|Delay|Stuck Frame|Flash II|Flash I|Black Flash II|Black Flash|White Flash|Flicker|Chromo-zoom|Astral|Unreal II|ظل|Bounce Cam...|Play Pendulu...|Throb|Beat|Pulse|Strobe|Sway|Soul|Flash')),
    TiniEffectCategory('إضاءة', _names('Frost Soft Le...|Diamond Sof...|Soft Light|Over Exposu...|Dream Glow|Red Glow|Glow|Leak II|Leak 1|Leak|Vaporwave|Neon|Halo Light II|Rainbow Sha...|Water Reflec...|Angel|Tyndall Light|Backlight|Prism I|Lights')),
    TiniEffectCategory('مذهلة', _names('H2L Text|2026 Loading|Disco Count|Love Window|Negative Gra...|Fire-Hot|Lyric Cut|Octopus End|Negative Wa...|American Co...|Reverse|Negative Spli...|Comic Book ...|Surveillance ...|Light Leaks|Color Negati...|سنة جديدة|خلل|Quick Speed|Energy|Split Apart|Question Ma...|Something\'s ...|Scanning lig...|Shockwave|Moon Off|Illusion')),
    TiniEffectCategory('خلل', _names('Fuzzy|X-Signal|Edgy|Edge Glitch|خلل|70\'s')),
    TiniEffectCategory('تشويه', _names('Waves 2|Concentric C...|Stretched W...|Ripple Distor...|Ripples')),
    TiniEffectCategory('كلاسيكية', _names('Slide Show|Black Noise|Vintage Film|Film Freeze|DV Tape|Viewfinder|Memory Film|Retro Blue|To B&W|B&W Film|Retro Burst|Black & White|FPS Lag|1998|JVC|Retro DV 3|Black Sprock...|Vintage Video|Saturated Fil...|Out of Focus|Noise I|White Retro ...|70s')),
    TiniEffectCategory('شاشة', _names('Seagull Digit...|Balloon Frame|Yellow And B...|Cute Polaroid|Graphic 2|MV Cover|DV|Spring Border|DV II|Camera Grid|Viewfinder II|Graphic III|Cinema|Camcorder II|Color Phosp...')),
    TiniEffectCategory('الطبيعة', _names('Fluffy Snow|Snowfall|Snow|Snowflake|Snow II|Flying Snow|Rain FX|Rain|Falling Leaves|Petals|Rose Petals|Soft Rose|Pink Petals|Sakura|Sunset 1|Sunset 2|Sunshine|Tree Shade 2|Heat Wave|Smog')),
    TiniEffectCategory('ملمس', _names('Crease|Paper Border|Silkscreen|blue mosaic|Grain|Blue Mosaic')),
    TiniEffectCategory('انقسام الشاشة', _names('Nine|Six|Four|Triptych|Focus Left|Focus Top')),
    TiniEffectCategory('مؤثر شكل الجسم', _names('Halo 1|Hellfire|Ghost|Butterfly Win...|Aura|Mechanical 2|Phantom|Enveloping L...|White Outline|Squad Yours...|Sliding Door...|Color Fringe|Thermal Heat|Tunnel Lights|Oscars|Colorful Outl...|Water Lighti...|Rainbow Sha...|Starry Clouds|Doodle Groo...|Sinking|Scattering Fr...|Background ...|Glowing Rain|أشكال|أجنحة|Thermal Aura...|Thermal Aura|تحديد|بريق')),
    TiniEffectCategory('مؤثر شكل الوجه', _names('Destiny|Dazz Cam|soft light eff...|Scarlet Mario...|cpm35|Iphone 13 Bl...|قمري قديم ✧|كيم|كيلز|تحسين لون|نجوم|bluegrain|DN 02|Blur Beauty|Pixel Shuffle ...|مكياج فرنسي|vintage look|Lux|ngoi sao|Soft Latte|kim x rio expo|2014 Dog Ch...|2016 soft bro...|Late Night 16...|Inner Red Lips|Goat Eyes|Small Body B...|Love Face|Light Shade|Purple Iris|Round Glass...|Butterfly Sun...|Halo|Purple Lips|Heart Cheek...|Blush Makeup|Festival|Blue Wing|Outliner Lips|Antlers|Lizard Eyes|Hat and Scarf|Black Wing|Royal Crown|Glasses|Round Sun G...|Orange Lips|Robot Eyes|Facial Fisheye|Colored Lash|Shade|Inner Glow Iris|Half Face Wh...|Freckles|Cyborg Eyes|Vanilla|Manga Lashes|Fantasy Butt...|Big & Bold Li...|Red Lips|No Signal|Dreamland 1|Laser Eyes 2|Little Devil|Future Glass...|Departing So...|Dark Skies|Divine|Salivate|Shy|Green Face|Dreamcatcher|مشمس|In Love|Red Face|3D Bunny|Woozy|Neon Helmet|Tall Hat|Mini Heads|Large Eyes|Full Lash|Police Hat|Light Lips|Sweaty Face|Bobsledder|Flower Fairy|Chipmunk Me|Animal Run|Fall Makeup|High Horse|Wonderful S...|Furry Brows|Eyeliner|Football Run|Grey Braids|Cruel|Large Chin|Vacation Walk|Cat Eyes|Pixelate|Lilac Frost|Pink Glow|Manga Aesth...|Closed Eyes|Feeling Hurt|Glitter Glow|Tongue out|Face Mosaic|Lasers')),
  ];

  // Only effects with actual preview/export implementations may be selected.
  // Unimplemented face/body AR, particles, masks and truncated labels remain
  // discoverable as reference metadata but never produce a fake generic filter.
  static const Set<String> _implemented = {
    'Low Exposure','Zoom In','Switch Off','Switch On','Rotate','Vertical','Horizon',
    'Noise','Halo Blur','Hazy','Vertical Blur','Blurry Focus','Vignette','Blur',
    'Fisheye III','Motion Blur','Mini Zoom','Slanted Blur','TV Jitter','Zoom','HDR',
    'Disco','Club Mood','Club lights','Shake 1','Shake 2','Shake','Trembling',
    'Colorful','Neon','Chromatic','Flash II','Flash I','Black Flash II',
    'Black Flash','White Flash','Flicker','Throb','Beat','Pulse','Strobe',
    'Soft Light','Dream Glow','Red Glow','Glow','Vaporwave','Backlight','Lights',
    'Color Negati...','Reverse','Surveillance ...','خلل',
    'Fuzzy','X-Signal','Edgy','Edge Glitch','70\'s',
    'Waves 2','Ripples',
    'Black Noise','Vintage Film','Film Freeze','Retro Blue','To B&W','B&W Film',
    'Black & White','1998','Vintage Video','Saturated Fil...','Out of Focus','Noise I','70s',
    'DV','DV II','Camera Grid','Viewfinder II','Cinema','Camcorder II',
    'Sunset 1','Sunset 2','Sunshine','Heat Wave','Smog',
    'Silkscreen','blue mosaic','Grain','Blue Mosaic','Nine','Six','Four','Triptych','Focus Left','Focus Top',
    'تحسين لون','bluegrain','vintage look','Lux','Soft Latte','Red Face','Green Face',
    'Pixelate','Face Mosaic',
  };

  static bool isRenderable(String name, String category) {
    // Intro/Outro recipes are implemented separately from generic colour FX.
    if (category == 'مقدمة وخاتمة') {
      return const <String>{
        'Transform to Fall', 'Axis Rotation', 'Starry Zoom', 'Gradual Focusing',
        'Vertical Open', 'Horizontal Close', 'Low Exposure', 'Camera Focus 1',
        'Zoom In', 'Horizontal Open', 'The End', 'Switch Off', 'Switch On',
        'Shooting Frame', 'Countdown', 'Slip', 'Scroll', 'Rotate', 'Circle',
        'Vertical', 'Horizon',
      }.contains(name);
    }
    // Enable only Basic recipes backed by the dedicated export engine.
    if (category == 'أساسية') {
      return TiniBasicEffectsExport.supported.contains(name);
    }
    if (category == TiniVibeEffectsSpec.category) {
      return TiniVibeEffectsSpec.supported.contains(name);
    }
    if (category == TiniDynamicEffectsExport.category) {
      return TiniDynamicEffectsExport.supported.contains(name);
    }
    if (category == TiniLightingEffectsExport.category) {
      return TiniLightingEffectsExport.supported.contains(name);
    }
    // Both batches of eight reference items are implemented in Amazing.
    if (category == TiniAmazingEffectsExport.category) {
      return TiniAmazingEffectsExport.supported.contains(name) ||
          TiniAmazingNextEightExport.supported.contains(name) ||
          TiniAmazingTenExport.supported.contains(name) ||
          name == 'خلل';
    }
    if (category == TiniGlitchEffectsExport.category) {
      return TiniGlitchEffectsExport.supported.contains(name);
    }
    if (category == TiniDistortionEffectsExport.category) {
      return TiniDistortionEffectsExport.supported.contains(name);
    }
    if (category == TiniClassicEffectsExport.category) {
      return TiniClassicEffectsExport.supported.contains(name);
    }
    if (category == TiniScreenEffectsExport.category) {
      return TiniScreenEffectsExport.supported.contains(name);
    }
    if (category == TiniNatureEffectsExport.category) {
      return TiniNatureEffectsExport.supported.contains(name);
    }
    if (category == TiniTextureEffectsExport.category) {
      return TiniTextureEffectsExport.supported.contains(name);
    }
    // Only enable effect names that use Android segmentation masks; the
    // remaining references are deliberately not replaced by fake filters.
    if (category == TiniBodyFxNames.category) {
      return TiniBodyFxNames.supported.contains(name);
    }
    if ({'Reverse','Film Freeze','Waves 2','Ripples','Heat Wave',
        'Smog','Vertical','Horizon','Switch Off','Switch On',
        'Slanted Blur','Throb'}.contains(name)) return false;
    if (category == 'مؤثر شكل الوجه' &&
        {'Bobsledder', '2014 Dog Ch...'}.contains(name)) return true;
    if (category == 'مؤثر شكل الوجه' &&
        !{'تحسين لون','bluegrain','vintage look','Lux','Soft Latte','Pixelate'}
            .contains(name)) return false;
    return _implemented.contains(name);
  }

  static List<TiniEffectDescriptor> itemsFor(String category) {
    final group = categories.firstWhere((e) => e.name == category);
    // Some reference items share a visibly identical label. Keep both, with
    // stable, distinct IDs, so selecting one never selects the other.
    final seen = <String, int>{};
    return [for (final name in group.names)
      TiniEffectDescriptor(category, name,
        occurrence: seen.update(name, (count) => count + 1,
          ifAbsent: () => 1))];
  }

  static TiniEffectDescriptor? find(String id) {
    // Backwards compatibility for selections created by the previous build.
    const oldIntroNames = <String, String>{
      'Transform to ...': 'Transform to Fall',
      'Gradual Focu...': 'Gradual Focusing',
      'Horizontal Cl...': 'Horizontal Close',
      'Camera Focu...': 'Camera Focus 1',
      'Horizontal O...': 'Horizontal Open',
      'Shooting Fra...': 'Shooting Frame',
    };
    const prefix = 'مقدمة وخاتمة/';
    var target = id;
    if (id.startsWith(prefix)) {
      final original = id.substring(prefix.length);
      if (oldIntroNames.containsKey(original)) {
        target = '$prefix${oldIntroNames[original]}';
      }
    }
    for (final category in categories) {
      for (final item in itemsFor(category.name)) {
        if (item.id == target) return item;
      }
    }
    return null;
  }

  static Color colorFor(String id) {
    var hash = 0;
    for (final unit in id.codeUnits) {
      hash = (hash * 31 + unit) & 0x7fffffff;
    }
    return HSVColor.fromAHSV(1, (hash % 360).toDouble(), .7, .85).toColor();
  }
}
