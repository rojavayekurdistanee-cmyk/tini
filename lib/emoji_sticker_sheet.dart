import 'package:flutter/material.dart';
import 'sticker_layer.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// واجهة إيموجي + ملصقات بتصميم الدردشة.
/// ترجع [StickerLayer] عند الاختيار، أو null عند الإغلاق.
class EmojiStickerSheet extends StatefulWidget {
  const EmojiStickerSheet({super.key, this.inline = false, this.inlineHeight = 300, this.onEmojiSelected});

  /// Inline mode reuses the same picker inside the chat keyboard area.
  final bool inline;
  final double inlineHeight;
  final ValueChanged<String>? onEmojiSelected;

  @override
  State<EmojiStickerSheet> createState() => _EmojiStickerSheetState();
}

class _EmojiStickerSheetState extends State<EmojiStickerSheet>
    with SingleTickerProviderStateMixin {
  static const Color _bg = Color(0xFF0B141A);
  static const Color _bar = Color(0xFF1F2C34);
  static const Color _hint = Color(0xFF8696A0);
  static const Color _green = Color(0xFF00A884);

  late TabController _mainTab; // 0 = إيموجي ، 1 = ملصقات
  final TextEditingController _searchCtrl = TextEditingController();
  final ScrollController _emojiScroll = ScrollController();
  int _emojiCatIndex = 0;
  String _search = '';
  List<String> _recentEmojis = ['😀', '😍', '👍', '🇺🇸', '😂', '🥰', '🔥', '❤', '👏', '🙏'];
  static const String _recentKey = 'recent_emojis';

  // —— تصنيفات الإيموجي ——
  List<_EmojiCat> get _cats => [
    _EmojiCat(
      key: 'recent',
      title: 'المستخدمة مؤخراً',
      icon: Icons.access_time_rounded,
      emojis: _recentEmojis,
    ),
    _EmojiCat(
      key: 'smileys',
      title: 'وجوه ضاحكة وأشخاص',
      icon: Icons.emoji_emotions_outlined,
      emojis: [
        '😀', '😃', '😄', '😁', '😆', '😅', '🤣', '😂', '🙂', '🙃',
        '😉', '😊', '😇', '🥰', '😍', '🤩', '😘', '😗', '😚', '😙',
        '🥲', '😋', '😛', '😜', '🤪', '😝', '🤑', '🤗', '🤭', '🤫',
        '🤔', '🤐', '🤨', '😐', '😑', '😶', '😏', '😒', '🙄', '😬',
        '😮‍💨', '🤥', '😌', '😔', '😪', '🤤', '😴', '😷', '🤒', '🤕',
        '🤢', '🤮', 'sneezing', '🥵', '🥶', '🥴', '😵', '🤯', '🤠', '🥳',
        '🥸', '😎', '🤓', '🧐', '😕', '😟', '🙁', '☹️', '😮', '😯',
        '😲', '😳', '🥺', '😦', '😧', '😨', '😰', '😥', '😢', '😭',
        '😱', '😖', '😣', '😞', '😓', '😩', '😫', '🥱', '😤', '😡',
        '😠', '🤬', '😈', '👿', '💀', '☠️', '💩', '🤡', '👹', '👺',
        '👻', '👽', '👾', '🤖', '😺', '😸', '😹', '😻', '😼', '😽',
        '🙀', '😿', '😾', '🙈', '🙉', '🙊', '💋', '💌', '💘', '💝',
        '💖', '💗', '💓', '💞', '💕', '💟', '❣️', '💔', '❤️', '🧡',
        '💛', '💚', '💙', '💜', '🤎', '🖤', '🤍', '💯', '💢', '💥',
        '💫', '💦', '💨', '🕳️', '💣', '💬', '👁️‍🗨️', '🗨️', '🗯️', '💭',
        '👋', '🤚', '🖐️', '✋', '🖖', '👌', '🤌', '🤏', '✌️', '🤞',
        '🤟', '🤘', '🤙', '👈', '👉', '👆', '🖕', '👇', '☝️', '👍',
        '👎', '✊', '👊', '🤛', '🤜', '👏', '🙌', '👐', '🤲', '🤝',
        '🙏', '✍️', '💅', '🤳', '💪', '🦾', '🦵', '🦶', '👂', '🦻',
        'nose', '🧠', '🫀', 'lungs', '🦷', '🦴', '👀', '👁️', '👅', '👄',
        '👶', '🧒', '👦', '👧', '🧑', 'blond', '👨', 'beard', '👩', 'older',
        '👴', '👵', 'فrown', 'pout', '🙅', '🙆', '💁', '🙋', 'deaf', 'bow',
        'facepalm', 'shrug', 'police', 'detective', 'guard', 'ninja', 'construction',
        'prince', 'princess', 'turban', 'gua', 'hijab', 'tuxedo', 'bride',
        'pregnant', 'breastfeed', 'angel', 'santa', 'mrsclaus', 'superhero',
        'supervillain', 'mage', 'fairy', 'vampire', 'merperson', 'elf',
        'genie', 'zombie', 'massage', 'haircut', 'walking', 'standing',
        'kneeling', 'running', 'dancing', 'man_dancing', 'business', 'people',
        'sauna', 'climbing', 'fencing', 'horse', 'skier', 'snowboarder',
        'golfing', 'surfing', 'rowing', 'swimming', 'bouncing', 'lifting',
        'biking', 'mountain_biking', 'cartwheel', 'wrestling', 'water_polo',
        'handball', 'juggling', 'lotus', 'bath', 'sleeping_accommodation',
      ].where((e) => e.length <= 4 || e.runes.length <= 2).toList(), // تنظيف أي نص إنجليزي بالخطأ
    ),
    _EmojiCat(
      key: 'animals',
      title: 'حيوانات وطبيعة',
      icon: Icons.pets_outlined,
      emojis: [
        '🐶', '🐱', '🐭', '🐹', '🐰', '🦊', '🐻', '🐼', '🐻‍❄️', '🐨',
        '🐯', '🦁', '🐮', '🐷', '🐽', '🐸', '🐵', '🙈', '🙉', '🙊',
        '🐒', '🐔', '🐧', '🐦', '🐤', '🐣', '🐥', '🦆', '🦅', '🦉',
        '🦇', '🐺', '🐗', '🐴', '🦄', '🐝', '🪱', '🐛', '🦋', '🐌',
        '🐞', '🐜', '🪰', '🪲', '🪳', '🦟', '🦗', '🕷️', '🕸️', '🦂',
        '🐢', '🐍', '🦎', '🦖', '🦕', '🐙', '🦑', '🦐', '🦞', '🦀',
        '🐡', '🐠', '🐟', '🐬', '🐳', '🐋', '🦈', '🐊', '🐅', '🐆',
        '🦓', '🦍', '🦧', '🦣', '🐘', '🦛', '🦏', '🐪', '🐫', '🦒',
        '🦘', '🦬', 'buffalo', 'ox', 'cow', 'horse2', 'pig2', 'ram', 'sheep',
        'llama', 'goat', 'deer', 'dog2', 'poodle', 'guide_dog', 'service_dog',
        'cat2', 'black_cat', 'feather', 'rooster', 'turkey', 'dodo', 'peacock',
        'parrot', 'swan', 'flamingo', 'dove', 'rabbit2', 'raccoon', 'skunk',
        'badger', 'beaver', 'otter', 'sloth', 'mouse2', 'rat', 'chipmunk',
        'hedgehog', 'cactus', 'christmas_tree', 'evergreen', 'deciduous', 'palm',
        'wood', 'seedling', 'herb', 'shamrock', 'four_leaf', 'bamboo', 'potted',
        'tanabata', 'leaves', 'fallen_leaf', 'maple', 'mushroom', 'shell',
        'rock', 'ear_of_rice', 'bouquet', 'tulip', 'rose', 'wilted', 'hibiscus',
        'cherry_blossom', 'blossom', 'sunflower', 'sun_with_face', 'full_moon_face',
        'first_quarter', 'last_quarter', 'new_moon_face', 'full_moon', 'waning_gibbous',
        'last_quarter_moon', 'waning_crescent', 'new_moon', 'waxing_crescent',
        'first_quarter_moon', 'waxing_gibbous', 'crescent', 'earth_americas',
        'earth_africa', 'earth_asia', 'ringed_planet', 'dizzy', 'star', 'glowing_star',
        'sparkles', 'zap', 'comet', 'boom', 'fire', 'tornado', 'rainbow', 'sunny',
        'sun_behind_small', 'partly_sunny', 'sun_behind_large', 'cloud', 'sun_behind_rain',
        'cloud_with_rain', 'cloud_with_lightning_rain', 'cloud_with_lightning',
        'cloud_with_snow', 'snowflake', 'snowman2', 'snowman', 'wind_face', 'dash',
        'droplet', 'sweat_drops', 'umbrella', 'umbrella2', 'ocean', 'fog',
      ].where((e) => !RegExp(r'[a-zA-Z_]').hasMatch(e)).toList(),
    ),
    _EmojiCat(
      key: 'food',
      title: 'طعام وشراب',
      icon: Icons.fastfood_outlined,
      emojis: [
        '🍇', '🍈', '🍉', '🍊', '🍋', '🍌', '🍍', '🥭', '🍎', '🍏',
        '🍐', '🍑', '🍒', '🍓', '🫐', '🥝', '🍅', '🫒', '🥥', '🥑',
        '🍆', '🥔', '🥕', '🌽', '🌶️', '🫑', 'cucumber', 'leafy', 'broccoli',
        'garlic', 'onion', 'mushroom', 'peanuts', 'chestnut', 'bread', 'croissant',
        'baguette', 'flatbread', 'pretzel', 'bagel', 'pancakes', 'waffle', 'cheese',
        'meat', 'poultry', 'cut_of_meat', 'bacon', 'hamburger', 'fries', 'pizza',
        'hotdog', 'sandwich', 'taco', 'burrito', 'tamale', 'stuffed', 'falafel',
        'egg', 'cooking', 'shallow', 'stew', 'fondue', 'bowl', 'green_salad',
        'popcorn', 'butter', 'salt', 'canned', 'bento', 'rice_cracker', 'rice_ball',
        'rice', 'curry', 'ramen', 'spaghetti', 'sweet_potato', 'oden', 'sushi',
        'fried_shrimp', 'fish_cake', 'moon_cake', 'dango', 'dumpling', 'fortune',
        'takeout', 'crab', 'lobster', 'shrimp', 'squid', 'oyster', 'icecream',
        'shaved', 'ice_cream', 'doughnut', 'cookie', 'birthday', 'cake', 'cupcake',
        'pie', 'chocolate', 'candy', 'lollipop', 'custard', 'honey', 'baby_bottle',
        'milk', 'coffee', 'teapot', 'tea', 'sake', 'champagne', 'wine', 'cocktail',
        'tropical', 'beer', 'beers', 'clinking', 'tumbler', 'cup_with_straw',
        'bubble_tea', 'beverage', 'mate', 'ice', 'chopsticks', 'plate', 'fork',
        'spoon', 'knife', 'amphora',
      ].where((e) => !RegExp(r'[a-zA-Z_]').hasMatch(e)).toList(),
    ),
    _EmojiCat(
      key: 'activity',
      title: 'نشاطات',
      icon: Icons.sports_soccer_outlined,
      emojis: [
        '⚽', '🏀', '🏈', '⚾', '🥎', '🎾', '🏐', '🏉', '🥏', '🎱',
        '🪀', '🏓', '🏸', '🏒', '🏑', '🥍', '🏏', '🪃', '🥅', '⛳',
        '🪁', '🏹', '🎣', '🤿', '🥊', '🥋', '🎽', '🛹', '🛼', '🛷',
        '⛸️', '🥌', '🎿', '⛷️', '🏂', '🪂', '🏋️', '🤼', '🤸', '⛹️',
        '🤺', '🤾', '🏌️', '🏇', '🧘', '🏄', '🏊', '🤽', '🚣', '🧗',
        '🚵', '🚴', '🏆', '🥇', '🥈', '🥉', '🏅', '🎖️', '🏵️', '🎗️',
        '🎫', '🎟️', '🎪', '🤹', '🎭', '🩰', '🎨', '🎬', '🎤', '🎧',
        '🎼', '🎹', '🥁', '🪘', '🎷', '🎺', '🪗', '🎸', '🪕', '🎻',
        '🎲', '♟️', '🎯', '🎳', '🎮', '🕹️', '🎰', '🧩',
      ],
    ),
    _EmojiCat(
      key: 'travel',
      title: 'سفر وأماكن',
      icon: Icons.flight_outlined,
      emojis: [
        '🚗', '🚕', '🚙', '🚌', '🚎', '🏎️', '🚓', '🚑', '🚒', '🚐',
        '🛻', '🚚', '🚛', 'tractor', 'white_cane', 'manual_wheelchair',
        'motorized_wheelchair', 'kick_scooter', 'bike', 'motor_scooter',
        'motorcycle', 'auto_rickshaw', 'rotating_light', 'oncoming_police',
        'oncoming_bus', 'oncoming_automobile', 'oncoming_taxi', 'aerial_tramway',
        'mountain_cableway', 'suspension_railway', 'railway_car', 'tram_car',
        'mountain_railway', 'monorail', 'bullettrain_side', 'bullettrain_front',
        'light_rail', 'steam_locomotive', 'train2', 'metro', 'tram', 'station',
        'airplane', 'flight_departure', 'flight_arrival', 'small_airplane',
        'seat', 'satellite', 'rocket', 'flying_saucer', 'helicopter', 'canoe',
        'sailboat', 'speedboat', 'motor_boat', 'passenger_ship', 'ferry',
        'ship', 'anchor', 'hook', 'fuelpump', 'construction', 'vertical_traffic',
        'horizontal_traffic', 'busstop', 'world_map', 'moyai', 'statue_of_liberty',
        'tokyo_tower', 'european_castle', 'japanese_castle', 'stadium',
        'ferris_wheel', 'roller_coaster', 'carousel_horse', 'fountain',
        'beach_umbrella', 'beach_with_umbrella', 'desert_island', 'desert',
        'volcano', 'mountain', 'snow_capped', 'mount_fuji', 'camping', 'tent',
        'house', 'house_with_garden', 'houses', 'derelict', 'building_construction',
        'factory', 'office', 'department_store', 'post_office', 'european_post',
        'hospital', 'bank', 'hotel', 'convenience', 'school', 'love_hotel',
        'wedding', 'classical_building', 'church', 'mosque', 'hindu_temple',
        'synagogue', 'shinto_shrine', 'kaaba',
      ].where((e) => !RegExp(r'[a-zA-Z_]').hasMatch(e)).toList(),
    ),
    _EmojiCat(
      key: 'objects',
      title: 'أشياء',
      icon: Icons.lightbulb_outline,
      emojis: [
        '⌚', '📱', '📲', '💻', '⌨️', '🖥️', '🖨️', '🖱️', '🖲️', 'joystick',
        'clamp', 'minidisc', 'floppy', 'cd', 'dvd', 'vhs', 'camera', 'camera_flash',
        'video_camera', 'movie_camera', 'film_projector', 'film_frames', 'telephone_receiver',
        'phone', 'pager', 'fax', 'tv', 'radio', 'studio_microphone', 'level_slider',
        'control_knobs', 'compass', 'stopwatch', 'timer', 'alarm_clock', 'mantelpiece',
        'hourglass', 'hourglass_flowing', 'satellite_antenna', 'battery', 'electric_plug',
        'bulb', 'flashlight', 'candle', 'diya', 'fire_extinguisher', 'oil', 'money_with_wings',
        'dollar', 'yen', 'euro', 'pound', 'coin', 'moneybag', 'credit_card', 'gem',
        'balance_scale', 'ladder', 'toolbox', 'screwdriver', 'wrench', 'hammer',
        'hammer_pick', 'tools', 'pick', 'carpentry_saw', 'nut_and_bolt', 'gear',
        'mouse_trap', 'bricks', 'chains', 'magnet', 'gun', 'bomb', 'firecracker',
        'axe', 'knife', 'dagger', 'crossed_swords', 'shield', 'cigarette', 'coffin',
        'headstone', 'funeral_urn', 'amphora', 'crystal_ball', 'prayer_beads', 'nazar',
        'barber', 'alembic', 'telescope', 'microscope', 'hole', 'adhesive_bandage',
        'stethoscope', 'pill', 'syringe', 'drop_of_blood', 'dna', 'microbe', 'petri',
        'test_tube', 'thermometer', 'broom', 'plunger', 'basket', 'roll_of_paper',
        'toilet', 'potable', 'shower', 'bathtub', 'bath', 'soap', 'toothbrush',
        'razor', 'sponge', 'bucket', 'lotion', 'bellhop', 'key', 'old_key', 'door',
        'chair', 'couch', 'bed', 'sleeping', 'teddy', 'framed', 'mirror', 'window',
        'shopping_bags', 'shopping_cart', 'gift', 'balloon', 'carp', 'ribbon',
        'magic_wand', 'pinata', 'confetti', 'tada', 'dolls', 'izakaya', 'wind_chime',
        'red_envelope', 'envelope', 'envelope_with_arrow', 'incoming', 'e-mail',
        'love_letter', 'inbox', 'outbox', 'package', 'label', 'placard', 'mailbox',
        'mailbox_closed', 'mailbox_with', 'mailbox_with_no', 'postbox', 'postal_horn',
        'scroll', 'page_with', 'page_facing', 'bookmark_tabs', 'receipt', 'bar_chart',
        'chart_increasing', 'chart_decreasing', 'spiral_notepad', 'spiral_calendar',
        'calendar', 'tear_off', 'wastebasket', 'card_index', 'card_file', 'ballot',
        'file_cabinet', 'clipboard', 'file_folder', 'open_file', 'card_index_dividers',
        'newspaper', 'notebook', 'notebook_with', 'ledger', 'closed_book', 'green_book',
        'blue_book', 'orange_book', 'books', 'open_book', 'bookmark', 'safety_pin',
        'link', 'paperclip', 'linked', 'triangular_ruler', 'straight_ruler', 'abacus',
        'pushpin', 'round_pushpin', 'scissors', 'pen', 'fountain', 'black_nib',
        'paintbrush', 'crayon', 'memo', 'pencil', 'mag', 'mag_right', 'lock_with',
        'closed_lock', 'lock', 'unlock',
      ].where((e) => !RegExp(r'[a-zA-Z_]').hasMatch(e)).toList(),
    ),
    _EmojiCat(
      key: 'symbols',
      title: 'رموز',
      icon: Icons.tag_outlined,
      emojis: [
        '❤️', '🧡', '💛', '💚', '💙', '💜', '🖤', 'white_heart', 'brown_heart',
        'broken_heart', 'heart_exclamation', 'two_hearts', 'revolving', 'heartbeat',
        'heartpulse', 'sparkling', 'cupid', 'gift_heart', 'heart_decoration',
        'peace', 'cross', 'star_crescent', 'om', 'wheel_dharma', 'star_of_david',
        'dotted_six', 'menorah', 'yin_yang', 'orthodox', 'place_worship',
        'ophiuchus', 'aries', 'taurus', 'gemini', 'cancer', 'leo', 'virgo',
        'libra', 'scorpius', 'sagittarius', 'capricorn', 'aquarius', 'pisces',
        'id', 'atom', 'accept', 'radioactive', 'biohazard', 'mobile_phone_off',
        'vibration', 'u6709', 'u7121', 'u7533', 'u55b6', 'u6708', 'eight_pointed',
        'vs', 'white_flower', 'ideograph', 'secret', 'congratulations', 'u5408',
        'u6e80', 'u5272', 'u7981', 'a', 'b', 'ab', 'cl', 'o2', 'sos', 'x',
        'o', 'stop_sign', 'no_entry', 'name_badge', 'no_entry_sign', '100',
        'anger', 'hotsprings', 'no_pedestrians', 'do_not_litter', 'no_bicycles',
        'non-potable', 'underage', 'no_mobile', 'no_smoking', 'exclamation',
        'grey_exclamation', 'question', 'grey_question', 'bangbang', 'interrobang',
        'low_brightness', 'high_brightness', 'part_alternation', 'warning',
        'children_crossing', 'trident', 'fleur', 'beginner', 'recycle', 'white_check',
        'u6307', 'chart', 'sparkle', 'eight_spoked', 'negative', 'globe',
        'diamond_shape', 'm', 'cyclone', 'zzz', 'atm', 'wc', 'wheelchair',
        'parking', 'elevator', 'u7a7a', 'sa', 'passport', 'customs', 'baggage',
        'left_luggage', 'mens', 'womens', 'baby_symbol', 'transgender', 'restroom',
        'put_litter', 'cinema', 'signal_strength', 'koko', 'symbols', 'information',
        'abc', 'abcd', 'capital_abcd', 'ng', 'ok', 'up', 'cool', 'new', 'free',
        'zero', 'one', 'two', 'three', 'four', 'five', 'six', 'seven', 'eight',
        'nine', 'keycap_ten', '1234', 'hash', 'asterisk', 'eject', 'arrow_forward',
        'pause', 'play_pause', 'stop', 'record', 'next_track', 'previous',
        'fast_forward', 'rewind', 'arrow_double_up', 'arrow_double_down',
        'arrow_backward', 'arrow_up_small', 'arrow_down_small', 'arrow_right',
        'arrow_left', 'arrow_up', 'arrow_down', 'arrow_upper_right', 'arrow_lower_right',
        'arrow_lower_left', 'arrow_upper_left', 'arrow_up_down', 'left_right',
        'arrow_right_hook', 'leftwards', 'arrow_heading_up', 'arrow_heading_down',
        'twisted', 'repeat', 'repeat_one', 'arrows_counterclockwise', 'arrows_clockwise',
        'musical_note', 'notes', 'heavy_plus', 'heavy_minus', 'heavy_division',
        'heavy_multiplication', 'infinity', 'heavy_dollar', 'currency', 'tm',
        'copyright', 'registered', 'eye_in_speech', 'end', 'back', 'on', 'top',
        'soon', 'wavy', 'curly', 'loop', 'heavy_check', 'ballot_box', 'radio_button',
        'red_circle', 'orange_circle', 'yellow_circle', 'green_circle', 'blue_circle',
        'purple_circle', 'black_circle', 'white_circle', 'brown_circle',
        'small_red_triangle', 'small_red_triangle_down', 'small_orange_diamond',
        'small_blue_diamond', 'large_orange', 'large_blue', 'white_square_button',
        'black_square_button', 'black_small', 'white_small', 'black_medium_small',
        'white_medium_small', 'black_medium', 'white_medium', 'red_square',
        'orange_square', 'yellow_square', 'green_square', 'blue_square',
        'purple_square', 'black_large', 'white_large', 'brown_square',
        'speaker', 'mute', 'sound', 'loud_sound', 'bell', 'no_bell', 'mega',
        'loudspeaker', 'speech_balloon', 'thought', 'right_anger', 'spades',
        'clubs', 'hearts', 'diamonds', 'black_joker', 'flower_playing', 'mahjong',
      ].where((e) => !RegExp(r'[a-zA-Z_]').hasMatch(e)).toList(),
    ),
    _EmojiCat(
      key: 'flags',
      title: 'رايات',
      icon: Icons.flag_outlined,
      emojis: [
        '🏳️', '🏴', '🏁', '🚩', '🏳️‍🌈', '🏳️‍⚧️', '🇺🇳',
        '🇦🇫', '🇦🇱', '🇩🇿', '🇦🇸', '🇦🇩', '🇦🇴', '🇦🇮', '🇦🇶', '🇦🇬',
        '🇦🇷', '🇦🇲', '🇦🇼', '🇦🇺', '🇦🇹', '🇦🇿', '🇧🇸', '🇧🇭', '🇧🇩',
        '🇧🇧', '🇧🇾', '🇧🇪', '🇧🇿', '🇧🇯', '🇧🇲', '🇧🇹', '🇧🇴', '🇧🇦',
        '🇧🇼', '🇧🇷', '🇮🇴', '🇻🇬', '🇧🇳', '🇧🇬', '🇧🇫', '🇧🇮', '🇰🇭',
        '🇨🇲', '🇨🇦', '🇮🇨', '🇨🇻', '🇧🇶', '🇰🇾', '🇨🇫', '🇹🇩', '🇨🇱',
        '🇨🇳', '🇨🇽', '🇨🇨', '🇨🇴', '🇰🇲', '🇨🇬', '🇨🇩', '🇨🇰', '🇨🇷',
        '🇨🇮', '🇭🇷', '🇨🇺', '🇨🇼', '🇨🇾', '🇨🇿', '🇩🇰', '🇩🇯', '🇩🇲',
        '🇩🇴', '🇪🇨', '🇪🇬', '🇸🇻', '🇬🇶', '🇪🇷', '🇪🇪', '🇸🇿', '🇪🇹',
        '🇪🇺', '🇫🇰', '🇫🇴', '🇫🇯', '🇫🇮', '🇫🇷', '🇬🇫', '🇵🇫', '🇹🇫',
        '🇬🇦', '🇬🇲', '🇬🇪', '🇩🇪', '🇬🇭', '🇬🇮', '🇬🇷', '🇬🇱', '🇬🇩',
        '🇬🇵', '🇬🇺', '🇬🇹', '🇬🇬', '🇬🇳', '🇬🇼', '🇬🇾', '🇭🇹', '🇭🇳',
        '🇭🇰', '🇭🇺', '🇮🇸', '🇮🇳', '🇮🇩', '🇮🇷', '🇮🇶', '🇮🇪', '🇮🇲',
        '🇮🇱', '🇮🇹', '🇯🇲', '🇯🇵', '🇯🇪', '🇯🇴', '🇰🇿', '🇰🇪', '🇰🇮',
        '🇽🇰', '🇰🇼', '🇰🇬', '🇱🇦', '🇱🇻', '🇱🇧', '🇱🇸', '🇱🇷', '🇱🇾',
        '🇱🇮', '🇱🇹', '🇱🇺', '🇲🇴', '🇲🇬', '🇲🇼', '🇲🇾', '🇲🇻', '🇲🇱',
        '🇲🇹', '🇲🇭', '🇲🇶', '🇲🇷', '🇲🇺', '🇾🇹', '🇲🇽', '🇫🇲', '🇲🇩',
        '🇲🇨', '🇲🇳', '🇲🇪', '🇲🇸', '🇲🇦', '🇲🇿', '🇲🇲', '🇳🇦', '🇳🇷',
        '🇳🇵', '🇳🇱', '🇳🇨', '🇳🇿', '🇳🇮', '🇳🇪', '🇳🇬', '🇳🇺', '🇳🇫',
        '🇰🇵', '🇲🇰', '🇲🇵', '🇳🇴', '🇴🇲', '🇵🇰', '🇵🇼', '🇵🇸', '🇵🇦',
        '🇵🇬', '🇵🇾', '🇵🇪', '🇵🇭', '🇵🇳', '🇵🇱', '🇵🇹', '🇵🇷', '🇶🇦',
        '🇷🇪', '🇷🇴', '🇷🇺', '🇷🇼', '🇼🇸', '🇸🇲', '🇸🇹', '🇸🇦', '🇸🇳',
        '🇷🇸', '🇸🇨', '🇸🇱', '🇸🇬', '🇸🇽', '🇸🇰', '🇸🇮', '🇬🇸', '🇸🇧',
        '🇸🇴', '🇿🇦', '🇰🇷', '🇸🇸', '🇪🇸', '🇱🇰', '🇧🇱', '🇸🇭', '🇰🇳',
        '🇱🇨', '🇵🇲', '🇻🇨', '🇸🇩', '🇸🇷', '🇸🇪', '🇨🇭', '🇸🇾', '🇹🇼',
        '🇹🇯', '🇹🇿', '🇹🇭', '🇹🇱', '🇹🇬', '🇹🇰', '🇹🇴', '🇹🇹', '🇹🇳',
        '🇹🇷', '🇹🇲', '🇹🇨', '🇹🇻', '🇺🇬', '🇺🇦', '🇦🇪', '🇬🇧', '🇺🇸',
        '🇺🇾', '🇺🇿', '🇻🇺', '🇻🇦', '🇻🇪', '🇻🇳', '🇼🇫', '🇪🇭', '🇾🇪',
        '🇿🇲', '🇿🇼', '🏴󠁧󠁢󠁥󠁮󠁧󠁿', '🏴󠁧󠁢󠁳󠁣󠁴󠁿', '🏴󠁧󠁢󠁷󠁬󠁳󠁿',
      ],
    ),
  ];

  // —— حزم الملصقات ——
  final List<_StickerPack> _packs = [
    _StickerPack(
      name: 'Cuppy',
      stickers: ['☕', '🥺', '😍', '😂', '😎', '🤔', '😢', '😡', '😴', '🥳'],
    ),
    _StickerPack(
      name: 'فلومب',
      stickers: ['💜', '💙', '💚', '💛', '🧡', '❤️', '🖤', '🤍', '🤎', '💖'],
    ),
    _StickerPack(
      name: 'تيست بادز',
      stickers: ['🍔', '🍕', '🍟', '🌭', '🥪', '🌮', '🍣', '🍦', '🍩', '🍪'],
    ),
    _StickerPack(
      name: 'أصدقاء الحفلات',
      stickers: ['🎉', '🎊', '🎈', '🎁', '🥳', '🎂', '🍾', '🥂', '✨', '🌟'],
    ),
  ];

  // ملصقات ذات وظيفة
  final List<_FuncSticker> _funcStickers = [
    _FuncSticker(label: 'موقع', emoji: '📍', type: 'location'),
    _FuncSticker(label: 'وقت', emoji: '🕐', type: 'time'),
    _FuncSticker(label: 'مربع', emoji: '⬜', type: 'shape_square'),
    _FuncSticker(label: 'دائرة', emoji: '⚪', type: 'shape_circle'),
    _FuncSticker(label: 'سهم', emoji: '↗️', type: 'shape_arrow'),
    _FuncSticker(label: 'فقاعة', emoji: '💬', type: 'bubble'),
  ];

  @override
  void initState() {
    super.initState();
    _mainTab = TabController(length: 2, vsync: this);
    _mainTab.addListener(() {
      if (!_mainTab.indexIsChanging) setState(() {});
    });
    _loadRecents();
  }

  Future<void> _loadRecents() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getStringList(_recentKey);
    if (saved != null && saved.isNotEmpty) {
      setState(() => _recentEmojis = saved);
    }
  }

  @override
  void dispose() {
    _mainTab.dispose();
    _searchCtrl.dispose();
    _emojiScroll.dispose();
    super.dispose();
  }

  void _pickEmoji(String emoji) async {
    // احفظه بالمستخدمة مؤخرا
    final prefs = await SharedPreferences.getInstance();
    List<String> recents = List.from(_recentEmojis);
    recents.remove(emoji);
    recents.insert(0, emoji);
    if (recents.length > 30) recents = recents.sublist(0, 30);
    await prefs.setStringList(_recentKey, recents);
    
    final layer = StickerLayer(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      path: emoji,
      isEmoji: true,
    );
    if (!mounted) return;
    if (widget.inline) {
      widget.onEmojiSelected?.call(emoji);
    } else {
      Navigator.pop(context, layer);
    }
  }

  void _pickFunc(_FuncSticker f) {
    _pickEmoji(f.emoji);
  }

  List<String> get _filteredEmojis {
    if (_search.isEmpty) return [];
    final q = _search.toLowerCase();
    final all = <String>{};
    for (final c in _cats) {
      for (final e in c.emojis) {
        if (e.contains(q) || c.title.contains(q)) all.add(e);
      }
    }
    return all.toList();
  }

  @override
  Widget build(BuildContext context) {
    final h = MediaQuery.of(context).size.height;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Container(
        height: widget.inline ? widget.inlineHeight : h * 0.72,
        decoration: const BoxDecoration(
          color: _bg,
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: Column(
          children: [
            if (!widget.inline) const SizedBox(height: 8),
            if (!widget.inline) Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            if (!widget.inline) const SizedBox(height: 8),
            if (!widget.inline) Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Container(
                height: 40,
                decoration: BoxDecoration(
                  color: _bar,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: TextField(
                  controller: _searchCtrl,
                  style: const TextStyle(color: Colors.white, fontSize: 15),
                  decoration: const InputDecoration(
                    hintText: 'العثور على ملصقات جديدة',
                    hintStyle: TextStyle(color: _hint, fontSize: 14),
                    prefixIcon: Icon(Icons.search, color: _hint, size: 22),
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(vertical: 10),
                  ),
                  onChanged: (v) => setState(() => _search = v.trim()),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Container(
              height: 40,
              margin: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: _bar,
                borderRadius: BorderRadius.circular(10),
              ),
              child: TabBar(
                controller: _mainTab,
                indicator: BoxDecoration(
                  color: const Color(0xFF2A3942),
                  borderRadius: BorderRadius.circular(8),
                ),
                indicatorSize: TabBarIndicatorSize.tab,
                labelColor: Colors.white,
                unselectedLabelColor: _hint,
                labelStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                tabs: const [
                  Tab(text: 'إيموجي'),
                  Tab(text: 'ملصقات'),
                ],
              ),
            ),
            const SizedBox(height: 4),
            Expanded(
              child: TabBarView(
                controller: _mainTab,
                children: [
                  _buildEmojiTab(),
                  _buildStickersTab(),
                ],
              ),
            ),
            if (_mainTab.index == 0 && _search.isEmpty) _buildEmojiCatBar(),
          ],
        ),
      ),
    );
  }

  Widget _buildEmojiTab() {
    if (_search.isNotEmpty) {
      final list = _filteredEmojis;
      return GridView.builder(
        padding: const EdgeInsets.all(10),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 8,
          mainAxisSpacing: 4,
          crossAxisSpacing: 4,
        ),
        itemCount: list.length,
        itemBuilder: (_, i) => _emojiCell(list[i]),
      );
    }

    return ListView.builder(
      controller: _emojiScroll,
      padding: const EdgeInsets.only(bottom: 8),
      itemCount: _cats.length,
      itemBuilder: (context, index) {
        final cat = _cats[index];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
              child: Text(
                cat.title,
                style: const TextStyle(
                  color: _hint,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 8),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 8,
                mainAxisSpacing: 2,
                crossAxisSpacing: 2,
              ),
              itemCount: cat.emojis.length,
              itemBuilder: (_, i) => _emojiCell(cat.emojis[i]),
            ),
          ],
        );
      },
    );
  }

  Widget _emojiCell(String e) {
    return GestureDetector(
      onTap: () => _pickEmoji(e),
      behavior: HitTestBehavior.opaque,
      child: Center(
        child: Text(e, style: const TextStyle(fontSize: 28)),
      ),
    );
  }

  Widget _buildEmojiCatBar() {
    return Container(
      height: 48,
      color: _bar,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        itemCount: _cats.length,
        itemBuilder: (context, i) {
          final selected = _emojiCatIndex == i;
          return GestureDetector(
            onTap: () {
              setState(() => _emojiCatIndex = i);
              final approx = i * 280.0;
              _emojiScroll.animateTo(
                approx.clamp(0, _emojiScroll.position.maxScrollExtent),
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOut,
              );
            },
            child: Container(
              width: 44,
              alignment: Alignment.center,
              child: Icon(
                _cats[i].icon,
                size: 22,
                color: selected ? _green : _hint,
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildStickersTab() {
    return ListView(
      padding: const EdgeInsets.only(bottom: 16),
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(14, 12, 14, 8),
          child: Text(
            'ملصقات ذات وظيفة',
            style: TextStyle(color: _hint, fontSize: 13, fontWeight: FontWeight.w500),
          ),
        ),
        SizedBox(
          height: 72,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: _funcStickers.length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (_, i) {
              final f = _funcStickers[i];
              return GestureDetector(
                onTap: () => _pickFunc(f),
                child: Container(
                  width: 64,
                  decoration: BoxDecoration(
                    color: _bar,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(f.emoji, style: const TextStyle(fontSize: 26)),
                      const SizedBox(height: 2),
                      Text(
                        f.label,
                        style: const TextStyle(color: _hint, fontSize: 10),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(14, 16, 14, 8),
          child: Text(
            'الأشكال',
            style: TextStyle(color: _hint, fontSize: 13, fontWeight: FontWeight.w500),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              _shapeBtn('💬', const Color(0xFF25D366)),
              const SizedBox(width: 10),
              _shapeBtn('💭', const Color(0xFF25D366)),
              const SizedBox(width: 10),
              _shapeBtn('⬜', const Color(0xFF25D366)),
              const SizedBox(width: 10),
              _shapeBtn('⭕', const Color(0xFF25D366)),
              const SizedBox(width: 10),
              _shapeBtn('↗️', const Color(0xFF25D366)),
            ],
          ),
        ),
        ..._packs.map((pack) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 18, 14, 8),
                child: Text(
                  pack.name,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 10),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 5,
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                ),
                itemCount: pack.stickers.length,
                itemBuilder: (_, i) {
                  final s = pack.stickers[i];
                  return GestureDetector(
                    onTap: () => _pickEmoji(s),
                    child: Container(
                      decoration: BoxDecoration(
                        color: _bar,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Center(
                        child: Text(s, style: const TextStyle(fontSize: 32)),
                      ),
                    ),
                  );
                },
              ),
            ],
          );
        }),

      ],
    );
  }

  Widget _shapeBtn(String emoji, Color color) {
    return GestureDetector(
      onTap: () => _pickEmoji(emoji),
      child: Container(
        width: 52,
        height: 52,
        decoration: BoxDecoration(
          color: _bar,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.5), width: 1.5),
        ),
        child: Center(
          child: Text(emoji, style: TextStyle(fontSize: 24, color: color)),
        ),
      ),
    );
  }
}

class _EmojiCat {
  final String key;
  final String title;
  final IconData icon;
  final List<String> emojis;
  const _EmojiCat({
    required this.key,
    required this.title,
    required this.icon,
    required this.emojis,
  });
}

class _StickerPack {
  final String name;
  final List<String> stickers;
  const _StickerPack({
    required this.name,
    required this.stickers,
  });
}

class _FuncSticker {
  final String label;
  final String emoji;
  final String type;
  const _FuncSticker({
    required this.label,
    required this.emoji,
    required this.type,
  });
}