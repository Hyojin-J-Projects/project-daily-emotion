import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'main.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  // 현재 어떤 단계를 보여줄지 결정하는 변수
  // -1: 시작화면, 0: 약관동의, 1: 계정생성, 2: 감정설정, 3: 로그인화면
  int _currentStep = -1; 
  bool _isLoading = false;

  // 🌟 이메일 중복 확인 상태 관리 변수
  bool _isEmailChecked = false; 
  String _checkedEmail = "";

  // 입력 컨트롤러
  final _nicknameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  // 약관 동의 상태
  bool _allAgreed = false;
  final List<bool> _agreements = [false, false, false];

  // 선택된 감정들
  final Set<String> _selectedEmotions = {};
  final List<Map<String, String>> _emotions = [
    {"name": "기쁨", "emoji": "😄"}, {"name": "슬픔", "emoji": "😢"},
    {"name": "분노", "emoji": "😠"}, {"name": "불안", "emoji": "😟"},
    {"name": "상처", "emoji": "🤢"}, {"name": "놀람", "emoji": "😲"},
    {"name": "일상", "emoji": "😐"},
  ];

  final SupabaseClient _supabase = Supabase.instance.client;

  // 🔍 [최종 종결] 임시 계정을 만들지 않고 에러 코드로 중복을 감별하는 함수
  Future<void> _checkEmailDuplicate() async {
    final email = _emailController.text.trim();
    if (email.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('이메일을 입력해 주세요!🌻')));
      return;
    }

    if (!email.contains('@') || !email.contains('.')) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('올바른 이메일 형식이 아닙니다.')));
      return;
    }

    setState(() => _isLoading = true);

    try {
      // 🌟 [핵심] 가입(signUp)을 시도하지 않고, '가짜 비밀번호'로 로그인을 시도해 봅니다!
      await _supabase.auth.signInWithPassword(
        email: email,
        password: 'ThisIsADummyPasswordForDuplicateCheck123!@#', 
      );
      
      // 혹시라도 로그인이 성공해 버리면 당연히 이미 존재하는 계정입니다.
      setState(() {
        _isEmailChecked = false;
        _checkedEmail = "";
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('❌ 이미 가입된 이메일입니다. 다른 이메일을 사용해 주세요.'))
      );

    } catch (e) {
      String errStr = e.toString();
      
      // 💡 Supabase의 최신 보안 정책 필터링
      // 계정이 존재하지 않으면 'User not found' 또는 'Invalid login credentials' 에러가 납니다.
      // 하지만 우리는 앞서 '이중 필터링 시스템'을 이미 다 구축해 두었기 때문에,
      // 가입 요청을 날려보아 중복 에러가 나는지 확인하는 것이 가장 안전합니다.
      
      // 단, 이메일이 진짜 없는 이메일인지 구별하기 위해 아래와 같이 안전하게 체크합니다.
      if (errStr.contains('User not found') || errStr.contains('invalid_credentials')) {
        setState(() {
          _isEmailChecked = true;
          _checkedEmail = email;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('🟢 사용 가능한 이메일입니다!'))
        );
      } else {
        // 비밀번호가 틀렸다는 에러 등이 나면 이미 계정이 존재한다는 강력한 증거입니다.
        setState(() {
          _isEmailChecked = false;
          _checkedEmail = "";
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('❌ 이미 가입된 이메일입니다. 다른 이메일을 사용해 주세요.'))
        );
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

 // ✉️ 실제 회원가입 실행 (효진님의 기존 유효성 검사 및 닉네임 저장 100% 완벽 유지!)
  Future<void> _handleSignUp() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();
    final confirmPassword = _confirmPasswordController.text.trim();
    final nickname = _nicknameController.text.trim();

    // 1. 빈칸 검사
    if (nickname.isEmpty || email.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('모든 정보를 입력해 주세요!🌻')),
      );
      return;
    }

    // 🌟 [추가된 유일한 방어선] 중복 확인 도중 이메일을 슬쩍 바꾸고 가입하려는 꼼수 방지!
    if (!_isEmailChecked || email != _checkedEmail) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('이메일 중복 확인을 먼저 완료해 주세요! 🔍')),
      );
      return;
    }

    // 2. 비밀번호 일치 확인
    if (password != confirmPassword) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('비밀번호가 서로 일치하지 않습니다. 다시 확인해 주세요!')),
      );
      return;
    }

    // 3. 🔐 비밀번호 정규식 유효성 검사 (7자 이상, 영문, 숫자, 특수문자 각각 최소 1자 포함)
    final passwordRegex = RegExp(r'^(?=.*[A-Za-z])(?=.*\d)(?=.*[@$!%*#?&])[A-Za-z\d@$!%*#?&]{7,}$');
    if (!passwordRegex.hasMatch(password)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('비밀번호는 영문, 숫자, 특수문자를 각각 포함하여 7자 이상이어야 합니다! 🔒'),
          duration: Duration(seconds: 3),
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      await _supabase.auth.signOut();
      // 4. Supabase 회원가입 요청
      final response = await _supabase.auth.signUp(
        email: email,
        password: password,
        data: {
          'nickname': nickname,
          'preferred_emotions': _selectedEmotions.toList(), // 선택한 주 감정 배열도 메타데이터에 함께 저장
        },
      );

      // 5. 🛑 이메일 중복 가입 방지 이중 필터링
      if (response.user != null && response.user!.identities != null && response.user!.identities!.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('이미 가입된 이메일 주소입니다. 로그인을 이용해 주세요!')),
        );
        setState(() => _isLoading = false);
        return;
      }

      await _supabase.auth.signOut();

      // 입력 폼 초기화 (보안 방어)
      _nicknameController.clear();
      _emailController.clear();
      _passwordController.clear();
      _confirmPasswordController.clear();
      _selectedEmotions.clear();

      // 다이얼로그나 스낵바로 사용자에게 메일함 확인 가이드 제공
      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: false, // 외부 클릭으로 닫기 방지
          builder: (context) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: const Text('✉️ 인증 메일 발송 완료', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF3C2612))),
            content: Text('$email 주소로 가입 확인 메일이 전송되었습니다.\n\n메일 안의 링크를 클릭해 주셔야 로그인이 가능합니다! 🌻'),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(context); // 팝업 닫기
                  setState(() {
                    _currentStep = 3; // 🎯 곧바로 로그인 화면으로 안전하게 튕겨내기!
                  });
                },
                child: const Text('확인', style: TextStyle(color: Color(0xFFDCA842), fontWeight: FontWeight.bold)),
              )
            ],
          ),
        );
      }
    } catch (e) {
      String errorMessage = '가입 실패: $e';
      if (e.toString().contains('already exists')) {
        errorMessage = '이미 가입된 이메일 주소입니다!';
      }
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(errorMessage)));
    } finally {
      setState(() => _isLoading = false);
    }
  }

  // 🔑 실제 로그인 실행 (기존 코드 완벽 유지)
  Future<void> _handleSignIn() async {
    if (_emailController.text.trim().isEmpty || _passwordController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('이메일과 비밀번호를 입력해 주세요!')));
      return;
    }
    setState(() => _isLoading = true);
    try {
      final authResponse = await _supabase.auth.signInWithPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );
      // 🎯 [여기서부터 5줄 추가!] 이메일 인증 완료 날짜가 찍혀있는지 확인합니다.
      final isEmailConfirmed = authResponse.user?.emailConfirmedAt != null;
      if (!isEmailConfirmed) {
        // 인증을 안 한 유저라면 로그인 세션을 즉시 파기(강제 로그아웃)하고 입장을 막습니다.
        await _supabase.auth.signOut();
        throw '이메일 인증이 완료되지 않았습니다. 메일함을 확인해 주세요!';
      }

      // 2. 인증이 통과된 정상 유저만 홈 화면으로 들여보냅니다.
      _navigateToHome();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('로그인 실패: $e')));
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _navigateToHome() {
    Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => HomeScreen()));
  }

  // --- UI 구성 요소들 ---

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFFFDF6),
      appBar: _currentStep == -1 ? null : AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Color(0xFFDCA842)),
          onPressed: () {
             setState(() {
              if (_currentStep == 3) {
                // 🎯 로그인 화면(3)에서 뒤로 가기를 누르면 감정 설정으로 안 가고 '시작 화면(-1)'으로 다이렉트 복귀!
                _currentStep = -1; 
               } else {
                  // 나머지 회원가입 단계(0, 1, 2)에서는 정상적으로 이전 단계로 이동
                _currentStep--;
              }   
            });
         },
      ),
        title: const Text('뒤로', style: TextStyle(color: Color(0xFFDCA842), fontSize: 16)),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 30),
          child: _buildBodyByStep(),
        ),
      ),
    );
  }

  Widget _buildBodyByStep() {
    if (_currentStep == -1) return _buildWelcomeStep();
    if (_currentStep == 0) return _buildTermsStep();
    if (_currentStep == 1) return _buildAccountStep();
    if (_currentStep == 2) return _buildEmotionStep();
    if (_currentStep == 3) return _buildLoginStep();
    return const SizedBox();
  }

  // 0. 시작 화면
  Widget _buildWelcomeStep() {
    return Column(
      children: [
        const SizedBox(height: 60),
        Center(
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(color: const Color(0xFFFBBF24), borderRadius: BorderRadius.circular(30)),
            child: const Icon(Icons.favorite, color: Colors.white, size: 60),
          ),
        ),
        const SizedBox(height: 20),
        const Text('무드록', style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Color(0xFF3C2612))),
        const Text('MOODLOG', style: TextStyle(fontSize: 14, color: Color(0xFFDCA842), fontWeight: FontWeight.bold)),
        const SizedBox(height: 50),
        const Text('오늘 당신의 감정은\n어떤가요?', textAlign: TextAlign.center, style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFFDCA842))),
        const SizedBox(height: 15),
        const Text('AI가 당신의 감정을 분석하고\n매일의 마음 기록을 도와드려요', textAlign: TextAlign.center, style: TextStyle(color: Color(0xFFB45309), fontSize: 14)),
        const SizedBox(height: 60),
        _buildLongButton('시작하기', const Color(0xFFFBBF24), Colors.white, () => setState(() => _currentStep = 0)),
        const SizedBox(height: 16),
        _buildLongButton(
          '로그인', 
          const Color(0xFFDCA842), 
          Colors.white, 
          () => setState(() => _currentStep = 3)
        ),
      ],
    );
  }

  // 1. 약관 동의
  Widget _buildTermsStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildStepIndicator(0),
        const SizedBox(height: 30),
        const Text('시작하기 전에 🌻', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
        const Text('이용약관에 동의해 주세요', style: TextStyle(fontSize: 16, color: Colors.grey)),
        const SizedBox(height: 40),
        _buildTermsBox(),
        const SizedBox(height: 100),
        _buildLongButton('다음으로', const Color(0xFFFBBF24), Colors.white, _allAgreed ? () => setState(() => _currentStep = 1) : null),
      ],
    );
  }

  // 2. 계정 생성 패널 (비밀번호 철벽 검증 및 화면 전환 잠금 버전)
  Widget _buildAccountStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildStepIndicator(1),
        const SizedBox(height: 30),
        const Text('계정 만들기 ✨', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
        const Text('나만의 감정 일기를 시작해요', style: TextStyle(fontSize: 16, color: Colors.grey)),
        const SizedBox(height: 30),
        
        _buildTextField('닉네임', '감자', _nicknameController, Icons.person),
        
        // 이메일 입력 영역
        const Text('이메일', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF3C2612))),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _emailController,
                onChanged: (value) {
                  if (value != _checkedEmail) {
                    setState(() {
                      _isEmailChecked = false;
                    });
                  }
                },
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.email, color: Color(0xFFDCA842)),
                  hintText: 'hello@moodlog.kr',
                  filled: true, fillColor: const Color(0xFFFDF5E6),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
                ),
              ),
            ),
            const SizedBox(width: 10),
            ElevatedButton(
              onPressed: _checkEmailDuplicate,
              style: ElevatedButton.styleFrom(
                backgroundColor: _isEmailChecked ? Colors.green : const Color(0xFFDCA842),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                elevation: 0,
              ),
              child: Text(_isEmailChecked ? '완료 ✓' : '중복 확인', style: const TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
        const SizedBox(height: 15),
        
        _buildTextField('비밀번호', '영문, 숫자, 특수문자 포함 7자 이상', _passwordController, Icons.lock, isObscure: true),
        _buildTextField('비밀번호 확인', '한 번 더 입력', _confirmPasswordController, Icons.lock, isObscure: true),
        const SizedBox(height: 40),
        
        // 🌟 [중요 수정] 다음으로 버튼을 누를 때 꼼꼼하게 먼저 검사합니다!
        _buildLongButton(
          '다음으로', 
          const Color(0xFFFBBF24), 
          Colors.white, 
          () {
            final password = _passwordController.text.trim();
            final confirmPassword = _confirmPasswordController.text.trim();
            final nickname = _nicknameController.text.trim();

            // 1. 이메일 중복 확인 패스 확인
            if (!_isEmailChecked) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('이메일 중복 확인을 먼저 완료해 주세요! 🔍')),
              );
              return;
            }

            // 2. 닉네임 빈칸 검사
            if (nickname.isEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('닉네임을 입력해 주세요!🌻')),
              );
              return;
            }

            // 3. 비밀번호 일치 확인 (다르게 쓰면 여기서 딱 걸립니다!)
            if (password != confirmPassword) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('비밀번호가 서로 일치하지 않습니다. 다시 확인해 주세요! ❌')),
              );
              return;
            }

            // 4. 비밀번호 정규식 유효성 검사 (7자 이상 조합 규칙)
            final passwordRegex = RegExp(r'^(?=.*[A-Za-z])(?=.*\d)(?=.*[@$!%*#?&])[A-Za-z\d@$!%*#?&]{7,}$');
            if (!passwordRegex.hasMatch(password)) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('비밀번호는 영문, 숫자, 특수문자를 각각 포함하여 7자 이상이어야 합니다! 🔒'),
                  duration: Duration(seconds: 3),
                ),
              );
              return;
            }

            // 🟢 모든 철벽 검사를 통과해야만 '감정 설정(스텝 2)' 화면으로 넘어갑니다!
            setState(() => _currentStep = 2);
          }
        ),
      ],
    );
  }

  // 3. 감정 설정
  Widget _buildEmotionStep() {
    return Column(
      children: [
        _buildStepIndicator(2),
        const SizedBox(height: 30),
        const Text('어떤 감정을\n주로 느끼세요? 🌈', textAlign: TextAlign.center, style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
        const SizedBox(height: 10),
        const Text('관심 있는 감정을 모두 선택해요', style: TextStyle(color: Colors.grey)),
        const SizedBox(height: 30),
        Wrap(
          spacing: 15, runSpacing: 15,
          children: _emotions.map((e) => _buildEmotionTag(e['name']!, e['emoji']!)).toList(),
        ),
        const SizedBox(height: 40),
        Text('${_selectedEmotions.length}개 선택됨', style: const TextStyle(color: Color(0xFFDCA842))),
        const SizedBox(height: 30),
        _buildLongButton('시작하기 🪄', const Color(0xFFFBBF24), Colors.white, _handleSignUp),
      ],
    );
  }

  // 4. 로그인 화면
  Widget _buildLoginStep() {
    return Column(
      children: [
        const SizedBox(height: 40),
        const Text('다시 만나서\n반가워요 👋', textAlign: TextAlign.center, style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
        const SizedBox(height: 40),
        _buildTextField('이메일', 'hello@moodlog.kr', _emailController, Icons.email_outlined),
        _buildTextField('비밀번호', '비밀번호 입력', _passwordController, Icons.lock_outline, isObscure: true),
        const SizedBox(height: 30),
        _buildLongButton('로그인', const Color(0xFFFBBF24), Colors.white, _handleSignIn),
        const SizedBox(height: 20),
        const Text('또는', style: TextStyle(color: Colors.grey)),
        const SizedBox(height: 20),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _buildSocialIcon('N', Colors.green), const SizedBox(width: 20),
            _buildSocialIcon('K', Colors.yellow), const SizedBox(width: 20),
            _buildSocialIcon('G', Colors.white),
          ],
        ),
        const SizedBox(height: 40),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('아직 계정이 없으신가요? '),
            GestureDetector(
              onTap: () {
                setState(() {
                  // 🎯 로그인 창에 입력했던 것들이 회원가입 창에 간섭하지 않도록 컨트롤러 청소!
                  _emailController.clear();
                  _passwordController.clear();
                  _currentStep = 0; // 약관 동의 단계로 이동
               });
             },
             child: const Text('회원가입', style: TextStyle(color: Color(0xFFDCA842), fontWeight: FontWeight.bold))
            ),
          ],
        )
      ],
    );
  }

  // --- 공통 컴포넌트 함수들 ---

  Widget _buildStepIndicator(int activeStep) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: ['약관 동의', '계정 생성', '감정 설정'].asMap().entries.map((e) {
        bool isActive = e.key == activeStep;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Column(
            children: [
              Text(e.value, style: TextStyle(fontSize: 12, color: isActive ? const Color(0xFFDCA842) : Colors.grey, fontWeight: isActive ? FontWeight.bold : FontWeight.normal)),
              const SizedBox(height: 4),
              Container(height: 2, width: 60, color: isActive ? const Color(0xFFDCA842) : Colors.grey[300]),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildTextField(String label, String hint, TextEditingController controller, IconData icon, {bool isObscure = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 15),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF3C2612))),
          const SizedBox(height: 8),
          TextField(
            controller: controller,
            obscureText: isObscure,
            decoration: InputDecoration(
              prefixIcon: Icon(icon, color: const Color(0xFFDCA842)),
              hintText: hint,
              filled: true, fillColor: const Color(0xFFFDF5E6),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLongButton(String text, Color bg, Color fg, VoidCallback? onPressed) {
    return SizedBox(
      width: double.infinity, height: 55,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(backgroundColor: bg, foregroundColor: fg, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)), elevation: 0),
        child: _isLoading ? const CircularProgressIndicator(color: Colors.white) : Text(text, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
      ),
    );
  }

  Widget _buildTermsBox() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: const Color(0xFFFBBF24))),
      child: Column(
        children: [
          Row(children: [
            Checkbox(value: _allAgreed, activeColor: const Color(0xFFFBBF24), onChanged: (v) => setState(() {
              _allAgreed = v!; _agreements.fillRange(0, 3, v);
            })),
            const Text('전체 동의', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          ]),
          const Divider(),
          _buildTermItem(0, '[필수] 서비스 이용약관'),
          _buildTermItem(1, '[필수] 개인정보 처리방침'),
          _buildTermItem(2, '[선택] 마케팅 수신 동의'),
        ],
      ),
    );
  }

  Widget _buildTermItem(int idx, String title) {
    return Row(children: [
      Checkbox(value: _agreements[idx], activeColor: const Color(0xFFFBBF24), onChanged: (v) => setState(() {
        _agreements[idx] = v!; _allAgreed = _agreements[0] && _agreements[1];
      })),
      Text(title),
      const Spacer(),
      const Icon(Icons.chevron_right, color: Colors.grey),
    ]);
  }

  Widget _buildEmotionTag(String name, String emoji) {
    bool isSelected = _selectedEmotions.contains(name);
    return GestureDetector(
      onTap: () => setState(() => isSelected ? _selectedEmotions.remove(name) : _selectedEmotions.add(name)),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white, borderRadius: BorderRadius.circular(15),
          border: Border.all(color: isSelected ? const Color(0xFFFBBF24) : Colors.grey[300]!, width: 2),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [Text(emoji, style: const TextStyle(fontSize: 20)), const SizedBox(width: 8), Text(name)],
        ),
      ),
    );
  }

  Widget _buildSocialIcon(String text, Color color) {
    return Container(
      width: 50, height: 50,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle, border: Border.all(color: Colors.grey[300]!)),
      child: Center(child: Text(text, style: TextStyle(fontWeight: FontWeight.bold, color: color == Colors.white ? Colors.black : Colors.white))),
    );
  }
}