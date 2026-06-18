import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:image_picker/image_picker.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:supabase_flutter/supabase_flutter.dart'; // 👈 Supabase 패키지 임포트

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
      home: const HomeScreen(),
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

  // 📡 [Supabase 연동 핵심]: 원격 데이터베이스로부터 시계열 일기 피드 전건 동적 로드 엔진
  Future<void> _fetchDiaryEntriesFromSupabase() async {
    try {
      final List<dynamic> response = await _supabase
          .from('diary_entries')
          .select()
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

          // JSON 타입의 수치를 Map<String, double> 구조로 파싱 변환
          Map<String, dynamic> rawEmotions = row['emotions'];
          Map<String, double> parsedEmotions = {};
          rawEmotions.forEach((k, v) => parsedEmotions[k] = (v as num).toDouble());

          _dailyTimelineFeeds[dateKey]!.add({
            "id": row['id'],
            "time": row['diary_time'],
            "text": row['text'],
            "emoji": row['emoji'],
            "emotions": parsedEmotions,
            "imageBytes": null, // 스토리지 주소 연동 전 프리셋용 공백값
            "imagePath": null
          });
        }

        // 전체 데이터 주머니 순회하며 일일 합산 평균 통계 재계산 가동
        _dailyTimelineFeeds.keys.forEach((dateKey) {
          _recalculateDailyDatabase(dateKey);
        });
      });
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

  // 🤖 1단계: AI 분석 연산 가동
  Future<void> _analyzeEmotionWithFastAPI() async {
    final text = _diaryController.text.trim();
    if (text.isEmpty && _selectedImage == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('일기를 작성하거나 사진을 추가해 주세요!')));
      return;
    }

    setState(() { _isLoading = true; });

    try {
      final url = Uri.parse('http://127.0.0.1:8000/analyze/');
      final request = http.MultipartRequest('POST', url);

      if (text.isNotEmpty) {
        request.fields['content'] = utf8.decode(utf8.encode(text));
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
          
          _dailyTimelineFeeds[targetKey]!.insert(0, {
            "id": feedId,
            "time": timeStr,
            "text": text.isNotEmpty ? text : "사진 AI 멀티모달 오리지널 분석 기록",
            "emoji": _emojiTable[highest]!,
            "imagePath": _selectedImage?.path,
            "imageBytes": imageBytes,
            "emotions": Map<String, double>.from(_editingSliders)
          });

          _editingFeedId = feedId; 
          _recalculateDailyDatabase(targetKey);
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

  // 💾 [Supabase 연동 핵심]: 새로고침 방어형 원격 동기화 동적 원스톱 저장소 레일
  void _saveManualAdjustment() async {
    String targetKey = _getDateKey(_selectedDay);
    if (_editingFeedId == null || !_dailyTimelineFeeds.containsKey(targetKey)) return;

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
      // 💡 Supabase의 강력한 'upsert' 연산 가동: 동일 ID 존재 시 수정(Update), 미존재 시 신규 추가(Insert)
      await _supabase.from('diary_entries').upsert({
        'id': targetFeed['id'],
        'diary_date': targetKey,
        'diary_time': targetFeed['time'],
        'text': targetFeed['text'],
        'emoji': targetFeed['emoji'],
        'emotions': targetFeed['emotions'], // JSONB 형태로 객체 데이터 자동 직렬화 적재
      });

      setState(() {
        _recalculateDailyDatabase(targetKey);
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

  void _recalculateDailyDatabase(String dateKey) {
    if (!_dailyTimelineFeeds.containsKey(dateKey) || _dailyTimelineFeeds[dateKey]!.isEmpty) {
      _dailyEmotionDatabase.remove(dateKey);
      _calendarEmojiMap.remove(dateKey);
      return;
    }

    Map<String, double> aggregatedEmotions = {"분노": 0.0, "불안": 0.0, "상처": 0.0, "기쁨": 0.0, "슬픔": 0.0, "놀람": 0.0, "일상": 0.0};
    
    for (var feed in _dailyTimelineFeeds[dateKey]!) {
      Map<String, double> feedEmotions = Map<String, double>.from(feed["emotions"]);
      feedEmotions.forEach((key, value) {
        aggregatedEmotions[key] = aggregatedEmotions[key]! + value;
      });
    }

    int totalFeeds = _dailyTimelineFeeds[dateKey]!.length;
    aggregatedEmotions.updateAll((key, value) => double.parse((value / totalFeeds).toStringAsFixed(1)));
    _dailyEmotionDatabase[dateKey] = aggregatedEmotions;

    String highest = "일상";
    double maxVal = -1.0;
    _dailyEmotionDatabase[dateKey]!.forEach((k, v) {
      if (v > maxVal) { maxVal = v; highest = k; }
    });
    _calendarEmojiMap[dateKey] = _emojiTable[highest]!;
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
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                    child: const Icon(Icons.access_time_rounded, color: Color(0xFFDCA842), size: 24),
                  )
                ],
              ),
            ),

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
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(titleLabel, style: const TextStyle(color: Color(0xFF78350F), fontSize: 13, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  Text(_dominantEmotion, style: const TextStyle(color: Color(0xFF451A03), fontSize: 36, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 4),
                  const Text('하루 모든 조절 데이터의 평균 결합값이 실시간 반영됩니다.', style: TextStyle(color: Color(0xFF92400E), fontSize: 11, fontWeight: FontWeight.w600)),
                ],
              ),
              Text(_dominantEmoji, style: const TextStyle(fontSize: 68)),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('종합 감정 점수 비율', style: TextStyle(color: Color(0xFF78350F), fontSize: 12, fontWeight: FontWeight.bold)),
              Text('${_dominantValue.toInt()}%', style: const TextStyle(color: Color(0xFF451A03), fontSize: 12, fontWeight: FontWeight.w900)),
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
                      Map<String, double> storedEmotions = Map<String, double>.from(record["emotions"]);
                      storedEmotions.forEach((k, v) {
                        _editingSliders[k] = v;
                        emotionMetrics[k]!['value'] = v;
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