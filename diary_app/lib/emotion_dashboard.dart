import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:fl_chart/fl_chart.dart';

class EmotionDashboardScreen extends StatefulWidget {
  const EmotionDashboardScreen({Key? key}) : super(key: key);

  @override
  _EmotionDashboardScreenState createState() => _EmotionDashboardScreenState();
}

class _EmotionDashboardScreenState extends State<EmotionDashboardScreen> {
  bool _isLoading = false;
  String _mainEmotion = "Other";
  String _emoji = "🍀";
  String _comment = "일기를 작성하면 AI가 감정을 분석해 드립니다.";
  double _confidence = 0.0;

  Map<String, double> _emotionDistribution = {
    "Anger": 0.0,
    "Anxiety": 0.0,
    "Disgust": 0.0,
    "Joy": 0.0,
    "Other": 100.0,
    "Sad": 0.0,
    "Surprise": 0.0,
  };

  // --- 🚀 [POST 연동 함수] 주소 끝에 슬래시(/) 고정 ---
  Future<void> sendDataToAI(String diaryText, File? imageFile) async {
    setState(() { _isLoading = true; });

    final url = Uri.parse("http://127.0.0.1:8000/analyze/"); 
    
    try {
      var request = http.MultipartRequest("POST", url);
      request.headers.addAll({
        "Accept": "application/json",
        "Content-Type": "multipart/form-data",
      });
      
      request.fields['content'] = diaryText;
      if (imageFile != null) {
        request.files.add(await http.MultipartFile.fromPath('image', imageFile.path));
      }

      print("🚀 [POST] AI 서버로 전송 중: $diaryText");
      
      var streamedResponse = await request.send();
      var response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        final Map<String, dynamic> responseData = json.decode(utf8.decode(response.bodyBytes));
        if (responseData["success"] == true) {
          final results = responseData["results"];
          final uiDisplay = results["ui_display"];
          
          setState(() {
            _mainEmotion = results["main_emotion"];
            _confidence = (results["confidence"] as num).toDouble();
            _emoji = uiDisplay["emoji"];
            _comment = uiDisplay["sys_comment"];
            
            final dist = results["emotion_distribution"];
            _emotionDistribution = {
              "Anger": (dist["Anger"] as num).toDouble(),
              "Anxiety": (dist["Anxiety"] as num).toDouble(),
              "Disgust": (dist["Disgust"] as num).toDouble(),
              "Joy": (dist["Joy"] as num).toDouble(),
              "Other": (dist["Other"] as num).toDouble(),
              "Sad": (dist["Sad"] as num).toDouble(),
              "Surprise": (dist["Surprise"] as num).toDouble(),
            };
          });
          print("🎯 [연동 대성공] UI 갱신 완료!");
        }
      } else {
        print("❌ 서버 에러: ${response.body}");
      }
    } catch (e) {
      print("❌ 네트워크 통신 실패: $e");
    } finally {
      setState(() { _isLoading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFDF7E7),
      appBar: AppBar(
        title: const Text("AI 감정 다이어리 대시보드", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFF3B334))))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 감정 요약 카드 카드 (Figma 디자인 매핑)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF3B334),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Column(
                      children: [
                        Text(_emoji, style: const TextStyle(fontSize: 50)),
                        const SizedBox(height: 10),
                        Text(
                          "주요 감정: $_mainEmotion (${(_confidence * 100).toStringAsFixed(1)}%)",
                          style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          _comment,
                          textAlign: CenterText.textAlign,
                          style: const TextStyle(color: Colors.white70, fontSize: 14),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 30),
                  const Text("📊 감정 스펙트럼 분석", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 20),
                  // 막대그래프 영역
                  SizedBox(
                    height: 200,
                    child: BarChart(
                      BarChartData(
                        alignment: BarChartAlignment.spaceAround,
                        maxY: 100,
                        barTouchData: BarTouchData(enabled: false),
                        titlesData: FlTitlesData(
                          show: true,
                          bottomTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              getTitlesWidget: (double value, TitleMeta meta) {
                                const style = TextStyle(color: Colors.black54, fontWeight: FontWeight.bold, fontSize: 12);
                                switch (value.toInt()) {
                                  case 0: return const Text('기쁨', style: style);
                                  case 1: return const Text('당황', style: style);
                                  case 2: return const Text('불안', style: style);
                                  case 3: return const Text('분노', style: style);
                                  case 4: return const Text('슬픔', style: style);
                                  case 5: return const Text('상처', style: style);
                                  case 6: return const Text('평온', style: style);
                                  default: return const Text('');
                                }
                              },
                            ),
                          ),
                          leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                        ),
                        borderData: FlBorderData(show: false),
                        barGroups: [
                          makeGroupData(0, _emotionDistribution["Joy"]!, const Color(0xFFFFD700)),
                          makeGroupData(1, _emotionDistribution["Surprise"]!, const Color(0xFFFFA500)),
                          makeGroupData(2, _emotionDistribution["Anxiety"]!, const Color(0xFF9370DB)),
                          makeGroupData(3, _emotionDistribution["Anger"]!, const Color(0xFFFF4500)),
                          makeGroupData(4, _emotionDistribution["Sad"]!, const Color(0xFF1E90FF)),
                          makeGroupData(5, _emotionDistribution["Disgust"]!, const Color(0xFF8B4513)),
                          makeGroupData(6, _emotionDistribution["Other"]!, const Color(0xFF3CB371)),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 40),
                  // 테스트 발사 버튼
                  Center(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFF3B334),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      icon: const Icon(Icons.edit_note),
                      label: const Text("진짜 일기 작성해서 AI 분석 테스트"),
                      onPressed: () {
                        final TextEditingController _textController = TextEditingController();
                        showDialog(
                          context: context,
                          builder: (context) => AlertDialog(
                            title: const Text("오늘의 일기 작성"),
                            content: TextField(
                              controller: _textController,
                              maxLines: 3,
                              decoration: const InputDecoration(
                                hintText: "오늘 하루는 어땠나요? 감정을 담아 적어보세요.",
                                border: OutlineInputBorder(),
                              ),
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context),
                                child: const Text("취소", style: TextStyle(color: Colors.grey)),
                              ),
                              ElevatedButton(
                                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFF3B334)),
                                onPressed: () {
                                  final inputText = _textController.text;
                                  Navigator.pop(context);
                                  if (inputText.isNotEmpty) {
                                    sendDataToAI(inputText, null); 
                                  }
                                },
                                child: const Text("AI 분석 요청", style: TextStyle(color: Colors.white)),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  BarChartGroupData makeGroupData(int x, double y, Color color) {
    return BarChartGroupData(
      x: x,
      barRods: [
        BarChartRodData(
          toY: y,
          color: color,
          width: 18,
          borderRadius: const BorderRadius.only(topLeft: Radius.circular(4), topRight: Radius.circular(4)),
        ),
      ],
    );
  }
}

// 텍스트 정렬을 위한 가상 클래스 방어선
class CenterText {
  static const textAlign = TextAlign.center;
}