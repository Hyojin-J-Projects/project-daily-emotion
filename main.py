import os
import numpy as np
import tensorflow as tf
from PIL import Image
from io import BytesIO
from typing import Optional
from fastapi import FastAPI, UploadFile, File, Form, HTTPException
from transformers import AutoTokenizer, TFAutoModelForSequenceClassification, CLIPProcessor, TFCLIPModel
from scalar_fastapi import get_scalar_api_reference 
from fastapi.middleware.cors import CORSMiddleware

app = FastAPI(title="Emotion Diary Multi-Modal API")
app.openapi_url = "/openapi.json" 

# 🔒 CORS 보안 해제 미들웨어
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# 🎯 감정 매핑 레이블 테이블 (작동 코드의 LABEL_NAMES 정렬 순서 고정 매칭)
# 인덱스 순서 규칙: 0:Anger(분노), 1:Anxiety(불안), 2:Disgust(상처), 3:Joy(기쁨), 4:Other(일상), 5:Sad(슬픔), 6:Surprise(놀람)
KOREAN_LABELS = ['분노', '불안', '상처', '기쁨', '일상', '슬픔', '놀람']

# 📸 CLIP용 프롬프트 및 매핑 스펙
CLIP_PROMPTS = [
    "an angry and furious photo", "an anxious and worried photo", "a disgusting and unpleasant photo",
    "a joyful and happy photo", "a neutral and ordinary photo", "a sad and gloomy photo", "an amazing and wonderful photo"
]
CLIP_MAP = ['anger', 'anxiety', 'disgust', 'joy', 'other', 'sad', 'surprise']
CLIP_LABEL_TO_KOREAN = {
    'anger': '분노', 'anxiety': '불안', 'disgust': '상처', 
    'joy': '기쁨', 'other': '일상', 'sad': '슬픔', 'surprise': '놀람'
}

@app.get("/scalar", include_in_schema=False)
async def scalar_html():
    return get_scalar_api_reference(
        openapi_url=app.openapi_url,
        title=app.title,
    )

tokenizer = None
text_model = None
clip_processor = None
clip_model = None

@app.on_event("startup")
def load_models():
    global tokenizer, text_model, clip_processor, clip_model
    print("🚀 [FastAPI] 감성 분석 멀티모달 엔진 로드 시작...")
    tokenizer = AutoTokenizer.from_pretrained("./models/my_emotion_model")
    text_model = TFAutoModelForSequenceClassification.from_pretrained("./models/my_emotion_model")
    clip_model = TFCLIPModel.from_pretrained("openai/clip-vit-base-patch32")
    clip_processor = CLIPProcessor.from_pretrained("openai/clip-vit-base-patch32")
    print("🎉 [FastAPI] 작동 코드와 100% 동기화된 모든 AI 모델 상주 완료!")

# -----------------------------------------------------------------
# 🔌 [엔진 싱크 융합 파이프라인] 멀티모달 포스트 레일
# -----------------------------------------------------------------
@app.post("/analyze")
@app.post("/analyze/")
async def analyze_diary(
    content: Optional[str] = Form(None),
    image: Optional[UploadFile] = File(None)
):
    try:
        if not content and not image:
            return {"일상": 100.0, "분노": 0.0, "불안": 0.0, "상처": 0.0, "기쁨": 0.0, "슬픔": 0.0, "놀람": 0.0}

        # 결과 저장 구조 선언
        flutter_formatted_results = {"분노": 0.0, "불안": 0.0, "상처": 0.0, "기쁨": 0.0, "슬픔": 0.0, "놀람": 0.0, "일상": 0.0}
        text_probs_dict = {"분노": 0.0, "불안": 0.0, "상처": 0.0, "기쁨": 0.0, "슬픔": 0.0, "놀람": 0.0, "일상": 0.0}
        image_probs_dict = {}

        # 1. 📝 일기 글(content) BERT 가동 부위 (제공해주신 추적 작동 코드 로직 100% 구현)
        if content and str(content).strip() and str(content) != "null":
            raw_memo = str(content).strip()
            
            # [방어 로직] 3글자 미만은 일상(Other) 처리
            if len(raw_memo) < 3:
                text_probs_dict["일상"] = 1.0
            else:
                # [템플릿 싱크] 학습/추론 때와 동일한 빈 컨텍스트 문맥 구조 주입
                inference_text = f"사용자: {raw_memo} 시스템:  사용자: "
                
                # 전처리 토크나이징 (MAX_LEN=128)
                encodings = tokenizer(
                    inference_text, 
                    padding='max_length', 
                    truncation=True, 
                    max_length=128, 
                    return_tensors='tf'
                )
                
                # 모델 예측 
                outputs = text_model(
                    input_ids=tf.cast(encodings['input_ids'], tf.int32), 
                    attention_mask=tf.cast(encodings['attention_mask'], tf.int32)
                )
                logits = outputs.logits
                
                # 💡 [치명적 버그 수정 부위]: 작동 코드와 완벽히 동일하게 [0]을 통해 1차원 확률 배열화 가동!
                raw_text_probs = tf.nn.softmax(logits, axis=-1).numpy()[0]
                
                # 제공해주신 고유 감정 규칙 순서대로 한글 데이터 주머니 매핑 (배열 누락 차단)
                for idx, prob in enumerate(raw_text_probs[:7]):
                    korean_key = KOREAN_LABELS[idx]
                    text_probs_dict[korean_key] = float(prob)

        # 2. 📸 이미지 파일 CLIP 가동
        if image and hasattr(image, "filename") and image.filename:
            try:
                image_bytes = await image.read()
                if image_bytes and len(image_bytes) > 0:
                    pil_image = Image.open(BytesIO(image_bytes)).convert("RGB")
                    clip_inputs = clip_processor(text=CLIP_PROMPTS, images=pil_image, return_tensors="tf", padding=True)
                    clip_outputs = clip_model(clip_inputs)
                    
                    raw_image_probs = tf.nn.softmax(clip_outputs.logits_per_image, axis=-1).numpy()[0]
                    
                    for i, prob in enumerate(raw_image_probs):
                        clip_label = CLIP_MAP[i]
                        korean_key = CLIP_LABEL_TO_KOREAN.get(clip_label, "일상")
                        image_probs_dict[korean_key] = float(prob)
            except Exception as img_err:
                print(f"⚠️ [이미지 파싱 예외 로그]: {str(img_err)}")

        # 3. ⚖️ 상황별 가중치 동적 매칭 융합 알고리즘
        has_text = content and str(content).strip() and str(content) != "null"
        has_image = len(image_probs_dict) > 0

        for emotion in flutter_formatted_results.keys():
            t_val = text_probs_dict.get(emotion, 0.0)
            i_val = image_probs_dict.get(emotion, 0.0)
            
            if has_text and has_image:
                final_prob = (t_val * 0.8) + (i_val * 0.2)
            elif has_text:
                final_prob = t_val
            elif has_image:
                final_prob = i_val
            else:
                final_prob = 1.0 if emotion == "일상" else 0.0
                
            flutter_formatted_results[emotion] = float(round(final_prob * 100, 1))

        # 📊 실시간 수치 역동적 소팅 모니터링 레이아웃
        print("\n" + "="*60)
        print("🧠 [멀티모달 감정 분석 엔진 실시간 파이프라인 수치 스캔]")
        print("="*60)
        if has_text and len(raw_memo) >= 3:
            text_sorted = sorted([(k, v * 100) for k, v in text_probs_dict.items()], key=lambda x: x[1], reverse=True)
            text_items = [f"'{k}': '{v:.1f}%'" for k, v in text_sorted]
            print(f"📝 [1. BERT 작동 코드 동기화형 텍스트 분석 수치]:\n   -> {{ {', '.join(text_items)} }}")
        elif has_text:
            print("📝 [1. BERT 작동 코드 동기화형 텍스트 분석 수치]: 3글자 미만 강제 중립 스킵 처리")
        else:
            print("📝 [1. BERT 작동 코드 동기화형 텍스트 분석 수치]: 입력 글 없음")
            
        if has_image:
            image_sorted = sorted([(k, v * 100) for k, v in image_probs_dict.items()], key=lambda x: x[1], reverse=True)
            image_items = [f"'{k}': '{v:.1f}%'" for k, v in image_sorted]
            print(f"📸 [2. CLIP 오리지널 이미지 분석 수치]:\n   -> {{ {', '.join(image_items)} }}")
        else:
            print("📸 [2. CLIP 오리지널 이미지 분석 수치]: 입력 사진 없음")
            
        print("-"*60)
        fusion_sorted = sorted(flutter_formatted_results.items(), key=lambda x: x[1], reverse=True)
        fusion_items = [f"'{k}': '{v}%'" for k, v in fusion_sorted if v > 0.0]
        print(f"⚖️ [3. 최종 가중치 퓨전 결과 (Flutter 앱 전송용)]:\n   -> {{ {', '.join(fusion_items)} }}")
        print("="*60 + "\n")

        return flutter_formatted_results
        
    except Exception as e:
        print(f"❌ 연산 에러: {str(e)}")
        return {"일상": 100.0, "분노": 0.0, "불안": 0.0, "상처": 0.0, "기쁨": 0.0, "슬픔": 0.0, "놀람": 0.0}