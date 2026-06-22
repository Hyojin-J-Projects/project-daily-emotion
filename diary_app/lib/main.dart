import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:image_picker/image_picker.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:supabase_flutter/supabase_flutter.dart'; 
import 'login_screen.dart';

// 🔒 [보안 가이드]: 본인의 Supabase 고유 주소와 Anon Public 토큰 키를 대입하세요!
String supabaseUrl = "";
String supabaseAnonKey = "";

void main() async {
  // 플러터 엔진 초기화
  WidgetsFlutterBinding.ensureInitialized();
  
  try {
    // 📂 1. .env 파일을 문자열로 로드
    final envString = await rootBundle.loadString('.env');
    
    // 🔍 2. 정규식을 이용해 공백/따옴표/줄바꿈을 싹 무시하고 KEY=VALUE 구조만 정확히 추출
    final regExp = RegExp(r'^\s*([A-Z_]+)\s*=\s*["️]?(.*?)["️]?\s*$', multiLine: true);
    final matches = regExp.allMatches(envString);
    
    for (final match in matches) {
      final key = match.group(1);
      final value = match.group(2);
      
      if (key == 'SUPABASE_URL') {
        supabaseUrl = value ?? "";
      } else if (key == 'SUPABASE_ANON_KEY') {
        supabaseAnonKey = value ?? "";
      }
    }
    print("✅ .env 로드 성공! URL 주소 확보 완료");
  } catch (e) {
    print("ℹ️ 로컬 .env 분석 실패 또는 없음 (배포 모드 가동): $e");
  }

  // 🛡️ 3. 만약 파일 파싱에서 실패했다면 Vercel 시스템 환경 변수(Dart Define)에서 소싱
  if (supabaseUrl.isEmpty || supabaseAnonKey.isEmpty) {
    supabaseUrl = const String.fromEnvironment('SUPABASE_URL');
    supabaseAnonKey = const String.fromEnvironment('SUPABASE_ANON_KEY');
  }

  // ⚡ 4. 최종 확인된 주소로 Supabase 가동
  await Supabase.initialize(
    url: supabaseUrl,
    publishableKey: supabaseAnonKey, // 👈 기존 'anonKey:'를 'publishableKey:'로 변경!
  );

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AI 감정 다이어리',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFFFFDF6),
      ),
      home: const LoginScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final TextEditingController _diaryController = TextEditingController();
  final ImagePicker _picker = ImagePicker();
  XFile? _selectedImage;
  bool _isLoading = false;

  String _currentTab = "오늘";

  CalendarFormat _calendarFormat = CalendarFormat.month;
  DateTime _focusedDay = DateTime.now();
  DateTime _selectedDay = DateTime.now();

  // 🗄️ Supabase 동기화형 로컬 상태 관리 주머니 레일
  final Map<String, List<Map<String, dynamic>>> _dailyTimelineFeeds = {};
  final Map<String, Map<String, double>> _dailyEmotionDatabase = {};
  final Map<String, String> _calendarEmojiMap = {};

  Future<void> _handleLogout() async {
    try {
      // Supabase 서버 세션 종료
      await Supabase.instance.client.auth.signOut();
      
      // 로그인 첫 화면으로 튕겨내기
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const LoginScreen()),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('로그아웃 실패: $e')),
      );
    }
  }
  Future<void> _fetchDiariesFromSupabase() async {
    // 현재 로그인한 유저 고유 ID 가져오기
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;

    setState(() => _isLoading = true);

    try {
      // 🌟 .eq('user_id', userId) 를 붙여서 '내 계정 일기만' 쏙 필터링합니다!
      final response = await Supabase.instance.client
          .from('diaries')
          .select()
          .eq('user_id', userId);

      if (response != null && response is List) {
        setState(() {
          // 주머니 초기화 후 데이터 채워넣기
          _dailyTimelineFeeds.clear();
          _dailyEmotionDatabase.clear();
          _calendarEmojiMap.clear();

          for (var item in response) {
            String dateStr = item['date'] ?? '';
            if (dateStr.isEmpty) continue;

            // 로컬 화면 주머니 데이터 구조에 맞게 매핑
            _dailyTimelineFeeds[dateStr] = [
              {
                'text': item['content'] ?? '',
                'emotion': item['emotion'] ?? '일상',
                'image': item['image_url'], // 이미지 경로가 있다면 추가
              }
            ];

          }
        });
      }
    } catch (e) {
      print('일기 불러오기 실패: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  // 🔄 1단계 AI 분석 직후 백엔드로 실시간 자동 전송 + 로컬 화면 새로고침 엔진
  Future<void> _recalculateDailyDatabase(String dateKey) async {
    final client = Supabase.instance.client;
    String? userId = client.auth.currentUser?.id ?? client.auth.currentSession?.user.id;

    if (userId == null) {
      print("⚠️ 세션이 만료되어 자동 디비 동기화가 차단되었습니다.");
      return; 
    }

    List<Map<String, dynamic>> feeds = _dailyTimelineFeeds[dateKey] ?? [];
    if (feeds.isEmpty) {
      setState(() {
        _dailyEmotionDatabase.remove(dateKey);
        _calendarEmojiMap.remove(dateKey);
      });
      return;
    }

    // 1. 피드들의 전체 평점 및 평균 계산 데이터 정렬
    double totalJoy = 0, totalSad = 0, totalAngry = 0, totalAnxious = 0, totalHurt = 0, totalSurprised = 0, totalNormal = 0;
    int count = feeds.length;

    for (var f in feeds) {
      Map<String, dynamic> em = f["emotions"] ?? {};
      totalJoy += (em["기쁨"] ?? 0.0);
      totalSad += (em["슬픔"] ?? 0.0);
      totalAngry += (em["분노"] ?? 0.0);
      totalAnxious += (em["불안"] ?? 0.0);
      totalHurt += (em["상처"] ?? 0.0);
      totalSurprised += (em["놀람"] ?? 0.0);
      totalNormal += (em["일상"] ?? 0.0);
    }

    Map<String, double> integratedEmotions = {
      "기쁨": double.parse((totalJoy / count).toStringAsFixed(1)),
      "슬픔": double.parse((totalSad / count).toStringAsFixed(1)),
      "분노": double.parse((totalAngry / count).toStringAsFixed(1)),
      "불안": double.parse((totalAnxious / count).toStringAsFixed(1)),
      "상처": double.parse((totalHurt / count).toStringAsFixed(1)),
      "놀람": double.parse((totalSurprised / count).toStringAsFixed(1)),
      "일상": double.parse((totalNormal / count).toStringAsFixed(1)),
    };

    String highestEmotion = "일상";
    double maxVal = -1.0;
    integratedEmotions.forEach((k, v) {
      if (v > maxVal) {
        maxVal = v;
        highestEmotion = k;
      }
    });

    final latestFeed = feeds.first;
    String idKey = latestFeed["id"] ?? DateTime.now().millisecondsSinceEpoch.toString();
    String timeKey = latestFeed["time"] ?? "${TimeOfDay.now().period == DayPeriod.am ? '오전' : '오후'} ${TimeOfDay.now().format(context).split(' ')[0]}";

    // 🌟 [추가] 계산된 평점 수치들을 그래프와 대시보드 변수들에 실시간 강제 새로고침(setState) 바인딩합니다.
    setState(() {
      _dailyEmotionDatabase[dateKey] = integratedEmotions;
      _calendarEmojiMap[dateKey] = _emojiTable[highestEmotion]!;
      
      Map<String, double> latestEmotions = Map<String, double>.from(latestFeed["emotions"] ?? {});
      latestEmotions.forEach((key, value) {
        if (_editingSliders.containsKey(key)) _editingSliders[key] = value;
        if (emotionMetrics.containsKey(key)) emotionMetrics[key]!['value'] = value;
      });
    });

    try {
      // 🚀 실제 디비 컬럼명 구조에 맞춰서 전송!
      await client.from('diary_entries').upsert({
        'id': idKey,
        'user_id': userId,       
        'text': latestFeed["text"] ?? "사진 AI 멀티모달 오리지널 분석 기록",
        'emoji': _emojiTable[highestEmotion]!,
        'diary_date': dateKey,
        'diary_time': timeKey,
        'emotions': integratedEmotions, 
      });
      
      print("🎯 [성공] AI 분석 결과가 user_id($userId)와 함께 자동 업서트 및 화면 갱신 완료되었습니다.");
    } catch (e) {
      print("❌ 자동 마이그레이션 실패 로그: $e");
    }
  }
  String _dominantEmotion = "일상";
  String _dominantEmoji = "😐";
  double _dominantValue = 100.0;

  final Map<String, double> _editingSliders = {
    "분노": 0.0, "불안": 0.0, "상처": 0.0, "기쁨": 0.0, "슬픔": 0.0, "놀람": 0.0, "일상": 100.0,
  };

  String? _editingFeedId;

  final Map<String, Map<String, dynamic>> emotionMetrics = {
    "분노": {"emoji": "😠", "value": 0.0, "color": const Color(0xFFFCA5A5)},
    "불안": {"emoji": "😟", "value": 0.0, "color": const Color(0xFF93C5FD)},
    "상처": {"emoji": "🤢", "value": 0.0, "color": const Color(0xFF86EFAC)},
    "기쁨": {"emoji": "😄", "value": 0.0, "color": const Color(0xFFFBBF24)},
    "슬픔": {"emoji": "😢", "value": 0.0, "color": const Color(0xFFFA5B4FC)},
    "놀람": {"emoji": "😲", "value": 0.0, "color": const Color(0xFFFCD34D)},
    "일상": {"emoji": "😐", "value": 100.0, "color": const Color(0xFFD1D5DB)},
  };

  final Map<String, String> _emojiTable = {
    "분노": "😠", "불안": "😟", "상처": "🤢", "기쁨": "😄", "슬픔": "😢", "놀람": "😲", "일상": "😐"
  };

  final List<String> _weekDays = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"];
  final List<String> _koreanWeekDays = ["일", "월", "화", "수", "목", "금", "토"];

  // 단일 Supabase 클라이언트 단말 참조 인스턴스 생성
  final SupabaseClient _supabase = Supabase.instance.client;

  @override
  void initState() {
    super.initState();
    // 📡 앱 부팅 시 오늘 자 날짜 데이터를 백엔드 데이터베이스로부터 원격 소싱(Fetch)해옵니다.
    _fetchDiaryEntriesFromSupabase();
  }

  String _getDateKey(DateTime date) {
    return "${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}";
  }

  String _getFormattedDate(DateTime date) {
    String weekdayStr = _koreanWeekDays[date.weekday % 7];
    return "${date.year}년 ${date.month}월 ${date.day}일 ${weekdayStr}요일";
  }

  // 📡 [Supabase 연동]: 원격 데이터베이스로부터 내 계정의 시계열 일기 피드만 동적 로드하는 엔진
  Future<void> _fetchDiaryEntriesFromSupabase() async {
    try {
      final client = Supabase.instance.client;
      String? userId = client.auth.currentUser?.id ?? client.auth.currentSession?.user.id;

      if (userId == null) {
        print("⚠️ 로그인 세션 정보가 없어 데이터를 불러오지 못했습니다.");
        return;
      }

      final List<dynamic> response = await client
          .from('diary_entries')
          .select()
          .eq('user_id', userId) 
          .order('created_at', ascending: false);

      setState(() {
        _dailyTimelineFeeds.clear();
        _dailyEmotionDatabase.clear();
        _calendarEmojiMap.clear();

        for (var row in response) {
          String dateKey = row['diary_date'];
          
          if (!_dailyTimelineFeeds.containsKey(dateKey)) {
            _dailyTimelineFeeds[dateKey] = [];
          }

          Map<String, dynamic> rawEmotions = row['emotions'] ?? {};
          Map<String, double> parsedEmotions = {};
          rawEmotions.forEach((k, v) => parsedEmotions[k] = (v as num).toDouble());

          // 🟢 변수 선언 위치를 확실하게 잡아 에러를 해결합니다.
          String? dbImagePath = row['image_url']; 

          _dailyTimelineFeeds[dateKey]!.add({
            "id": row['id'],
            "time": row['diary_time'],
            "text": row['text'],
            "emoji": row['emoji'],
            "emotions": parsedEmotions,
            "imageBytes": null, 
            "imagePath": dbImagePath // 🎯 에러 해결 및 정상 매핑
          });
        }

        _dailyTimelineFeeds.keys.forEach((dateKey) {
          _recalculateDailyDatabase(dateKey); 
        });
      });
      
      print("🎯 [동기화 성공] 클라우드에서 내 일기 피드 ${response.length}건을 정상 로드했습니다.");
    } catch (e) {
      print("⚠️ Supabase 데이터 초기 로드 실패: $e");
    }
  }


  int _calculateStreak(DateTime baseDate) {
    int streak = 0;
    DateTime checkDate = baseDate;
    while (true) {
      String key = _getDateKey(checkDate);
      if (_dailyEmotionDatabase.containsKey(key)) {
        streak++;
        checkDate = checkDate.subtract(const Duration(days: 1));
      } else {
        break;
      }
    }
    return streak;
  }

  double _calculateAverageEmotionScore() {
    if (_dailyEmotionDatabase.isEmpty) return 5.0;
    double totalScore = 0.0;
    int totalDays = _dailyEmotionDatabase.length;

    _dailyEmotionDatabase.forEach((dateKey, emotions) {
      double dayTotal = 0.0;
      emotions.forEach((key, val) => dayTotal += val);
      if (dayTotal == 0) dayTotal = 1.0;

      double anger = (emotions["분노"] ?? 0) / dayTotal;
      double anxiety = (emotions["불안"] ?? 0) / dayTotal;
      double injury = (emotions["상처"] ?? 0) / dayTotal;
      double joy = (emotions["기쁨"] ?? 0) / dayTotal;
      double sad = (emotions["슬픔"] ?? 0) / dayTotal;
      double surprise = (emotions["놀람"] ?? 0) / dayTotal;
      double neutral = (emotions["일상"] ?? 0) / dayTotal;

      double dayScore = (joy * 10.0) + (surprise * 8.5) + (neutral * 6.5) + (anxiety * 4.0) + (sad * 3.0) + (injury * 2.5) + (anger * 1.5);
      totalScore += dayScore;
    });
    return double.parse((totalScore / totalDays).toStringAsFixed(1));
  }

  Map<String, dynamic> _calculateTodayIntegratedEmotion() {
    String key = _getDateKey(_selectedDay);
    if (!_dailyEmotionDatabase.containsKey(key) || _dailyEmotionDatabase[key]!.isEmpty) {
      return {"emotion": "일상", "emoji": "😐", "value": 100.0};
    }

    String highestEmotion = "일상";
    double highestValue = -1.0;
    _dailyEmotionDatabase[key]!.forEach((k, v) {
      if (v > highestValue) {
        highestValue = v;
        highestEmotion = k;
      }
    });

    double total = 0.0;
    _dailyEmotionDatabase[key]!.forEach((k, v) => total += v);
    double ratio = total > 0 ? (highestValue / total) * 100 : 100.0;
    return {"emotion": highestEmotion, "emoji": _emojiTable[highestEmotion]!, "value": ratio > 100 ? 100.0 : ratio};
  }

  Map<String, dynamic> _getWeeklyDayTopEmotion(int weekdayIndex) {
    DateTime now = _selectedDay;
    DateTime monday = now.subtract(Duration(days: now.weekday - 1));
    DateTime targetDate = monday.add(Duration(days: weekdayIndex));
    String key = _getDateKey(targetDate);

    if (_dailyEmotionDatabase.containsKey(key)) {
      String topEmotion = "일상";
      double maxVal = -1.0;
      _dailyEmotionDatabase[key]!.forEach((k, v) {
        if (v > maxVal) {
          maxVal = v;
          topEmotion = k;
        }
      });
      double total = 0.0;
      _dailyEmotionDatabase[key]!.forEach((k, v) => total += v);
      double ratio = total > 0 ? (maxVal / total) * 100 : 0.0;
      return {"name": topEmotion, "emoji": _emojiTable[topEmotion]!, "value": ratio};
    }
    return {"name": "", "emoji": "", "value": 0.0};
  }

  double _getBioScore(DateTime date) {
    String key = _getDateKey(date);
    if (!_dailyEmotionDatabase.containsKey(key)) return 50.0;

    var data = _dailyEmotionDatabase[key]!;
    double good = (data["기쁨"] ?? 0) + (data["놀람"] ?? 0) * 0.8 + (data["일상"] ?? 0) * 0.5;
    double bad = (data["분노"] ?? 0) + (data["슬픔"] ?? 0) + (data["상처"] ?? 0) * 0.9 + (data["불안"] ?? 0) * 0.7;
    
    double total = good + bad;
    if (total == 0) return 50.0;
    return (good / total) * 100;
  }

  Future<void> _pickImage() async {
    final XFile? image = await _picker.pickImage(source: ImageSource.gallery);
    if (image != null) {
      setState(() {
        _selectedImage = image;
      });
    }
  }

  // 🤖 1단계: AI 분석 연산 가동 (기존 기능 100% 유지 + user_id 유실 방지)
  Future<void> _analyzeEmotionWithFastAPI() async {
    final text = _diaryController.text.trim();
    if (text.isEmpty && _selectedImage == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('일기를 작성하거나 사진을 추가해 주세요!')));
      return;
    }

    // 🌟 [추가] 안전하게 현재 로그인한 유저의 진짜 ID를 확보합니다.
    final client = Supabase.instance.client;
    String? userId = client.auth.currentUser?.id ?? client.auth.currentSession?.user.id;

    if (userId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('⚠️ 로그인 세션 정보가 없습니다. 다시 로그인 후 시도해 주세요!'), backgroundColor: Colors.red)
      );
      return;
    }

    setState(() { _isLoading = true; });

    try {
      // 🌟 로컬 주소를 지우고 16GB RAM 허깅페이스 서버 주소로 완벽 교체!
      final url = Uri.parse('https://erinjj-project-daily-emotion.hf.space/analyze/');
      final request = http.MultipartRequest('POST', url);

      if (text.isNotEmpty) {
        request.fields['content'] = text;
      }

      Uint8List? imageBytes;
      if (_selectedImage != null) {
        imageBytes = await _selectedImage!.readAsBytes();
        request.files.add(http.MultipartFile.fromBytes('image', imageBytes, filename: 'upload_image.jpg', contentType: MediaType('image', 'jpeg')));
      }

      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        final Map<String, dynamic> result = jsonDecode(utf8.decode(response.bodyBytes));

        String? serverSideImageUrl = result["image_url"];

        setState(() {
          String targetKey = _getDateKey(_selectedDay);
          
          _editingSliders.forEach((key, _) {
            if (result.containsKey(key)) {
              double val = (result[key] as num).toDouble();
              _editingSliders[key] = val;
              emotionMetrics[key]!['value'] = val;
            } else {
              _editingSliders[key] = 0.0;
              emotionMetrics[key]!['value'] = 0.0;
            }
          });
          
          String highest = "일상";
          double maxVal = -1.0;
          _editingSliders.forEach((k, v) {
            if (v > maxVal) { maxVal = v; highest = k; }
          });

          if (!_dailyTimelineFeeds.containsKey(targetKey)) {
            _dailyTimelineFeeds[targetKey] = [];
          }

          final String feedId = DateTime.now().millisecondsSinceEpoch.toString();
          final String timeStr = "${DateTime.now().hour >= 12 ? '오후' : '오전'} ${(DateTime.now().hour % 12 == 0 ? 12 : DateTime.now().hour % 12).toString().padLeft(2, '0')}:${DateTime.now().minute.toString().padLeft(2, '0')}";
          
          // 🌟 로컬 메모리 데이터 구조에도 user_id 주입
          _dailyTimelineFeeds[targetKey]!.insert(0, {
            "id": feedId,
            "user_id": userId, // 👈 [추가] 유저 식별 코드 장착!
            "time": timeStr,
            "text": text.isNotEmpty ? text : "사진 AI 멀티모달 오리지널 분석 기록",
            "emoji": _emojiTable[highest]!,
            "imagePath": serverSideImageUrl ?? _selectedImage?.path,
            "imageBytes": imageBytes,
            "emotions": Map<String, double>.from(_editingSliders)
          });

          _editingFeedId = feedId; 
          _recalculateDailyDatabase(targetKey); // 👈 여기서 디비로 밀어 넣을 때 유저 아이디를 타고 가게 합니다.
        });

        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('🤖 AI 분석 완료! 슬라이더 조절 후 하단 저장 버튼을 누르면 DB로 실시간 최종 마이그레이션됩니다.')));
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('FastAPI 서버 통신 실패!')));
    } finally {
      setState(() { _isLoading = false; });
    }
  }

  void _redistributeSliderValues(String changedKey, double newValue) {
    setState(() {
      newValue = double.parse(newValue.toStringAsFixed(1));
      if (newValue > 100.0) newValue = 100.0;
      if (newValue < 0.0) newValue = 0.0;
      
      _editingSliders[changedKey] = newValue;
      emotionMetrics[changedKey]!['value'] = newValue;

      double targetRemaining = 100.0 - newValue;

      double currentOthersTotal = 0.0;
      _editingSliders.forEach((key, value) {
        if (key != changedKey) {
          currentOthersTotal += value;
        }
      });

      List<String> otherKeys = _editingSliders.keys.where((k) => k != changedKey).toList();

      if (currentOthersTotal > 0.0) {
        double runningSum = 0.0;
        for (int i = 0; i < otherKeys.length; i++) {
          String key = otherKeys[i];
          if (i == otherKeys.length - 1) {
            double finalVal = double.parse((targetRemaining - runningSum).toStringAsFixed(1));
            _editingSliders[key] = finalVal < 0 ? 0.0 : finalVal;
          } else {
            double share = (targetRemaining * (_editingSliders[key]! / currentOthersTotal));
            double formattedShare = double.parse(share.toStringAsFixed(1));
            _editingSliders[key] = formattedShare;
            runningSum += formattedShare;
          }
          emotionMetrics[key]!['value'] = _editingSliders[key]!;
        }
      } else {
        double equalShare = double.parse((targetRemaining / otherKeys.length).toStringAsFixed(1));
        double runningSum = 0.0;

        for (int i = 0; i < otherKeys.length; i++) {
          String key = otherKeys[i];
          if (i == otherKeys.length - 1) {
            _editingSliders[key] = double.parse((targetRemaining - runningSum).toStringAsFixed(1));
          } else {
            _editingSliders[key] = equalShare;
            runningSum += equalShare;
          }
          emotionMetrics[key]!['value'] = _editingSliders[key]!;
        }
      }
    });
  }

 // 💾 [Supabase 연동 핵심]: 새로고침 방어형 원격 동기화 동적 원스톱 저장소 레일 (user_id 주입 마스터 버전)
  void _saveManualAdjustment() async {
    String targetKey = _getDateKey(_selectedDay);
    if (_editingFeedId == null || !_dailyTimelineFeeds.containsKey(targetKey)) return;

    // 🌟 [최종 방어선] 현재 로그인한 유저 세션에서 진짜 고유 ID(UUID)를 확실하게 추출합니다.
    final client = Supabase.instance.client;
    String? userId = client.auth.currentUser?.id ?? client.auth.currentSession?.user.id;

    if (userId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('⚠️ 로그인 세션 정보가 없습니다. 다시 로그인해 주세요!'), backgroundColor: Colors.red)
      );
      return;
    }

    int index = _dailyTimelineFeeds[targetKey]!.indexWhere((f) => f["id"] == _editingFeedId);
    if (index == -1) return;

    setState(() {
      String highest = "일상";
      double maxVal = -1.0;
      _editingSliders.forEach((k, v) {
        if (v > maxVal) { maxVal = v; highest = k; }
      });

      _dailyTimelineFeeds[targetKey]![index]["emoji"] = _emojiTable[highest]!;
      _dailyTimelineFeeds[targetKey]![index]["emotions"] = Map<String, double>.from(_editingSliders);
      if (_diaryController.text.trim().isNotEmpty) {
        _dailyTimelineFeeds[targetKey]![index]["text"] = _diaryController.text.trim();
      }
    });

    var targetFeed = _dailyTimelineFeeds[targetKey]![index];

    try {
      // 💡 Supabase의 강력한 'upsert' 연산 가동: user_id를 누락 없이 꽉 채워 던집니다!
      await _supabase.from('diary_entries').upsert({
        'id': targetFeed['id'],
        'user_id': userId,           // 🟢 [버그 완전 종결] 드디어 디비 빈칸에 진짜 내 UUID가 들어갑니다!
        'diary_date': targetKey,
        'diary_time': targetFeed['time'],
        'text': targetFeed['text'],
        'emoji': targetFeed['emoji'],
        'emotions': targetFeed['emotions'], // JSONB 형태로 객체 데이터 자동 직렬화 적재
      });

      setState(() {
        _recalculateDailyDatabase(targetKey); // 🌟 동기화 연산 가동
        _diaryController.clear();
        _selectedImage = null;
        _editingFeedId = null;
        _editingSliders.updateAll((key, value) => key == "일상" ? 100.0 : 0.0);
        emotionMetrics.forEach((key, value) {
          emotionMetrics[key]!['value'] = key == "일상" ? 100.0 : 0.0;
        });
      });

      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('💾 Supabase 클라우드 데이터 영구 동기화 완료! (새로고침 방어 완료)')));
    } catch (dbError) {
      print("❌ Supabase Upsert 실패 로그: $dbError");
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('⚠️ Supabase 클라우드 데이터 적재 실패!')));
    }
  }

 
  
  @override
  Widget build(BuildContext context) {
    var todayData = _calculateTodayIntegratedEmotion();
    _dominantEmotion = todayData["emotion"];
    _dominantEmoji = todayData["emoji"];
    _dominantValue = todayData["value"];

    String targetKey = _getDateKey(_selectedDay);
    List<Map<String, dynamic>> activeTimeline = _dailyTimelineFeeds[targetKey] ?? [];

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // 📝 상단 헤더 영역 (날짜, 타이틀, 로그아웃 버튼 정렬 완료)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_getFormattedDate(_selectedDay), style: const TextStyle(color: Color(0xFFDCA842), fontSize: 13, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      const Text('감정 일기', style: TextStyle(color: Color(0xFF3C2612), fontSize: 28, fontWeight: FontWeight.w900)),
                    ],
                  ),
                  // 🚪 기획하신 부드러운 그림자가 깔린 로그아웃 버튼
                  GestureDetector(
                    onTap: _handleLogout,
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.06),
                            blurRadius: 10,
                            spreadRadius: 2,
                            offset: const Offset(0, 2),
                          )
                        ],
                      ),
                      child: const Icon(
                        Icons.logout_rounded,
                        color: Color(0xFFDCA842),
                        size: 24,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            
            // 탭 버튼 영역
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
              child: Row(
                children: [
                  _buildTabButton("오늘"),
                  const SizedBox(width: 12),
                  _buildTabButton("이번 주"),
                  const SizedBox(width: 12),
                  _buildTabButton("캘린더로 보기"),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // 스크롤 가능한 메인 컨텐츠 영역
            Expanded(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                child: Column(
                  children: [
                    if (_currentTab == "오늘") ...[
                      _buildMainHeroCard("오늘 통합 감정 강도"),
                      _buildInputForm(),
                      _buildManualSliderPanel(),
                      _buildEmotionSpectrumChart("실시간 감정 스펙트럼"),
                      _buildTodayHistorySection(activeTimeline),
                    ] else if (_currentTab == "이번 주") ...[
                      _buildWeeklyMainCard(),
                      _buildWeeklyBarChart(),
                    ] else ...[
                      _buildCalendarPanel(),
                      _buildCalendarLineGraph(),
                    ],
                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTabButton(String tabName) {
    bool isSelected = _currentTab == tabName;
    return GestureDetector(
      onTap: () { 
        setState(() { _currentTab = tabName; }); 
        if (tabName == "캘린더로 보기" || tabName == "이번 주") {
          _fetchDiaryEntriesFromSupabase(); // 탭 스위칭 시 실시간 원격 DB 재동기화 동적 결합
        }
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        decoration: BoxDecoration(color: isSelected ? const Color(0xFFFBBF24) : Colors.white, borderRadius: BorderRadius.circular(20)),
        child: Text(tabName, style: TextStyle(color: isSelected ? const Color(0xFF451A03) : const Color(0xFF9CA3AF), fontWeight: FontWeight.w900, fontSize: 13)),
      ),
    );
  }

  Widget _buildMainHeroCard(String titleLabel) {
    String currentDayKey = _getDateKey(_selectedDay);
    int recordCount = _dailyTimelineFeeds.containsKey(currentDayKey) ? _dailyTimelineFeeds[currentDayKey]!.length : 0;
    int continuousDays = _calculateStreak(_selectedDay);
    double averageScore = _calculateAverageEmotionScore();

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [Color(0xFFFBBF24), Color(0xFFF59E0B)], begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(32),
      ),
      child: Column(
        children: [
          Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded( // 👈 1. 왼쪽 텍스트 영역이 차지할 수 있는 가로 폭을 제한합니다.
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(titleLabel, style: const TextStyle(color: Color(0xFF78350F), fontSize: 13, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  Text(_dominantEmotion, style: const TextStyle(color: Color(0xFF451A03), fontSize: 36, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 4),
                  // 💡 2. 긴 텍스트가 화면 밖으로 탈출하지 못하도록 maxLines와 overflow 속성을 추가합니다.
                  Text(
                    '하루 모든 조절 데이터의 평균 결합값이 실시간 반영됩니다.', 
                    style: const TextStyle(color: Color(0xFF92400E), fontSize: 11, fontWeight: FontWeight.w600),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12), // 👈 3. 텍스트와 이모티콘 사이의 최소 간격 확보
            Text(_dominantEmoji, style: const TextStyle(fontSize: 68)), // 🎯 이제 이모티콘이 제자리를 지킵니다!
          ],
        ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: LinearProgressIndicator(
              value: _dominantValue / 100,
              backgroundColor: const Color(0xFFFEF3C7).withOpacity(0.5),
              valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF451A03)),
              minHeight: 10,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildMiniStatusBadge(recordCount > 0 ? "$recordCount회 완료" : "미작성", "기록 여부"),
              _buildMiniStatusBadge("$continuousDays일", "연속 작성"),
              _buildMiniStatusBadge("$averageScore점", "평균 마음"),
            ],
          )
        ],
      ),
    );
  }

  Widget _buildMiniStatusBadge(String title, String subtitle) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 4),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(color: Colors.white.withOpacity(0.25), borderRadius: BorderRadius.circular(16)),
        child: Column(
          children: [
            Text(title, style: const TextStyle(color: Color(0xFF451A03), fontSize: 15, fontWeight: FontWeight.w900)),
            const SizedBox(height: 2),
            Text(subtitle, style: const TextStyle(color: Color(0xFF78350F), fontSize: 10, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }

  Widget _buildInputForm() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(28), border: Border.all(color: const Color(0xFFFEF3C7))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_editingFeedId == null ? '오늘의 마음 기록하기' : '💡 타임라인 피드 감정 수정 튜닝 모드 가동 중', style: TextStyle(color: _editingFeedId == null ? const Color(0xFF451A03) : Colors.blue[900], fontSize: 14, fontWeight: FontWeight.w900)),
          const SizedBox(height: 8),
          TextField(
            controller: _diaryController,
            maxLines: 2,
            style: const TextStyle(fontSize: 12, color: Color(0xFF78350F), fontWeight: FontWeight.w600),
            decoration: InputDecoration(
              hintText: '작성 후 분석을 요청하면 AI가 1차 수치를 슬라이더에 세팅해 줍니다...',
              hintStyle: TextStyle(color: const Color(0xFFB45309).withOpacity(0.4), fontSize: 11),
              filled: true,
              fillColor: const Color(0xFFFFFBEB).withOpacity(0.5),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
              contentPadding: const EdgeInsets.all(12),
            ),
          ),
          Row(
            children: [
              IconButton(onPressed: _pickImage, icon: const Icon(Icons.add_photo_alternate, color: Color(0xFFF59E0B), size: 28)),
              if (_selectedImage != null)
                Expanded(child: Text(' 연동됨: ${_selectedImage!.name}', style: const TextStyle(fontSize: 11, color: Colors.green, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis)),
              if (_editingFeedId != null)
                TextButton(onPressed: () { setState(() { _editingFeedId = null; _diaryController.clear(); }); }, child: const Text("수정 취소", style: TextStyle(color: Colors.red, fontSize: 12)))
            ],
          ),
          const SizedBox(height: 4),
          SizedBox(
            width: double.infinity,
            height: 44,
            child: ElevatedButton(
              onPressed: _isLoading ? null : _analyzeEmotionWithFastAPI,
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF3C2612), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
              child: _isLoading
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Text('1단계: AI 멀티모달 자동 분석 요청 🤖', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w900)),
            ),
          )
        ],
      ),
    );
  }

  Widget _buildManualSliderPanel() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(28), border: Border.all(color: const Color(0xFFFEF3C7))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('2단계: 실시간 감정 스펙트럼 수동 커스텀 조절', style: TextStyle(color: Color(0xFF451A03), fontSize: 14, fontWeight: FontWeight.w900)),
          const SizedBox(height: 4),
          const Text('바를 밀어 퍼센트를 조절하면 하단 실시간 그래프도 동시에 반응합니다.', style: TextStyle(color: Colors.black45, fontSize: 10, fontWeight: FontWeight.w600)),
          const SizedBox(height: 16),
          Column(
            children: _editingSliders.keys.map((emotionKey) {
              final metric = emotionMetrics[emotionKey]!;
              return Row(
                children: [
                  SizedBox(width: 45, child: Text('${metric["emoji"]} $emotionKey', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold))),
                  Expanded(
                    child: Slider(
                      value: _editingSliders[emotionKey]!,
                      min: 0.0,
                      max: 100.0,
                      activeColor: metric["color"],
                      inactiveColor: const Color(0xFFFFFBEB),
                      onChanged: (newValue) {
                        _redistributeSliderValues(emotionKey, newValue);
                      },
                    ),
                  ),
                  SizedBox(width: 35, child: Text('${_editingSliders[emotionKey]!.toInt()}%', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: Color(0xFFB45309)))),
                ],
              );
            }).toList(),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 44,
            child: ElevatedButton(
              onPressed: _editingFeedId == null ? null : _saveManualAdjustment, // 💡 피드가 선택(락온)된 상태에서만 안전하게 DB 업서트 유도
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFBBF24), elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
              child: Text(_editingFeedId == null ? '⚠️ 하단 피드를 먼저 선택하시면 클라우드 수정 저장이 활성화됩니다.' : '선택 피드 감정 수동 커스텀 클라우드 수정 완료 💾', style: const TextStyle(color: Color(0xFF451A03), fontSize: 12, fontWeight: FontWeight.w900)),
            ),
          )
        ],
      ),
    );
  }

  Widget _buildEmotionSpectrumChart(String title) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(28), border: Border.all(color: const Color(0xFFFEF3C7))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(color: Color(0xFF451A03), fontSize: 14, fontWeight: FontWeight.w900)),
          const SizedBox(height: 20),
          SizedBox(
            height: 120,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: emotionMetrics.entries.map((entry) {
                final emoji = entry.value['emoji'];
                final value = entry.value['value'] as double;
                final color = entry.value['color'] as Color;

                return Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text('${value.toInt()}%', style: const TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: Color(0xFFB45309))),
                    const SizedBox(height: 4),
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      width: 16,
                      height: (value == 0) ? 6 : (value * 0.75),
                      decoration: BoxDecoration(color: color, borderRadius: const BorderRadius.vertical(top: Radius.circular(6))),
                    ),
                    const SizedBox(height: 6),
                    Text(emoji, style: const TextStyle(fontSize: 14)),
                  ],
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTodayHistorySection(List<Map<String, dynamic>> timeline) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(padding: EdgeInsets.only(left: 4, bottom: 12, top: 8), child: Text('오늘의 기록 타임라인 피드 (클릭 시 감정 수정)', style: TextStyle(color: Color(0xFF451A03), fontSize: 14, fontWeight: FontWeight.w900))),
          if (timeline.isEmpty)
            Container(width: double.infinity, padding: const EdgeInsets.all(24), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24)), child: const Center(child: Text('기록된 피드가 비어있습니다. 📝', style: TextStyle(color: Colors.black38, fontSize: 11))))
          else
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: timeline.length,
              itemBuilder: (context, index) {
                final record = timeline[index];
                bool isSelectedFeed = _editingFeedId == record["id"];

                return InkWell(
                  onTap: () {
                    setState(() {
                      _editingFeedId = record["id"];
                      _diaryController.text = record["text"];
                      Map<String, double> storedEmotions = Map<String, double>.from(record["emotions"] ?? {});
                      storedEmotions.forEach((k, v) {
                        _editingSliders[k] = v;
                      });
                      storedEmotions.forEach((key, value) {
                        if (emotionMetrics.containsKey(key)) {
                          // 기존 Map의 내부 값을 바꾸는 대신, 새롭게 구성한 Map 객체를 통째로 덮어씌워 렌더링을 강제 트리거합니다.
                          emotionMetrics[key] = {
                            "emoji": emotionMetrics[key]!["emoji"],
                            "value": value,
                            "color": emotionMetrics[key]!["color"],
                          };
                        }
                      });
                    });
                  },
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: isSelectedFeed ? const Color(0xFFFEF3C7) : Colors.white, 
                      borderRadius: BorderRadius.circular(24),
                      border: isSelectedFeed ? Border.all(color: const Color(0xFFF59E0B), width: 1.5) : null
                    ),
                    child: Row(
                      children: [
                        Text(record["emoji"]!, style: const TextStyle(fontSize: 32)),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(record["time"]!, style: const TextStyle(color: Color(0xFFDCA842), fontSize: 10, fontWeight: FontWeight.bold)),
                              const SizedBox(height: 4),
                              Text(record["text"]!, style: const TextStyle(color: Color(0xFF451A03), fontSize: 12, fontWeight: FontWeight.w600)),
                            ],
                          ),
                        ),
                        if (record["imageBytes"] != null || record["imagePath"] != null) ...[
                          const SizedBox(width: 10),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: kIsWeb 
                              ? Image.memory(record["imageBytes"], width: 45, height: 45, fit: BoxFit.cover)
                              : Image.file(File(record["imagePath"]), width: 45, height: 45, fit: BoxFit.cover),
                          )
                        ]
                      ],
                    ),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _buildWeeklyBarChart() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(28), border: Border.all(color: const Color(0xFFFEF3C7))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('이번 주 주간 리포트 트랙', style: TextStyle(color: Color(0xFF451A03), fontSize: 15, fontWeight: FontWeight.w900)),
          const SizedBox(height: 4),
          const Text('※ 각 요일의 기둥은 당일 가장 강했던 대표 감정의 비중(%)입니다.', style: TextStyle(color: Color(0xFF92400E), fontSize: 11, fontWeight: FontWeight.w600), ),
          const SizedBox(height: 24),
          SizedBox(
            height: 160,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: List.generate(7, (index) {
                var topEmotionData = _getWeeklyDayTopEmotion(index);
                double weekValue = topEmotionData["value"];
                String emotionName = topEmotionData["name"];
                String emotionEmoji = topEmotionData["emoji"];

                return Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (emotionName.isNotEmpty) ...[
                      Text('$emotionEmoji $emotionName', style: const TextStyle(fontSize: 8, fontWeight: FontWeight.w900, color: Color(0xFF451A03))),
                      Text('${weekValue.toInt()}%', style: const TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: Color(0xFFB45309))),
                    ] else ...[
                      const Text('-', style: TextStyle(fontSize: 8, color: Colors.black26)),
                    ],
                    const SizedBox(height: 6),
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 500),
                      width: 26,
                      height: (weekValue == 0) ? 6 : (weekValue * 0.9),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(colors: [Color(0xFFFCD34D), Color(0xFFF59E0B)], begin: Alignment.topCenter, end: Alignment.bottomCenter),
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(_weekDays[index], style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF9CA3AF))),
                  ],
                );
              }),
            ),
          )
        ],
      ),
    );
  }

  Widget _buildWeeklyMainCard() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(color: const Color(0xFF3C2612), borderRadius: BorderRadius.circular(32)),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              Text('선택 주간 마음 트렌드', style: TextStyle(color: Color(0xFFDCA842), fontSize: 12, fontWeight: FontWeight.bold)),
              SizedBox(height: 6),
              Text('요일별 주간 리포트 대시보드 📈', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900)),
            ],
          ),
          const Text('📊', style: TextStyle(fontSize: 44)),
        ],
      ),
    );
  }

  Widget _buildCalendarPanel() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(28), border: Border.all(color: const Color(0xFFFEF3C7))),
      child: TableCalendar(
        firstDay: DateTime.utc(2026, 1, 1),
        lastDay: DateTime.utc(2026, 12, 31),
        focusedDay: _focusedDay,
        rowHeight: 54,
        calendarFormat: _calendarFormat,
        selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
        onDaySelected: (selectedDay, focusedDay) {
          setState(() {
            _selectedDay = selectedDay;
            _focusedDay = focusedDay;
          });
        },
        calendarBuilders: CalendarBuilders(
          markerBuilder: (context, date, events) {
            String dateKey = _getDateKey(date);
            if (_calendarEmojiMap.containsKey(dateKey)) {
              return Positioned(bottom: 4, child: Text(_calendarEmojiMap[dateKey]!, style: const TextStyle(fontSize: 15)));
            }
            return null;
          },
        ),
        calendarStyle: const CalendarStyle(
          todayDecoration: BoxDecoration(color: Color(0xFFFDE68A), shape: BoxShape.circle),
          selectedDecoration: BoxDecoration(color: Color(0xFFF59E0B), shape: BoxShape.circle),
          defaultTextStyle: TextStyle(color: Color(0xFF451A03), fontSize: 12, fontWeight: FontWeight.bold),
          weekendTextStyle: TextStyle(color: Color(0xFFAA6141), fontSize: 12),
        ),
        headerStyle: const HeaderStyle(formatButtonVisible: false, titleCentered: true, titleTextStyle: TextStyle(color: Color(0xFF451A03), fontSize: 14, fontWeight: FontWeight.w900)),
      ),
    );
  }

  Widget _buildCalendarLineGraph() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(28), border: Border.all(color: const Color(0xFFFEF3C7))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('마음 웰니스 바이오리듬 트랙', style: TextStyle(color: Color(0xFF451A03), fontSize: 14, fontWeight: FontWeight.w900)),
          const SizedBox(height: 4),
          const Text('높을수록 긍정 무드(😄,😲), 낮을수록 불안정 무드(😠,😢)를 뜻합니다.', style: TextStyle(color: Colors.black45, fontSize: 10, fontWeight: FontWeight.w600)),
          const SizedBox(height: 24),
          SizedBox(
            height: 120,
            width: double.infinity,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: List.generate(7, (idx) {
                DateTime targetDate = _selectedDay.subtract(Duration(days: 3 - idx));
                double bioScore = _getBioScore(targetDate);
                
                return Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Text('${bioScore.toInt()}', style: TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: bioScore >= 50 ? Colors.green : Colors.red)),
                      const SizedBox(height: 4),
                      Container(
                        width: 10,
                        height: bioScore * 0.7,
                        decoration: BoxDecoration(
                          color: bioScore >= 50 ? const Color(0xFFFBBF24) : const Color(0xFFA5B4FC),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text('${targetDate.day}일', style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.black38)),
                    ],
                  ),
                );
              }),
            ),
          )
        ],
      ),
    );
  }
}