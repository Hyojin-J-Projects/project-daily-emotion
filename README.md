# 🧠 AI 감정 다이어리 (Emotion Diary Multi-Modal App)

> **BERT 기반 텍스트 감성 분석**과 **CLIP 기반 이미지 맥락 분석**을 융합한 멀티모달(Multi-Modal) AI 일기장 앱입니다. 사용자의 글과 사진을 분석하여 7대 감정 스펙트럼을 도출하며, 실시간으로 총합 100%가 유지되는 동적 수동 조절 스펙트럼 차트를 제공합니다.

---

## 🚀 주요 기능 (Key Features)

* **멀티모달 감정 융합 엔진**: 텍스트 분석(BERT)과 이미지 분석(CLIP) 결과를 $8:2$ 비율로 동적 융합하여 정밀한 감정 곡선을 도출합니다.
* **학습 데이터셋 문맥 동기화**: 단일 문장 추론의 한계를 극복하기 위해, 모델 학습 규격(`사용자: [...] 시스템: [...]`)과 100% 일치하는 대화형 템플릿 임베딩을 수행합니다.
* **실시간 합산 100% 자동 유지 슬라이더**: 사용자가 특정 감정 수치를 수동으로 변경하면, 나머지 6개 감정의 수치가 기존 지분 비율에 맞춰 공평하게 가감되면서 항상 총합 100%를 유지합니다.
* **감정 타임라인 & 바이오리듬**: 하루 중 누적된 감정 데이터를 기반으로 대시보드 및 웰니스 웰빙 바이오리듬 그래프를 실시간 렌더링합니다.

---

## 📐 시스템 아키텍처 (Architecture)

### 1. 데이터 파이프라인 & 멀티모달 가중치 알고리즘
* **텍스트 처리**: `klue/bert-base` 파인튜닝 모델 가동 ($80\%$ 가중치 반영)
* **이미지 처리**: `openai/clip-vit-base-patch32` 제로샷 프로프팅 가동 ($20\%$ 가중치 반영)

$$\text{Final Probability} = (\text{BERT Prob} \times 0.8) + (\text{CLIP Prob} \times 0.2)$$

### 2. 수동 조절 시 총합 100% 유지 알고리즘 (Proportional Redistribution)
하나의 감정 수치($V_{new}$)가 조절되면, 나머지 감정들이 나눠 가져야 할 목표 잔여량($100 - V_{new}$)을 기존 지분 비율($Weight$)에 맞춰 공평하게 분배합니다.

$$\text{Share}_{i} = (100 - V_{new}) \times \frac{\text{Current Value}_{i}}{\text{Total of Other Values}}$$

---

## 📁 프로젝트 구조 (Directory Structure)

프로젝트는 FastAPI 백엔드 서버와 Flutter 프론트엔드 앱의 2-Tier 아키텍처로 구성되어 있으며, 단 두 개의 메인 스크립트 파일로 핵심 비즈니스 로직을 격리하여 관리합니다.

D:\project\ (Project Root)
├── main.py                          # 🧠 FastAPI 백엔드 멀티모달 서버 핵심 스크립트
├── requirements.txt                 # 🐍 백엔드 파이썬 의존성 패키지 리스트
├── text_train.py                    # 🧪 AI 모델 학습 스크립트
├── text_evaluate_model.py           # 🧪 AI 모델 평가 및 검증 스크립트
├── .gitignore                       # 🚫 깃허브 업로드 제외 규칙 설정 파일
├── README.md                        # 📑 프로젝트 메인 가이드 문서
│
├── models/                          # 📂 AI 모델 저장 폴더 (GitHub 제외)
│   └── my_emotion_model/            # 🎯 Fine-Tuning 완료된 BERT 감정 분석 가중치 파일들
│
├── diary_app/                       # 📂 Flutter 프론트엔드 전용 독립 프로젝트 폴더
│   ├── pubspec.yaml                 # 📦 플러터 패키지 및 에셋 의존성 관리 파일
│   └── lib/                         # 📱 플러터 소스코드 디렉토리
│       ├── main.dart                # ⚡ 가동 UI 및 상태 관리, 100% 동적 슬라이더 핸들러
│       └── emotion_dashboard.dart   # 📊 감정 통계 및 대시보드 화면 UI
│
├── data/                            # 📂 AI 학습용 데이터셋 관리 폴더
├── backup/                          # 📂 원본 백업 데이터 폴더 (GitHub 제외)
└── venv/                            # 📂 파이썬 가상환경 디렉토리 (GitHub 제외)

💻 시작하기 (Getting Started)
Prerequisites
Python 3.8+

TensorFlow 2.x

Flutter 3.x / Dart 3.x

1. Backend (FastAPI) 실행
서버 부팅 시 터미널에서 학습 모델의 id2label 바인딩 차원 검증 스냅샷과 데이터 수신 세션을 실시간으로 모니터링할 수 있습니다.

# 의존성 패키지 설치
pip install fastapi uvicorn tensorflow transformers pillow numpy scalar-fastapi

# 서버 가동 (포트 8000번 가동)
uvicorn main:app --reload

2. Frontend (Flutter) 실행

# 의존성 패키지 가져오기
flutter pub get

# 앱 실행 (로컬 환경 호스트 연결)
flutter run

📡 API 명세 (API Specification)
POST /analyze/
사용자가 입력한 일기 텍스트와 사진 파일을 받아 멀티모달 감정 스펙트럼 수치를 반환합니다.

Form Data (Multipart/Form-Data)

content (Optional[str]): 일기 텍스트 본문

image (Optional[UploadFile]): 첨부한 다이어리 사진 파일

Response (JSON)

{
  "분노": 1.2,
  "불안": 8.4,
  "상처": 3.1,
  "기쁨": 1.5,
  "슬픔": 31.2,
  "놀람": 66.4,
  "일상": 3.2
}

🛠️ 기술 스택 (Tech Stack)
Backend: FastAPI, TensorFlow, Hugging Face Transformers (BERT, CLIP)

Frontend: Flutter (Dart), Table Calendar, HTTP Multi-part Stream

Deployment & Tooling: Scalar OpenAPI Reference, CORS Middleware, Win64/macOS Cross-Platform