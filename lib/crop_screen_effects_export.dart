/// Screen-category FFmpeg compositions. All graphics are procedural: no assets,
/// fonts or network inputs are added to Tini's project. Each recipe retains the
/// input dimensions and is blended using the existing effect start/end times.
class TiniScreenEffectsExport {
  static const category = 'شاشة';
  static const supported = <String>{
    'Seagull Digit...', 'Balloon Frame', 'Yellow And B...', 'Cute Polaroid',
    'Graphic 2', 'MV Cover', 'DV', 'Spring Border', 'DV II', 'Camera Grid',
    'Viewfinder II', 'Graphic III', 'Cinema', 'Camcorder II', 'Color Phosp...',
  };

  static List<String> filterGraph({
    required String input,
    required String output,
    required String name,
    required double startSeconds,
    required double endSeconds,
    required int width,
    required int height,
    required int index,
  }) {
    if (!supported.contains(name)) {
      throw UnsupportedError('Unsupported Screen effect: $name');
    }
    final w = width, h = height;
    int x(double v) => (w * v).round();
    int y(double v) => (h * v).round();
    String box(double left, double top, double bw, double bh, String color,
        {bool fill = true, int thickness = 2}) =>
        'drawbox=x=${x(left)}:y=${y(top)}:w=${x(bw).clamp(1, w).toInt()}:h=${y(bh).clamp(1, h).toInt()}:'
        'color=$color:t=${fill ? 'fill' : thickness}';
    String label(String value, double left, double top, int size, String color,
        {String? enable}) =>
        "drawtext=text='$value':x=${x(left)}:y=${y(top)}:fontsize=$size:"
        'fontcolor=$color:borderw=1:bordercolor=black@0.32'
        '${enable == null ? '' : ':enable=$enable'}';
    final corner = <String>[];
    void corners(String color, {double inset = .055, double length = .12,
        int thickness = 3}) {
      for (final xx in <double>[inset, 1 - inset - length]) {
        for (final yy in <double>[inset, 1 - inset - length]) {
          final sideX = xx < .5 ? xx : xx + length;
          final sideY = yy < .5 ? yy : yy + length;
          corner.add(box(xx, sideY, length, .002, color,
              fill: false, thickness: thickness));
          corner.add(box(sideX, yy, .002, length, color,
              fill: false, thickness: thickness));
        }
      }
    }
    final filters = <String>[];
    final phase = '(t-${startSeconds.toStringAsFixed(4)})';
    switch (name) {
      case 'Seagull Digit...':
        corners('white@0.83', inset: .075, length: .12, thickness: 2);
        filters.addAll([
          'eq=contrast=1.06:saturation=0.90', ...corner,
          label('RAW', .84, .06, x(.036).clamp(8, 22).toInt(), 'white'),
          label('01  02  03', .055, .91, x(.025).clamp(8, 17).toInt(), 'white@0.85'),
          box(.04,.95,.92,.003,'white@0.45'),
        ]);
        break;
      case 'Balloon Frame':
        // Cluster of rounded balloons around upper-left and lower-right corners.
        // Circular glyphs are combined with colourful highlight streaks.
        for (var i = 0; i < 15; i++) {
          final top = i < 8;
          final k = top ? i : i - 8;
          final px = top ? .015 + (k % 4) * .073 : .75 + (k % 4) * .062;
          final py = top ? -.02 + (k ~/ 4) * .115 : .69 + (k ~/ 4) * .125;
          final c = const <String>['0xF45072','0xFFCE49','0x44B8FA',
              '0x9167E8','0xFF9D3E','0x52D5BA','0xFE78CE'][i % 7];
          filters.add(label('●', px, py, x(.12).clamp(18, 82).toInt(), c));
          if (i % 3 == 0) filters.add(label('✦', px + .022, py + .032,
              x(.025).clamp(9, 24).toInt(), 'white@0.89'));
        }
        break;
      case 'Yellow And B...':
        filters.addAll([
          box(0,0,1,.022,'0xB5F5FF'),box(0,.976,1,.024,'0xFFF4A4'),
          box(0,0,.028,1,'0xFFF0B3'),box(.972,0,.028,1,'0xA7ECFA'),
          label('✦',.025,.016,x(.049).clamp(13,38).toInt(),'black'),
          label('✦',.88,.013,x(.045).clamp(13,38).toInt(),'black'),
          label('✦',.92,.85,x(.04).clamp(12,30).toInt(),'black'),
          box(.07,.94,.86,.006,'0xFFF7B4'),
        ]);
        break;
      case 'Cute Polaroid':
        // Centre snapshot over a pink postcard filled with small red motifs.
        final bg = 'sc_bg$index', pic = 'sc_pic$index';
        final backdrop = <String>[
          box(0,0,1,1,'0xF3BBC5'),
          for (var row = 0; row < 8; row++)
            for (var col = 0; col < 5; col++)
              label('♡', .035 + col * .195 + (row % 2) * .04,
                  .02 + row * .119, x(.024).clamp(9,19).toInt(),'0xC94E70@0.85'),
          box(.16,.295,.68,.39,'white'),
        ];
        return [
          '[$input]split=2[$bg][$pic]',
          '[$bg]${backdrop.join(',')},format=yuv420p[sc_wall$index]',
          '[$pic]scale=${x(.62) ~/ 2 * 2}:${y(.32) ~/ 2 * 2}[sc_shot$index]',
          '[sc_wall$index][sc_shot$index]overlay=x=(W-w)/2:'
              'y=${y(.31)}:shortest=1[sc_photo$index]',
          '[sc_photo$index]${label('I love you',.33,.65,
              x(.046).clamp(12,32).toInt(),'0xD65972')},format=yuv420p[$output]',
        ];
      case 'Graphic 2':
        filters.addAll([
          box(0,0,1,.018,'0xF4FFFF'),box(0,.955,1,.045,'0xF5F2D4'),
          box(0,0,.024,1,'0xE9FCFF'),box(.976,0,.024,1,'0xE9FCFF'),
          label('✦',.05,.035,x(.037).clamp(11,29).toInt(),'black'),
          label('✦',.88,.035,x(.035).clamp(11,29).toInt(),'black'),
          label('PLAY  ●  CLASSIC  FRAME',.09,.967,
              x(.020).clamp(8,14).toInt(),'0x777777'),
        ]);
        break;
      case 'MV Cover':
        // MV art has a secondary translucent mat around a centered viewport.
        final outer = 'sc_cover$index', inner = 'sc_in$index';
        return [
          '[$input]split=2[$outer][$inner]',
          '[$outer]gblur=sigma=17,eq=saturation=0.65:brightness=-0.08,'
              '${box(.10,.06,.80,.87,'0xFFF9FC@0.65')},format=yuv420p[sc_matte$index]',
          '[$inner]scale=${x(.73) ~/ 2 * 2}:${y(.79) ~/ 2 * 2}[sc_focus$index]',
          '[sc_matte$index][sc_focus$index]overlay=x=(W-w)/2:'
              'y=(H-h)/2:shortest=1[sc_album$index]',
          '[sc_album$index]${label('♡ 3762',.76,.025,
              x(.029).clamp(9,21).toInt(),'white')},format=yuv420p[$output]',
        ];
      case 'DV':
        corners('white@0.83', inset:.05,length:.095,thickness:2);
        filters.addAll([
          'eq=contrast=1.11:saturation=0.83',...corner,
          label('REC',.055,.047,x(.033).clamp(10,21).toInt(),'white'),
          label('HDV',.77,.045,x(.033).clamp(10,22).toInt(),'white'),
          label('00 00 02',.055,.095,x(.026).clamp(9,19).toInt(),'white'),
          box(.81,.94,.15,.006,'white@0.85'),
        ]);
        break;
      case 'Spring Border':
        // A field of flowers, yellow stars and stems along the lower edge.
        for (var i = 0; i < 16; i++) {
          final px = .012 + (i * 67 % 95) / 100;
          final top = .81 + ((i * 17) % 17) / 100;
          filters.add(box(px,top,.003,1-top,'0x3DB96C@0.85'));
          filters.add(label('✿',px-.022,top-.018,x(.05).clamp(14,38).toInt(),
              i.isEven ? '0xFFF16D' : '0xFD86A2'));
        }
        filters.addAll([
          box(0,.965,1,.035,'0x65B854@0.52'),
          label('✿',.04,.065,x(.035).clamp(11,28).toInt(),'0xFFEE79'),
        ]);
        break;
      case 'DV II':
        filters.addAll([
          'eq=contrast=1.08:saturation=0.94',
          label('CAM',.02,.025,x(.04).clamp(12,30).toInt(),'0x7DD975'),
          label('SP  ▶',.75,.025,x(.035).clamp(10,28).toInt(),'white'),
          label('00 06 20',.69,.085,x(.03).clamp(10,23).toInt(),'white'),
          label('FEB. 02. 1997',.02,.935,x(.031).clamp(10,24).toInt(),'white'),
          label('PM 08 26',.73,.935,x(.027).clamp(9,22).toInt(),'white'),
        ]);
        break;
      case 'Camera Grid':
        filters.addAll([
          box(.333,0,.002,1,'white@0.42'),
          box(.666,0,.002,1,'white@0.42'),
          box(0,.333,1,.001,'white@0.42'),
          box(0,.666,1,.001,'white@0.42'),
          box(.49,.495,.02,.002,'white@0.78'),
          box(.499,.48,.002,.04,'white@0.78'),
        ]);
        break;
      case 'Viewfinder II':
        corners('white@0.69',inset:.045,length:.095,thickness:2);
        filters.addAll([
          'eq=contrast=1.12:saturation=0.78:brightness=-0.105',
          'vignette=angle=PI/3.7',...corner,
          box(.34,.962,.32,.002,'white@0.80'),
          label('Ⅰ Ⅰ Ⅰ Ⅰ Ⅰ',.39,.94,x(.02).clamp(8,15).toInt(),'white'),
        ]);
        break;
      case 'Graphic III':
        filters.addAll([
          box(.015,.015,.97,.004,'white@0.68'),
          box(.015,.981,.97,.004,'white@0.68'),
          box(.015,.015,.005,.97,'white@0.68'),
          box(.98,.015,.005,.97,'white@0.68'),
          label('GRAPHIC',.05,.04,x(.027).clamp(9,17).toInt(),'white'),
          label('●',.88,.04,x(.026).clamp(8,18).toInt(),'0xF16D64'),
          box(.065,.92,.86,.003,'white@0.5'),
        ]);
        break;
      case 'Cinema':
        filters.addAll([
          'eq=contrast=1.12:saturation=0.87',
          box(0,0,1,.095,'black'),box(0,.90,1,.10,'black'),
          box(.07,.100,.86,.002,'white@0.44'),
          box(.07,.898,.86,.002,'white@0.44'),
        ]);
        break;
      case 'Camcorder II':
        filters.addAll([
          label('REC',.045,.055,x(.035).clamp(11,25).toInt(),'white'),
          label('●',.015,.055,x(.034).clamp(11,24).toInt(),'red'),
          label('16 9  HD',.78,.055,x(.027).clamp(10,21).toInt(),'white'),
          label('ISO',.04,.92,x(.028).clamp(9,19).toInt(),'white'),
          label('100  1/250',.04,.95,x(.02).clamp(8,15).toInt(),'white'),
          box(.19,.945,.45,.003,'white@0.75'),
          box(.22,.939,.002,.016,'white@0.83'),
          box(.40,.939,.002,.016,'white@0.83'),
        ]);
        break;
      case 'Color Phosp...':
        filters.addAll([
          box(.008,.006,.984,.006,'0xFE9B9E@0.89'),
          box(.01,.985,.98,.007,'0xB9BCFF@0.90'),
          box(.008,.006,.009,.98,'0xFC82AD@0.81'),
          box(.984,.01,.008,.98,'0x9ABFFF@0.84'),
          box(.033,.025,.93,.006,'0xFF6166@0.55'),
          box(.035,.963,.93,.006,'0x727DFF@0.65'),
          'eq=contrast=1.06:saturation=1.10',
        ]);
        break;
    }
    return ['[$input]${filters.join(',')},format=yuv420p[$output]'];
  }
}
